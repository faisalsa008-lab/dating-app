import '../../domain/entities/nearby_user.dart';

/// Maps one row of `get_nearby_users_fuzzed` to the domain entity.
abstract final class NearbyUserDto {
  static NearbyUser fromJson(Map<String, dynamic> j) {
    List<String> strings(Object? v) => v == null ? const [] : List<String>.from(v as List);

    return NearbyUser(
      id: j['user_id'] as String,
      username: j['username'] as String,
      displayName: j['display_name'] as String,
      avatarUrl: j['avatar_url'] as String?,
      bio: j['bio'] as String?,
      intents: strings(j['intents']),
      interests: strings(j['interests']),
      age: (j['age'] as num?)?.toInt(),
      bikeModel: j['bike_model'] as String?,
      fuzzedLat: (j['fuzzed_lat'] as num).toDouble(),
      fuzzedLng: (j['fuzzed_lng'] as num).toDouble(),
      distanceM: (j['distance_m'] as num).toInt(),
      bearingDeg: (j['bearing_deg'] as num).toDouble(),
      sharedClubs: (j['shared_clubs'] as num?)?.toInt() ?? 0,
      isOnline: j['is_online'] as bool? ?? false,
    );
  }
}
