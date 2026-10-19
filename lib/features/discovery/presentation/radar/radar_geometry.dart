import 'dart:math' as math;
import 'dart:ui';

import '../../domain/entities/nearby_user.dart';

/// Maps real-world distance to radar geometry. Shared by the painter (rings, blips)
/// and the avatar widgets so everything lines up.
class RadarLayout {
  RadarLayout({required this.radiusKm});

  final double radiusKm;

  /// Fraction of the radar's radius kept clear around the user's core.
  static const double innerRadius = 0.22;

  /// Radius (as a fraction of the radar radius) of the outermost ring.
  static const double outerRingRadius = 0.92;

  static const List<double> _ringFractions = [0.1, 0.25, 0.5, 1.0];

  /// sqrt scale: nearby people spread out instead of piling up at the centre.
  double radiusForFraction(double fractionOfRange) =>
      innerRadius + (outerRingRadius - innerRadius) * math.sqrt(fractionOfRange.clamp(0.0, 1.0));

  double radiusForDistance(int meters) => radiusForFraction(meters / (radiusKm * 1000));

  late final List<double> ringRadii = [for (final f in _ringFractions) radiusForFraction(f)];

  late final List<String> ringLabels = [
    for (final f in _ringFractions) formatDistance(f * radiusKm * 1000),
  ];
}

/// Everything needed to place one person on the radar at any moment in time.
class RadarNodeSpec {
  factory RadarNodeSpec(NearbyUser user, RadarLayout layout) {
    final h = _fnv1a(user.id);
    final frac = (h & 0xFFFF) / 65535.0;
    final speedFrac = ((h >> 16) & 0xFF) / 255.0;
    return RadarNodeSpec._(
      user: user,
      baseAngle: user.bearingDeg * math.pi / 180 - math.pi / 2, // compass -> canvas angle
      baseRadius: layout.radiusForDistance(user.distanceM),
      phase: frac * 2 * math.pi,
      // Slow orbit (one lap every ~90-210 s), direction varies per person.
      orbitSpeed: (0.03 + 0.035 * speedFrac) * ((h & 1) == 0 ? 1 : -1),
    );
  }

  const RadarNodeSpec._({
    required this.user,
    required this.baseAngle,
    required this.baseRadius,
    required this.phase,
    required this.orbitSpeed,
  });

  final NearbyUser user;
  final double baseAngle;
  final double baseRadius;
  final double phase;
  final double orbitSpeed;

  /// Offset from the radar centre at time [t] (seconds).
  Offset positionAt(double t, double maxRadius) {
    final angle = baseAngle + orbitSpeed * t;
    final breathe = 1 + 0.018 * math.sin(t * 0.9 + phase);
    final r = baseRadius * breathe * maxRadius;
    return Offset(
      math.cos(angle) * r,
      math.sin(angle) * r + math.sin(t * 1.3 + phase) * 3, // gentle float
    );
  }

  static int _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }
}
