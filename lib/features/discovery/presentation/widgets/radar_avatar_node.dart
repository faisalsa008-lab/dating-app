import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/nearby_user.dart';
import 'user_avatar.dart';

/// A person on the radar. Scale is driven by an under-damped spring:
///  - spawn:       0 -> 1 with a bounce (staggered by [appearDelay])
///  - finger down: squashes to 0.88 and carries its velocity into the release
///  - tap / select: pops to 1.4 and settles; deselect springs back to 1.0
class RadarAvatarNode extends StatefulWidget {
  const RadarAvatarNode({
    super.key,
    required this.user,
    required this.selected,
    required this.dimmed,
    required this.appearDelay,
    required this.onTap,
  });

  static const double boxSize = 58;

  final NearbyUser user;
  final bool selected;
  final bool dimmed;
  final Duration appearDelay;
  final VoidCallback onTap;

  @override
  State<RadarAvatarNode> createState() => _RadarAvatarNodeState();
}

class _RadarAvatarNodeState extends State<RadarAvatarNode> with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(mass: 1, stiffness: 380, damping: 15);
  static const _pressedScale = 0.88;
  static const _selectedScale = 1.4;

  late final AnimationController _scale = AnimationController.unbounded(vsync: this, value: 0);
  Timer? _appearTimer;
  bool _pressed = false;

  double get _restScale => widget.selected ? _selectedScale : 1.0;

  @override
  void initState() {
    super.initState();
    _appearTimer = Timer(widget.appearDelay, () {
      if (mounted) _springTo(_pressed ? _pressedScale : _restScale);
    });
  }

  @override
  void didUpdateWidget(RadarAvatarNode old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected && !_pressed) _springTo(_restScale);
  }

  void _springTo(double target) {
    _scale.animateWith(SpringSimulation(_spring, _scale.value, target, _scale.velocity));
  }

  @override
  void dispose() {
    _appearTimer?.cancel();
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _pressed = true;
        _springTo(_pressedScale);
      },
      onTapUp: (_) {
        _pressed = false;
        HapticFeedback.lightImpact();
        widget.onTap(); // parent flips `selected`; didUpdateWidget springs to the new rest scale
        _springTo(!widget.selected ? _selectedScale : 1.0);
      },
      onTapCancel: () {
        _pressed = false;
        _springTo(_restScale);
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: widget.dimmed ? 0.35 : 1,
        child: Center(
          child: AnimatedBuilder(
            animation: _scale,
            builder: (context, child) => Transform.scale(
              scale: _scale.value.clamp(0.0, 2.0),
              child: child,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.violet.withValues(alpha: widget.selected ? 0.8 : 0.35),
                    blurRadius: widget.selected ? 26 : 12,
                    spreadRadius: widget.selected ? 2 : 0,
                  ),
                ],
              ),
              child: UserAvatar(user: widget.user, size: 46),
            ),
          ),
        ),
      ),
    );
  }
}
