import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/nearby_user.dart';

/// Circular avatar with a violet-to-cyan ring, an online dot and a rider badge.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.size = 46, this.showBadges = true});

  final NearbyUser user;
  final double size;
  final bool showBadges;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [AppColors.violet, AppColors.cyan, AppColors.violet]),
              ),
              child: Padding(
                padding: EdgeInsets.all(size * 0.055),
                child: ClipOval(child: _image()),
              ),
            ),
          ),
          if (showBadges && user.isOnline)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.26,
                height: size * 0.26,
                decoration: BoxDecoration(
                  color: AppColors.cyan,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 2),
                ),
              ),
            ),
          if (showBadges && user.isRider)
            Positioned(
              left: -3,
              top: -3,
              child: Container(
                padding: EdgeInsets.all(size * 0.08),
                decoration: BoxDecoration(
                  color: AppColors.violet,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 2),
                ),
                child: Icon(Icons.two_wheeler_rounded, size: size * 0.24, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _image() {
    final url = user.avatarUrl;
    if (url == null || url.isEmpty) return _initials();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, __) => _initials(),
      errorWidget: (_, __, ___) => _initials(),
    );
  }

  Widget _initials() => ColoredBox(
        color: AppColors.surface,
        child: Center(
          child: Text(
            user.initial,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.36,
            ),
          ),
        ),
      );
}
