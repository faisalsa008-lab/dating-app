import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/entities/nearby_user.dart';

/// Frosted-glass segmented control: 'Dating / Hangout' | 'Biker Clubs'.
class DiscoveryFilterToggle extends StatelessWidget {
  const DiscoveryFilterToggle({super.key, required this.mode, required this.onChanged});

  final DiscoveryMode mode;
  final ValueChanged<DiscoveryMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 28,
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 44,
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              alignment: mode == DiscoveryMode.social ? Alignment.centerLeft : Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(colors: [AppColors.violet, AppColors.cyan]),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.violet.withValues(alpha: 0.45),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final m in DiscoveryMode.values)
                  Expanded(
                    child: _Segment(mode: m, selected: m == mode, onTap: () => onChanged(m)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.mode, required this.selected, required this.onTap});

  final DiscoveryMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppColors.textMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mode == DiscoveryMode.social ? Icons.favorite_rounded : Icons.two_wheeler_rounded,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: Text(mode.label),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
