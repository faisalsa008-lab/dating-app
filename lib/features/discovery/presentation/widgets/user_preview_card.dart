import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/entities/nearby_user.dart';
import 'user_avatar.dart';

/// Glass card shown when a node is selected. Action buttons only render when the
/// host screen supplies the matching callback.
class UserPreviewCard extends StatelessWidget {
  const UserPreviewCard({
    super.key,
    required this.user,
    required this.onClose,
    this.onOpenProfile,
    this.onStartChat,
  });

  final NearbyUser user;
  final VoidCallback onClose;
  final ValueChanged<NearbyUser>? onOpenProfile;
  final ValueChanged<NearbyUser>? onStartChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final title = user.age != null ? '${user.displayName}, ${user.age}' : user.displayName;
    final clubs = user.sharedClubs == 0
        ? ''
        : ' · ${user.sharedClubs} shared ${user.sharedClubs == 1 ? 'club' : 'clubs'}';

    return GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(user: user, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${user.approxDistanceLabel} away$clubs',
                      style: theme.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                tooltip: 'Close',
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (user.bio != null && user.bio!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(user.bio!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.bodyMedium),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final intent in user.intents)
                      _Tag(
                        label: '${intent[0].toUpperCase()}${intent.substring(1)}',
                        color: intent == 'riding' ? AppColors.cyan : AppColors.violet,
                      ),
                    if (user.bikeModel != null)
                      _Tag(label: user.bikeModel!, color: AppColors.cyan, icon: Icons.two_wheeler_rounded),
                  ],
                ),
                if (onOpenProfile != null || onStartChat != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (onOpenProfile != null)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => onOpenProfile!(user),
                            child: const Text('Profile'),
                          ),
                        ),
                      if (onOpenProfile != null && onStartChat != null) const SizedBox(width: 10),
                      if (onStartChat != null)
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: AppColors.violet),
                            onPressed: () => onStartChat!(user),
                            child: const Text('Say hi'),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      'Approximate location · privacy protected',
                      style: theme.labelSmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
