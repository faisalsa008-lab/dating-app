import 'package:flutter/foundation.dart';

/// Which slice of nearby people the radar shows.
enum DiscoveryMode {
  social('Dating / Hangout', ['dating', 'hangout']),
  riders('Biker Clubs', ['riding']);

  const DiscoveryMode(this.label, this.intents);
  final String label;

  /// Matched against `profiles.intents` (array overlap) by the RPC.
  final List<String> intents;
}

String formatDistance(num meters) {
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000;
  final text = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text} km';
}

@immutable
class NearbyUser {
  const NearbyUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.intents,
    required this.fuzzedLat,
    required this.fuzzedLng,
    required this.distanceM,
    required this.bearingDeg,
    this.avatarUrl,
    this.bio,
    this.interests = const [],
    this.age,
    this.bikeModel,
    this.sharedClubs = 0,
    this.isOnline = false,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final List<String> intents;
  final List<String> interests;
  final int? age;
  final String? bikeModel;

  /// Server-fuzzed position (100-300 m displacement). The real one never reaches the client.
  final double fuzzedLat;
  final double fuzzedLng;

  /// Distance from the caller to the FUZZED point, rounded to 100 m.
  final int distanceM;

  /// Compass bearing (0 = north, clockwise) from the caller to the fuzzed point.
  final double bearingDeg;
  final int sharedClubs;
  final bool isOnline;

  bool get isRider => intents.contains('riding');
  String get approxDistanceLabel => '~${formatDistance(distanceM)}';
  String get initial =>
      displayName.isEmpty ? '?' : String.fromCharCode(displayName.runes.first).toUpperCase();
}
