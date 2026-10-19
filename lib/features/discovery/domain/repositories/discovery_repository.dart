import '../entities/nearby_user.dart';

abstract interface class DiscoveryRepository {
  Future<void> updateMyLocation(double lat, double lng);

  Future<List<NearbyUser>> getNearbyUsers({
    required double lat,
    required double lng,
    required double radiusKm,
    required DiscoveryMode mode,
  });
}
