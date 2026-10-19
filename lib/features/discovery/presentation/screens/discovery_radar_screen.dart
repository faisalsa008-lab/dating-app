import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/entities/nearby_user.dart';
import '../providers/discovery_providers.dart';
import '../radar/radar_geometry.dart';
import '../radar/radar_painter.dart';
import '../widgets/discovery_filter_toggle.dart';
import '../widgets/radar_avatar_node.dart';
import '../widgets/radius_selector.dart';
import '../widgets/user_preview_card.dart';

/// Proximity discovery radar.
///
/// A single [Ticker] feeds a ValueNotifier clock (seconds). The CustomPainter
/// and every avatar position listen to it directly, so the 60-120 FPS animation
/// never triggers a rebuild of this screen.
class DiscoveryRadarScreen extends ConsumerStatefulWidget {
  const DiscoveryRadarScreen({super.key, this.onOpenProfile, this.onStartChat});

  final ValueChanged<NearbyUser>? onOpenProfile;
  final ValueChanged<NearbyUser>? onStartChat;

  @override
  ConsumerState<DiscoveryRadarScreen> createState() => _DiscoveryRadarScreenState();
}

class _DiscoveryRadarScreenState extends ConsumerState<DiscoveryRadarScreen>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  late final Ticker _ticker;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _clock.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _select(String? id) => setState(() => _selectedId = id);

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(discoveryModeProvider);
    final radiusKm = ref.watch(discoveryRadiusProvider);
    final async = ref.watch(discoveryProvider);

    ref.listen<DiscoveryMode>(discoveryModeProvider, (_, __) => _select(null));

    // Only draw data that was fetched for the filters currently selected.
    final snapshot = async.valueOrNull;
    final users = (snapshot != null && snapshot.matches(mode, radiusKm))
        ? snapshot.users
        : const <NearbyUser>[];
    final layout = RadarLayout(radiusKm: radiusKm);
    final specs = [for (final u in users) RadarNodeSpec(u, layout)];
    final selected = users.where((u) => u.id == _selectedId).firstOrNull;
    final selectedId = selected?.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final center = Offset(size.width / 2, size.height * 0.47);
              final maxRadius = math.min(size.width * 0.5, size.height * 0.36) - 6;

              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _select(null),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: RadarPainter(
                            clock: _clock,
                            center: center,
                            maxRadius: maxRadius,
                            layout: layout,
                            specs: specs,
                            selectedId: selectedId,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _RingLabels(center: center, maxRadius: maxRadius, layout: layout),
                    ),
                  ),
                  for (final (i, spec) in specs.indexed)
                    _RadarNode(
                      key: ValueKey(spec.user.id),
                      spec: spec,
                      clock: _clock,
                      center: center,
                      maxRadius: maxRadius,
                      selected: spec.user.id == selectedId,
                      dimmed: selectedId != null && spec.user.id != selectedId,
                      appearDelay: Duration(milliseconds: 70 * math.min(i, 12)),
                      onTap: () => _select(spec.user.id == selectedId ? null : spec.user.id),
                    ),
                ],
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      const _Brand(),
                      const Spacer(),
                      GlassContainer(
                        borderRadius: 22,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: IconButton(
                            tooltip: 'Rescan',
                            onPressed: () => ref.read(discoveryProvider.notifier).refresh(),
                            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DiscoveryFilterToggle(
                    mode: mode,
                    onChanged: (m) {
                      HapticFeedback.selectionClick();
                      ref.read(discoveryModeProvider.notifier).select(m);
                    },
                  ),
                  const SizedBox(height: 10),
                  _StatusPill(
                    async: async,
                    count: users.length,
                    visibleEmpty: users.isEmpty,
                    mode: mode,
                    radiusKm: radiusKm,
                    onRetry: () => ref.read(discoveryProvider.notifier).refresh(),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero)
                              .animate(animation),
                          child: child,
                        ),
                      ),
                      child: selected == null
                          ? const SizedBox.shrink(key: ValueKey('no-selection'))
                          : UserPreviewCard(
                              key: ValueKey(selected.id),
                              user: selected,
                              onClose: () => _select(null),
                              onOpenProfile: widget.onOpenProfile,
                              onStartChat: widget.onStartChat,
                            ),
                    ),
                    const SizedBox(height: 12),
                    RadiusSelector(
                      radiusKm: radiusKm,
                      onChanged: (km) => ref.read(discoveryRadiusProvider.notifier).select(km),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Positions one avatar from the shared clock. Only the Positioned rebuilds per
/// frame; the avatar subtree (and its spring state) is passed in as `child`.
class _RadarNode extends StatelessWidget {
  const _RadarNode({
    super.key,
    required this.spec,
    required this.clock,
    required this.center,
    required this.maxRadius,
    required this.selected,
    required this.dimmed,
    required this.appearDelay,
    required this.onTap,
  });

  final RadarNodeSpec spec;
  final ValueListenable<double> clock;
  final Offset center;
  final double maxRadius;
  final bool selected;
  final bool dimmed;
  final Duration appearDelay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const half = RadarAvatarNode.boxSize / 2;
    return ValueListenableBuilder<double>(
      valueListenable: clock,
      child: RadarAvatarNode(
        user: spec.user,
        selected: selected,
        dimmed: dimmed,
        appearDelay: appearDelay,
        onTap: onTap,
      ),
      builder: (context, t, child) {
        final p = spec.positionAt(t, maxRadius);
        return Positioned(
          left: center.dx + p.dx - half,
          top: center.dy + p.dy - half,
          width: RadarAvatarNode.boxSize,
          height: RadarAvatarNode.boxSize,
          child: child!,
        );
      },
    );
  }
}

class _RingLabels extends StatelessWidget {
  const _RingLabels({required this.center, required this.maxRadius, required this.layout});

  final Offset center;
  final double maxRadius;
  final RadarLayout layout;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 10,
      letterSpacing: 0.4,
      color: AppColors.cyan.withValues(alpha: 0.6),
      fontWeight: FontWeight.w600,
    );
    final angle = -math.pi / 4;
    return Stack(
      children: [
        Positioned(
          left: center.dx - 4,
          top: center.dy - maxRadius * RadarLayout.outerRingRadius - 20,
          child: Text('N', style: style.copyWith(color: AppColors.cyan)),
        ),
        for (var i = 0; i < layout.ringRadii.length; i++)
          Positioned(
            left: center.dx + math.cos(angle) * maxRadius * layout.ringRadii[i] + 3,
            top: center.dy + math.sin(angle) * maxRadius * layout.ringRadii[i] - 13,
            child: Text(layout.ringLabels[i], style: style),
          ),
      ],
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) =>
          const LinearGradient(colors: [AppColors.violet, AppColors.cyan]).createShader(rect),
      child: const Text(
        'PulseRide',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.async,
    required this.count,
    required this.visibleEmpty,
    required this.mode,
    required this.radiusKm,
    required this.onRetry,
  });

  final AsyncValue<DiscoverySnapshot> async;
  final int count;
  final bool visibleEmpty;
  final DiscoveryMode mode;
  final double radiusKm;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (async.isLoading && visibleEmpty) {
      content = const _PillText(icon: Icons.radar_rounded, text: 'Scanning nearby…');
    } else if (async.hasError && visibleEmpty) {
      final error = async.error;
      final message = error is AppException ? error.message : 'Something went wrong. Please try again.';
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.danger),
          const SizedBox(width: 8),
          Flexible(child: Text(message, style: const TextStyle(fontSize: 12.5))),
          TextButton(
            onPressed: error is LocationException && error.canOpenSettings
                ? Geolocator.openAppSettings
                : onRetry,
            child: Text(error is LocationException && error.canOpenSettings ? 'Settings' : 'Retry'),
          ),
        ],
      );
    } else if (count == 0) {
      content = const _PillText(icon: Icons.explore_off_rounded, text: 'No one here yet. Try a wider radius.');
    } else {
      final noun = mode == DiscoveryMode.riders ? 'riders' : 'people';
      content = _PillText(
        icon: Icons.podcasts_rounded,
        text: '$count $noun within ${formatDistance(radiusKm * 1000)}',
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: GlassContainer(
        borderRadius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Center(child: content),
        ),
      ),
    );
  }
}

class _PillText extends StatelessWidget {
  const _PillText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.cyan),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
