import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';

class RadiusSelector extends StatelessWidget {
  const RadiusSelector({super.key, required this.radiusKm, required this.onChanged});

  static const options = [1.0, 5.0, 10.0, 25.0, 50.0];

  final double radiusKm;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: GlassContainer(
        borderRadius: 22,
        padding: const EdgeInsets.all(5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final km in options)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(km);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    color: km == radiusKm ? AppColors.violet : Colors.transparent,
                  ),
                  child: Text(
                    '${km.toInt()} km',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: km == radiusKm ? FontWeight.w700 : FontWeight.w500,
                      color: km == radiusKm ? Colors.white : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
