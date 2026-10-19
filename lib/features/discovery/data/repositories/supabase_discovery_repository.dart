import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_exceptions.dart';
import '../../domain/entities/nearby_user.dart';
import '../../domain/repositories/discovery_repository.dart';
import '../dtos/nearby_user_dto.dart';

final class SupabaseDiscoveryRepository implements DiscoveryRepository {
  const SupabaseDiscoveryRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<void> updateMyLocation(double lat, double lng) =>
      _guard(() => _client.rpc('update_my_location', params: {'p_lat': lat, 'p_lng': lng}));

  @override
  Future<List<NearbyUser>> getNearbyUsers({
    required double lat,
    required double lng,
    required double radiusKm,
    required DiscoveryMode mode,
  }) {
    return _guard(() async {
      final rows = await _client.rpc('get_nearby_users_fuzzed', params: {
        'p_lat': lat,
        'p_lng': lng,
        'p_radius_km': radiusKm,
        'p_intents': mode.intents,
      }) as List<dynamic>;
      return rows
          .map((r) => NearbyUserDto.fromJson(r as Map<String, dynamic>))
          .toList(growable: false);
    });
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on PostgrestException catch (e) {
      throw DiscoveryException(
        switch (e.code) {
          '42501' => 'Add your birth date (18+) in your profile to use discovery.',
          '28000' => 'Please sign in to see who is nearby.',
          _ => 'Could not load nearby people. ${e.message}',
        },
        code: e.code,
      );
    }
  }
}
