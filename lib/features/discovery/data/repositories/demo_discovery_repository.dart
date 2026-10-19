import 'dart:math' as math;

import '../../domain/entities/nearby_user.dart';
import '../../domain/repositories/discovery_repository.dart';

/// Offline fixture so the radar can be previewed without Supabase
/// (`--dart-define=PULSERIDE_DEMO=true`). Same contract as the real repository.
final class DemoDiscoveryRepository implements DiscoveryRepository {
  const DemoDiscoveryRepository();

  static const _people = <({String name, String bio, List<String> intents, String? bike})>[
    (name: 'Anjali', bio: 'Coffee, coastal roads and bad puns.', intents: ['hangout', 'dating'], bike: null),
    (name: 'Rohan', bio: 'Himalayan 450 | weekend Peak District runs.', intents: ['riding', 'hangout'], bike: 'Royal Enfield Himalayan 450'),
    (name: 'Maya', bio: 'New in town, looking for gig buddies.', intents: ['dating', 'hangout'], bike: null),
    (name: 'Liam', bio: 'Track days and tea stops.', intents: ['riding'], bike: 'Triumph Street Triple'),
    (name: 'Sneha', bio: 'Product designer. Pizza critic.', intents: ['hangout'], bike: null),
    (name: 'Arjun', bio: 'Convoy lead for UK Malayali Riders.', intents: ['riding', 'hangout'], bike: 'KTM 390 Adventure'),
    (name: 'Zoe', bio: 'Climbing, sourdough, synthwave.', intents: ['dating'], bike: null),
    (name: 'Kabir', bio: 'Ex-courier, forever on two wheels.', intents: ['riding'], bike: 'Yamaha MT-07'),
    (name: 'Nia', bio: 'Photographer chasing golden hour.', intents: ['hangout', 'dating'], bike: null),
    (name: 'Dev', bio: 'London Techies organiser.', intents: ['hangout'], bike: null),
    (name: 'Isha', bio: 'Pillion turned rider, 2 years in.', intents: ['riding', 'dating'], bike: 'Honda CB300R'),
    (name: 'Tariq', bio: 'Night rides and chai.', intents: ['riding', 'hangout'], bike: 'Ducati Monster'),
    (name: 'Mei', bio: 'Board games and long walks.', intents: ['hangout'], bike: null),
    (name: 'Jon', bio: 'Touring the NC500 next spring.', intents: ['riding'], bike: 'BMW R1250GS'),
  ];

  static const _origin = (lat: 51.5074, lng: -0.1278);

  @override
  Future<void> updateMyLocation(double lat, double lng) async {}

  @override
  Future<List<NearbyUser>> getNearbyUsers({
    required double lat,
    required double lng,
    required double radiusKm,
    required DiscoveryMode mode,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final rng = math.Random(42);
    final users = <NearbyUser>[];

    for (final (i, p) in _people.indexed) {
      // Draw first so positions stay stable across modes.
      final spread = math.pow(rng.nextDouble(), 1.3).toDouble();
      final distance = (math.max(100, spread * radiusKm * 1000) / 100).round() * 100;
      final bearing = rng.nextDouble() * 360;
      if (!p.intents.any(mode.intents.contains)) continue;

      final rad = bearing * math.pi / 180;
      users.add(NearbyUser(
        id: 'demo-$i',
        username: p.name.toLowerCase(),
        displayName: p.name,
        bio: p.bio,
        intents: p.intents,
        age: 22 + (i * 3) % 14,
        bikeModel: p.bike,
        fuzzedLat: _origin.lat + distance * math.cos(rad) / 111320,
        fuzzedLng: _origin.lng +
            distance * math.sin(rad) / (111320 * math.cos(_origin.lat * math.pi / 180)),
        distanceM: distance,
        bearingDeg: bearing,
        sharedClubs: i % 4 == 1 ? 2 : (i % 5 == 0 ? 1 : 0),
        isOnline: i % 3 != 0,
      ));
    }
    users.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return users;
  }
}
