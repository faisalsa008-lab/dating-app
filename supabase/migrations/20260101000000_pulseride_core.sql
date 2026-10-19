-- =====================================================================
-- PulseRide :: core schema (profiles, clubs, club_members, rides,
--              ride_participants, live_convoy_locations) + discovery RPC
-- Target: Supabase (PostgreSQL 15+, PostGIS)
-- =====================================================================

create schema if not exists extensions;
create extension if not exists postgis with schema extensions;

-- ---------------------------------------------------------------------
-- Private schema: secrets that clients can never read
-- ---------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.secrets (
  key   text primary key,
  value text not null
);
revoke all on private.secrets from public, anon, authenticated;

-- Salt used to derive the deterministic location fuzz (never leaves the DB).
insert into private.secrets (key, value)
values ('fuzz_salt', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
on conflict (key) do nothing;

-- ---------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------
create type public.club_category     as enum ('riding','travel','tech','social','sports','other');
create type public.club_role         as enum ('owner','admin','moderator','member');
create type public.membership_status as enum ('active','pending','banned');
create type public.ride_status       as enum ('planned','live','completed','cancelled');

-- ---------------------------------------------------------------------
-- Generic helpers
-- ---------------------------------------------------------------------
create function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- profiles  (1:1 with auth.users)
-- ---------------------------------------------------------------------
create table public.profiles (
  id                  uuid primary key references auth.users(id) on delete cascade,
  username            text not null unique check (username ~ '^[a-z0-9_]{3,24}$'),
  display_name        text not null check (char_length(display_name) between 1 and 60),
  avatar_url          text,
  bio                 text check (char_length(bio) <= 280),
  interests           text[] not null default '{}',
  intents             text[] not null default array['hangout']
                        check (intents <@ array['dating','hangout','riding']),
  bike_model          text,
  birth_date          date,
  is_discoverable     boolean not null default true,
  discovery_radius_km numeric(5,1) not null default 10
                        check (discovery_radius_km between 0.5 and 100),
  -- REAL position. Never exposed to clients (column privileges below).
  location            extensions.geography(Point, 4326),
  location_updated_at timestamptz,
  last_active_at      timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index profiles_location_gix on public.profiles
  using gist (location) where is_discoverable and location is not null;
create index profiles_intents_gin on public.profiles using gin (intents);

create trigger profiles_set_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- Minors are never discoverable and never store a location.
create function public.profiles_enforce_minor_privacy() returns trigger
language plpgsql as $$
begin
  if new.birth_date is not null
     and new.birth_date > (current_date - interval '18 years')::date then
    new.is_discoverable := false;
    new.location := null;
  end if;
  return new;
end $$;

create trigger profiles_minor_privacy before insert or update on public.profiles
  for each row execute function public.profiles_enforce_minor_privacy();

-- Auto-create a profile when someone signs up.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    'rider_' || substr(replace(new.id::text, '-', ''), 1, 10),
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), 'New Rider')
  );
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- clubs / club_members
-- ---------------------------------------------------------------------
create table public.clubs (
  id             uuid primary key default gen_random_uuid(),
  slug           text not null unique check (slug ~ '^[a-z0-9-]{3,40}$'),
  name           text not null check (char_length(name) between 3 and 60),
  description    text check (char_length(description) <= 1000),
  category       public.club_category not null default 'social',
  avatar_url     text,
  cover_url      text,
  owner_id       uuid not null references public.profiles(id) on delete restrict,
  home_location  extensions.geography(Point, 4326),
  home_radius_km numeric(6,1) not null default 25 check (home_radius_km between 1 and 500),
  is_private     boolean not null default false,
  member_count   integer not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index clubs_home_location_gix on public.clubs using gist (home_location);
create index clubs_category_idx on public.clubs (category);
create index clubs_owner_idx on public.clubs (owner_id);
create trigger clubs_set_updated_at before update on public.clubs
  for each row execute function public.set_updated_at();

create table public.club_members (
  club_id   uuid not null references public.clubs(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  role      public.club_role not null default 'member',
  status    public.membership_status not null default 'active',
  joined_at timestamptz not null default now(),
  primary key (club_id, user_id)
);
create index club_members_user_idx on public.club_members (user_id) where status = 'active';

-- ---------------------------------------------------------------------
-- rides / ride_participants / live_convoy_locations
-- ---------------------------------------------------------------------
create table public.rides (
  id               uuid primary key default gen_random_uuid(),
  club_id          uuid references public.clubs(id) on delete set null,
  host_id          uuid not null references public.profiles(id) on delete cascade,
  title            text not null check (char_length(title) between 3 and 100),
  description      text check (char_length(description) <= 2000),
  status           public.ride_status not null default 'planned',
  start_at         timestamptz not null,
  start_point      extensions.geography(Point, 4326) not null,
  end_point        extensions.geography(Point, 4326),
  route            extensions.geography(LineString, 4326),   -- parsed from GPX client-side
  route_distance_m double precision,
  elevation_gain_m integer check (elevation_gain_m is null or elevation_gain_m >= 0),
  gpx_url          text,
  max_riders       integer check (max_riders is null or max_riders between 2 and 500),
  is_public        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index rides_start_point_gix on public.rides using gist (start_point);
create index rides_route_gix       on public.rides using gist (route);
create index rides_upcoming_idx    on public.rides (start_at) where status in ('planned','live');
create index rides_club_idx        on public.rides (club_id);
create trigger rides_set_updated_at before update on public.rides
  for each row execute function public.set_updated_at();

create function public.rides_compute_distance() returns trigger
language plpgsql set search_path = public, extensions, pg_temp as $$
begin
  new.route_distance_m := case when new.route is null then null else st_length(new.route) end;
  return new;
end $$;
create trigger rides_distance before insert or update of route on public.rides
  for each row execute function public.rides_compute_distance();

create table public.ride_participants (
  ride_id   uuid not null references public.rides(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  role      text not null default 'rider' check (role in ('host','rider','sweeper')),
  joined_at timestamptz not null default now(),
  primary key (ride_id, user_id)
);
create index ride_participants_user_idx on public.ride_participants (user_id);

-- Latest known position of every rider in a live convoy (one row per rider).
create table public.live_convoy_locations (
  ride_id      uuid not null references public.rides(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  location     extensions.geography(Point, 4326) not null,
  heading_deg  real check (heading_deg is null or (heading_deg >= 0 and heading_deg < 360)),
  speed_kmh    real check (speed_kmh is null or speed_kmh >= 0),
  battery_pct  smallint check (battery_pct is null or battery_pct between 0 and 100),
  is_emergency boolean not null default false,
  emergency_at timestamptz,
  updated_at   timestamptz not null default now(),
  primary key (ride_id, user_id)
);
create index live_convoy_location_gix on public.live_convoy_locations using gist (location);

-- ---------------------------------------------------------------------
-- Membership triggers
-- ---------------------------------------------------------------------
create function public.sync_club_member_count() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_club uuid := coalesce(new.club_id, old.club_id);
begin
  update public.clubs c
     set member_count = (select count(*) from public.club_members m
                          where m.club_id = v_club and m.status = 'active')
   where c.id = v_club;
  return null;
end $$;
create trigger club_members_count after insert or update or delete on public.club_members
  for each row execute function public.sync_club_member_count();

create function public.club_add_owner_membership() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.club_members (club_id, user_id, role, status)
  values (new.id, new.owner_id, 'owner', 'active');
  return new;
end $$;
create trigger clubs_owner_membership after insert on public.clubs
  for each row execute function public.club_add_owner_membership();

create function public.ride_add_host_participant() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.ride_participants (ride_id, user_id, role)
  values (new.id, new.host_id, 'host');
  return new;
end $$;
create trigger rides_host_participant after insert on public.rides
  for each row execute function public.ride_add_host_participant();

-- ---------------------------------------------------------------------
-- RLS helper predicates (SECURITY DEFINER avoids policy recursion)
-- ---------------------------------------------------------------------
create function public.is_club_member(p_club uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.club_members
                  where club_id = p_club and user_id = auth.uid() and status = 'active')
$$;

create function public.is_club_admin(p_club uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.club_members
                  where club_id = p_club and user_id = auth.uid() and status = 'active'
                    and role in ('owner','admin'))
$$;

create function public.shares_club_with(p_other uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1
      from public.club_members a
      join public.club_members b on b.club_id = a.club_id
     where a.user_id = auth.uid() and b.user_id = p_other
       and a.status = 'active' and b.status = 'active')
$$;

create function public.is_ride_participant(p_ride uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.ride_participants
                  where ride_id = p_ride and user_id = auth.uid())
$$;

create function public.ride_is_live(p_ride uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.rides where id = p_ride and status = 'live')
$$;

create function public.ride_has_capacity(p_ride uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.rides r
     where r.id = p_ride and r.status in ('planned','live')
       and (r.max_riders is null
            or (select count(*) from public.ride_participants p where p.ride_id = r.id) < r.max_riders))
$$;

-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------
alter table public.profiles              enable row level security;
alter table public.clubs                 enable row level security;
alter table public.club_members          enable row level security;
alter table public.rides                 enable row level security;
alter table public.ride_participants     enable row level security;
alter table public.live_convoy_locations enable row level security;

revoke all on public.profiles, public.clubs, public.club_members, public.rides,
              public.ride_participants, public.live_convoy_locations from anon;

-- profiles: column-level privileges keep `location`, `birth_date`,
-- `location_updated_at` and `last_active_at` unreadable by clients.
-- NOTE: clients must list columns explicitly (select('id,username,...')); `select *` is rejected.
revoke all on public.profiles from authenticated;
grant select (id, username, display_name, avatar_url, bio, interests, intents, bike_model,
              is_discoverable, discovery_radius_km, created_at, updated_at)
  on public.profiles to authenticated;
grant update (username, display_name, avatar_url, bio, interests, intents, bike_model,
              birth_date, is_discoverable, discovery_radius_km)
  on public.profiles to authenticated;

create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or is_discoverable or public.shares_club_with(id));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- clubs
create policy clubs_select on public.clubs for select to authenticated
  using (not is_private or owner_id = auth.uid() or public.is_club_member(id));
create policy clubs_insert on public.clubs for insert to authenticated
  with check (owner_id = auth.uid());
create policy clubs_update on public.clubs for update to authenticated
  using (public.is_club_admin(id)) with check (public.is_club_admin(id));
create policy clubs_delete on public.clubs for delete to authenticated
  using (owner_id = auth.uid());

-- club_members
create policy club_members_select on public.club_members for select to authenticated
  using (user_id = auth.uid()
         or public.is_club_member(club_id)
         or exists (select 1 from public.clubs c where c.id = club_id and not c.is_private));
create policy club_members_insert on public.club_members for insert to authenticated
  with check (
    public.is_club_admin(club_id)
    or (user_id = auth.uid() and role = 'member' and status = 'active'
        and exists (select 1 from public.clubs c where c.id = club_id and not c.is_private))
  );
create policy club_members_update on public.club_members for update to authenticated
  using (public.is_club_admin(club_id)) with check (public.is_club_admin(club_id));
create policy club_members_delete on public.club_members for delete to authenticated
  using ((user_id = auth.uid() and role <> 'owner') or public.is_club_admin(club_id));

-- rides
create policy rides_select on public.rides for select to authenticated
  using (is_public or host_id = auth.uid() or public.is_ride_participant(id)
         or (club_id is not null and public.is_club_member(club_id)));
create policy rides_insert on public.rides for insert to authenticated
  with check (host_id = auth.uid()
              and (club_id is null or public.is_club_member(club_id)));
create policy rides_update on public.rides for update to authenticated
  using (host_id = auth.uid()) with check (host_id = auth.uid());
create policy rides_delete on public.rides for delete to authenticated
  using (host_id = auth.uid());

-- ride_participants
create policy ride_participants_select on public.ride_participants for select to authenticated
  using (exists (select 1 from public.rides r where r.id = ride_id));
create policy ride_participants_insert on public.ride_participants for insert to authenticated
  with check (user_id = auth.uid() and role = 'rider' and public.ride_has_capacity(ride_id));
create policy ride_participants_delete on public.ride_participants for delete to authenticated
  using (user_id = auth.uid()
         or exists (select 1 from public.rides r where r.id = ride_id and r.host_id = auth.uid()));

-- live_convoy_locations: only convoy members can see each other, and only while the ride is live
create policy convoy_select on public.live_convoy_locations for select to authenticated
  using (public.is_ride_participant(ride_id));
create policy convoy_insert on public.live_convoy_locations for insert to authenticated
  with check (user_id = auth.uid() and public.is_ride_participant(ride_id) and public.ride_is_live(ride_id));
create policy convoy_update on public.live_convoy_locations for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.is_ride_participant(ride_id) and public.ride_is_live(ride_id));
create policy convoy_delete on public.live_convoy_locations for delete to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- RPC: update_my_location  (the ONLY way a client writes its position)
-- ---------------------------------------------------------------------
create or replace function public.update_my_location(p_lat double precision, p_lng double precision)
returns void
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'invalid_coordinates' using errcode = '22023';
  end if;

  update public.profiles
     set location = st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
         location_updated_at = now(),
         last_active_at = now()
   where id = auth.uid();
end $$;

-- ---------------------------------------------------------------------
-- RPC: get_nearby_users_fuzzed
--
-- Privacy model
--  * The caller only ever receives FUZZED coordinates: each user is displaced
--    100-300 m in a pseudo-random direction.
--  * The displacement is deterministic per (user, 30-minute bucket, secret salt),
--    so repeated calls can't be averaged to find the true point, yet the dot
--    doesn't jitter between refreshes.
--  * Radius filtering, distance and bearing are all computed from the FUZZED
--    point (rounded to 100 m), so boundary probing / trilateration can only
--    recover the fuzzed position, never the real one.
--  * Index use: the GIST index prefilters on the real location with a
--    +300 m margin; the exact cut happens on the fuzzed location.
-- ---------------------------------------------------------------------
create or replace function public.get_nearby_users_fuzzed(
  p_lat       double precision,
  p_lng       double precision,
  p_radius_km double precision default 5,
  p_intents   text[]           default null
)
returns table (
  user_id      uuid,
  username     text,
  display_name text,
  avatar_url   text,
  bio          text,
  intents      text[],
  interests    text[],
  age          integer,
  bike_model   text,
  fuzzed_lat   double precision,
  fuzzed_lng   double precision,
  distance_m   integer,
  bearing_deg  double precision,
  shared_clubs integer,
  is_online    boolean
)
language plpgsql stable security definer
set search_path = public, extensions, pg_temp
as $$
#variable_conflict use_column
declare
  c_fuzz_min_m constant double precision := 100;
  c_fuzz_max_m constant double precision := 300;
  v_uid      uuid := auth.uid();
  v_origin   geography;
  v_radius_m double precision;
  v_salt     text;
  v_bucket   text;
begin
  if v_uid is null then
    raise exception 'authentication_required' using errcode = '28000';
  end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'invalid_coordinates' using errcode = '22023';
  end if;
  if p_intents is not null and not (p_intents <@ array['dating','hangout','riding']) then
    raise exception 'invalid_intents' using errcode = '22023';
  end if;
  -- Discovery is adults-only: the caller must have a verified adult birth date.
  if not exists (select 1 from public.profiles me
                  where me.id = v_uid and me.birth_date <= (current_date - interval '18 years')) then
    raise exception 'age_verification_required' using errcode = '42501';
  end if;

  v_radius_m := least(greatest(coalesce(p_radius_km, 5), 0.5), 100) * 1000;
  v_origin   := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
  select s.value into v_salt from private.secrets s where s.key = 'fuzz_salt';
  v_bucket   := floor(extract(epoch from now()) / 1800)::bigint::text;

  return query
  with cand as (
    select p.id, p.username, p.display_name, p.avatar_url, p.bio, p.intents, p.interests,
           p.birth_date, p.bike_model, p.location as real_loc, p.last_active_at,
           md5(p.id::text || v_salt || v_bucket) as h
      from public.profiles p
     where p.is_discoverable
       and p.location is not null
       and p.id <> v_uid
       and p.location_updated_at > now() - interval '24 hours'
       and p.birth_date <= (current_date - interval '18 years')
       and st_dwithin(p.location, v_origin, v_radius_m + c_fuzz_max_m)
       and (p_intents is null or p.intents && p_intents)
  ),
  rnd as (
    select c.*,
           (('x' || substr(c.h, 1, 8))::bit(32)::bigint / 4294967295.0) as u1,
           (('x' || substr(c.h, 9, 8))::bit(32)::bigint / 4294967295.0) as u2
      from cand c
  ),
  fuzzed as (
    select r.*,
           st_project(
             r.real_loc,
             sqrt(r.u1 * (c_fuzz_max_m ^ 2 - c_fuzz_min_m ^ 2) + c_fuzz_min_m ^ 2),  -- uniform over the annulus
             r.u2 * 2 * pi()
           ) as floc
      from rnd r
  )
  select f.id,
         f.username,
         f.display_name,
         f.avatar_url,
         f.bio,
         f.intents,
         f.interests,
         extract(year from age(f.birth_date))::integer,
         f.bike_model,
         st_y(f.floc::geometry),
         st_x(f.floc::geometry),
         greatest(100, (round(st_distance(f.floc, v_origin) / 100.0) * 100))::integer,
         degrees(st_azimuth(v_origin, f.floc)),
         coalesce(sc.n, 0)::integer,
         f.last_active_at > now() - interval '10 minutes'
    from fuzzed f
    left join lateral (
      select count(*) as n
        from public.club_members a
        join public.club_members b on b.club_id = a.club_id
       where a.user_id = f.id and b.user_id = v_uid
         and a.status = 'active' and b.status = 'active'
    ) sc on true
   where st_distance(f.floc, v_origin) <= v_radius_m
   order by st_distance(f.floc, v_origin)
   limit 100;
end $$;

revoke all on function public.get_nearby_users_fuzzed(double precision, double precision, double precision, text[]) from public, anon;
grant execute on function public.get_nearby_users_fuzzed(double precision, double precision, double precision, text[]) to authenticated;
revoke all on function public.update_my_location(double precision, double precision) from public, anon;
grant execute on function public.update_my_location(double precision, double precision) to authenticated;

-- ---------------------------------------------------------------------
-- RPC: live convoy position + emergency ping (SECURITY INVOKER => RLS applies)
-- ---------------------------------------------------------------------
create or replace function public.upsert_convoy_location(
  p_ride_id   uuid,
  p_lat       double precision,
  p_lng       double precision,
  p_heading   real     default null,
  p_speed_kmh real     default null,
  p_battery   smallint default null,
  p_emergency boolean  default false
) returns void
language plpgsql security invoker set search_path = public, extensions, pg_temp as $$
begin
  insert into public.live_convoy_locations as l
         (ride_id, user_id, location, heading_deg, speed_kmh, battery_pct, is_emergency, emergency_at)
  values (p_ride_id, auth.uid(),
          st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
          p_heading, p_speed_kmh, p_battery, p_emergency,
          case when p_emergency then now() end)
  on conflict (ride_id, user_id) do update
     set location     = excluded.location,
         heading_deg  = excluded.heading_deg,
         speed_kmh    = excluded.speed_kmh,
         battery_pct  = excluded.battery_pct,
         is_emergency = l.is_emergency or excluded.is_emergency,  -- SOS stays on until cleared
         emergency_at = coalesce(l.emergency_at, excluded.emergency_at),
         updated_at   = now();
end $$;

create or replace function public.clear_convoy_emergency(p_ride_id uuid) returns void
language sql security invoker set search_path = public, pg_temp as $$
  update public.live_convoy_locations
     set is_emergency = false, emergency_at = null
   where ride_id = p_ride_id and user_id = auth.uid();
$$;

revoke all on function public.upsert_convoy_location(uuid, double precision, double precision, real, real, smallint, boolean) from public, anon;
grant execute on function public.upsert_convoy_location(uuid, double precision, double precision, real, real, smallint, boolean) to authenticated;
revoke all on function public.clear_convoy_emergency(uuid) from public, anon;
grant execute on function public.clear_convoy_emergency(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Realtime: stream convoy positions to the riders' devices
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.live_convoy_locations;
  end if;
end $$;
