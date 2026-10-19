import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'radar_geometry.dart';

/// Paints, back to front: ambient glow, range rings + compass ticks, pulsing ripples,
/// rotating sonar sweep, "ping" glows where the sweep just passed a person,
/// the selection link line and the pulsing core (you).
///
/// Repaints are driven by [clock] (seconds, from a Ticker) so the widget tree
/// never rebuilds per frame.
class RadarPainter extends CustomPainter {
  RadarPainter({
    required this.clock,
    required this.center,
    required this.maxRadius,
    required this.layout,
    required this.specs,
    required this.selectedId,
  })  : _outer = maxRadius * RadarLayout.outerRingRadius,
        super(repaint: clock);

  final ValueListenable<double> clock;
  final Offset center;
  final double maxRadius;
  final RadarLayout layout;
  final List<RadarNodeSpec> specs;
  final String? selectedId;
  final double _outer;

  static const double _sweepSeconds = 4.5;
  static const double _rippleSeconds = 3.6;
  static const double _coreRadius = 9;
  static const double _twoPi = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final sweepAngle = (t / _sweepSeconds * _twoPi) % _twoPi;

    _paintAmbientGlow(canvas);
    _paintRings(canvas);
    _paintRipples(canvas, t);
    _paintSweep(canvas, sweepAngle);
    _paintBlips(canvas, t, sweepAngle);
    _paintSelectionLink(canvas, t);
    _paintCore(canvas, t);
  }

  void _paintAmbientGlow(Canvas canvas) {
    final radius = _outer * 1.3;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.violet.withValues(alpha: 0.22),
            AppColors.cyan.withValues(alpha: 0.06),
            AppColors.cyan.withValues(alpha: 0),
          ],
          stops: const [0, 0.62, 1],
        ).createShader(rect),
    );
  }

  void _paintRings(Canvas canvas) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final radii = layout.ringRadii;
    for (var i = 0; i < radii.length; i++) {
      final isOuter = i == radii.length - 1;
      ring.color = AppColors.cyan.withValues(alpha: isOuter ? 0.38 : 0.16);
      canvas.drawCircle(center, maxRadius * radii[i], ring);
    }

    final cross = Paint()
      ..color = AppColors.cyan.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    canvas.drawLine(center.translate(-_outer, 0), center.translate(_outer, 0), cross);
    canvas.drawLine(center.translate(0, -_outer), center.translate(0, _outer), cross);

    // Compass ticks on the outer ring every 15 degrees.
    final tick = Paint()
      ..color = AppColors.cyan.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var deg = 0; deg < 360; deg += 15) {
      final a = deg * math.pi / 180;
      final dir = Offset(math.cos(a), math.sin(a));
      final len = deg % 90 == 0 ? 10.0 : 5.0;
      canvas.drawLine(center + dir * (_outer - len), center + dir * _outer, tick);
    }
  }

  void _paintRipples(Canvas canvas, double t) {
    for (var k = 0; k < 3; k++) {
      final phase = ((t / _rippleSeconds) + k / 3) % 1.0;
      final eased = Curves.easeOutCubic.transform(phase);
      final radius = lerpDouble(_coreRadius + 6, _outer, eased)!;
      final fade = math.pow(1 - phase, 1.6).toDouble();
      final color = Color.lerp(AppColors.violet, AppColors.cyan, phase)!;

      canvas.drawCircle(
        center,
        radius,
        Paint()..color = color.withValues(alpha: 0.10 * fade),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lerpDouble(2.6, 0.6, phase)!
          ..color = color.withValues(alpha: 0.55 * fade),
      );
    }
  }

  void _paintSweep(Canvas canvas, double sweepAngle) {
    const trail = math.pi * 0.75; // 135 degrees of afterglow
    final rect = Rect.fromCircle(center: center, radius: _outer);
    final edge = trail / _twoPi;

    // Hard-edged wedge: fades in behind the leading edge, cuts off at it.
    canvas.drawCircle(
      center,
      _outer,
      Paint()
        ..shader = SweepGradient(
          colors: [
            AppColors.cyan.withValues(alpha: 0),
            AppColors.cyan.withValues(alpha: 0.42),
            AppColors.cyan.withValues(alpha: 0),
            AppColors.cyan.withValues(alpha: 0),
          ],
          stops: [0, edge, edge, 1],
          transform: GradientRotation(sweepAngle - trail),
        ).createShader(rect),
    );

    final tip = center + Offset(math.cos(sweepAngle), math.sin(sweepAngle)) * _outer;
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..strokeWidth = 1.6
        ..shader = LinearGradient(
          colors: [
            AppColors.cyan.withValues(alpha: 0.1),
            AppColors.cyan.withValues(alpha: 0.95),
          ],
        ).createShader(Rect.fromPoints(center, tip)),
    );
  }

  /// Glow + expanding ring on a person right after the sweep passes over them.
  void _paintBlips(Canvas canvas, double t, double sweepAngle) {
    const window = math.pi * 0.9;
    for (final spec in specs) {
      final pos = center + spec.positionAt(t, maxRadius);
      final nodeAngle = math.atan2(pos.dy - center.dy, pos.dx - center.dx);
      final since = (sweepAngle - nodeAngle) % _twoPi;
      if (since > window) continue;

      final glow = math.pow(1 - since / window, 2).toDouble();
      canvas.drawCircle(
        pos,
        36,
        Paint()
          ..shader = RadialGradient(
            colors: [
              AppColors.cyan.withValues(alpha: 0.55 * glow),
              AppColors.cyan.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: pos, radius: 36)),
      );
      canvas.drawCircle(
        pos,
        lerpDouble(40, 24, glow)!,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppColors.cyan.withValues(alpha: 0.5 * glow),
      );
    }
  }

  /// Animated dashed link from you to the selected person.
  void _paintSelectionLink(Canvas canvas, double t) {
    if (selectedId == null) return;
    final spec = specs.where((s) => s.user.id == selectedId).firstOrNull;
    if (spec == null) return;

    final target = center + spec.positionAt(t, maxRadius);
    final delta = target - center;
    final length = delta.distance;
    if (length < _coreRadius + 30) return;
    final dir = delta / length;

    final paint = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(colors: [AppColors.violet, AppColors.cyan])
          .createShader(Rect.fromPoints(center, target));

    const dash = 6.0, gap = 6.0;
    var d = (t * 28) % (dash + gap) - (dash + gap); // marching dashes
    final start = _coreRadius + 4, end = length - 30;
    for (; d < end; d += dash + gap) {
      final a = math.max(d, start), b = math.min(d + dash, end);
      if (b > a) canvas.drawLine(center + dir * a, center + dir * b, paint);
    }
  }

  void _paintCore(Canvas canvas, double t) {
    final pulse = 0.5 + 0.5 * math.sin(t * _twoPi / 1.6);
    final glowRadius = 34 + 8 * pulse;
    canvas.drawCircle(
      center,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.violet.withValues(alpha: 0.65),
            AppColors.violet.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: glowRadius)),
    );
    canvas.drawCircle(
      center,
      _coreRadius + 2 * pulse,
      Paint()
        ..shader = const RadialGradient(colors: [Colors.white, AppColors.violet])
            .createShader(Rect.fromCircle(center: center, radius: _coreRadius + 2)),
    );
    canvas.drawCircle(
      center,
      _coreRadius + 5 + 2 * pulse,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.cyan.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(RadarPainter old) =>
      old.center != center ||
      old.maxRadius != maxRadius ||
      old.layout.radiusKm != layout.radiusKm ||
      old.selectedId != selectedId ||
      !listEquals(old.specs.map((s) => s.user.id).toList(), specs.map((s) => s.user.id).toList());
}
