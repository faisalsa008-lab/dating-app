import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../../core/location/location_service.dart';
import '../../data/repositories/demo_discovery_repository.dart';
import '../../data/repositories/supabase_discovery_repository.dart';
import '../../domain/entities/nearby_user.dart';
import '../../domain/repositories/discovery_repository.dart';

// ----------------------------------------------------------------- infrastructure

final locationServiceProvider = Provider<LocationService>((ref) {
  if (Env.demoMode) return const FixedLocationService((lat: 51.5074, lng: -0.1278));
  return const GeolocatorLocationService();
});

final discoveryRepositoryProvider = Provider<DiscoveryRepository>((ref) {
  if (Env.demoMode) return const DemoDiscoveryRepository();
  return SupabaseDiscoveryRepository(Supabase.instance.client);
});

// ----------------------------------------------------------------- UI filters

class DiscoveryModeNotifier extends Notifier<DiscoveryMode> {
  @override
  DiscoveryMode build() => DiscoveryMode.social;

  void select(DiscoveryMode mode) => state = mode;
}

final discoveryModeProvider =
    NotifierProvider<DiscoveryModeNotifier, DiscoveryMode>(DiscoveryModeNotifier.new);

class DiscoveryRadiusNotifier extends Notifier<double> {
  @override
  double build() => 10;

  void select(double km) => state = km;
}

final discoveryRadiusProvider =
    NotifierProvider<DiscoveryRadiusNotifier, double>(DiscoveryRadiusNotifier.new);

// ----------------------------------------------------------------- data

@immutable
class DiscoverySnapshot {
  const DiscoverySnapshot({
    required this.users,
    required this.mode,
    required this.radiusKm,
    required this.fetchedAt,
  });

  final List<NearbyUser> users;
  final DiscoveryMode mode;
  final double radiusKm;
  final DateTime fetchedAt;

  /// True when this data was fetched for the filters currently selected in the UI.
  bool matches(DiscoveryMode m, double km) => mode == m && radiusKm == km;
}

/// Loads nearby people for the selected mode + radius. Re-runs automatically when
/// either changes, and refreshes itself every 45 s while the radar is on screen.
class DiscoveryNotifier extends AutoDisposeAsyncNotifier<DiscoverySnapshot> {
  static const _autoRefresh = Duration(seconds: 45);

  @override
  Future<DiscoverySnapshot> build() async {
    final mode = ref.watch(discoveryModeProvider);
    final radiusKm = ref.watch(discoveryRadiusProvider);

    // One-shot timer, re-armed on every rebuild (also retries after an error).
    final timer = Timer(_autoRefresh, ref.invalidateSelf);
    ref.onDispose(timer.cancel);

    final here = await ref.read(locationServiceProvider).currentPosition();
    final repo = ref.read(discoveryRepositoryProvider);
    await repo.updateMyLocation(here.lat, here.lng);
    final users = await repo.getNearbyUsers(
      lat: here.lat,
      lng: here.lng,
      radiusKm: radiusKm,
      mode: mode,
    );
    return DiscoverySnapshot(
      users: users,
      mode: mode,
      radiusKm: radiusKm,
      fetchedAt: DateTime.now(),
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      // Surfaced through the AsyncValue state; nothing to rethrow here.
    }
  }
}

final discoveryProvider =
    AsyncNotifierProvider.autoDispose<DiscoveryNotifier, DiscoverySnapshot>(DiscoveryNotifier.new);
