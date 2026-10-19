import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/discovery/presentation/screens/discovery_radar_screen.dart';

class PulseRideApp extends StatelessWidget {
  const PulseRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PulseRide',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const DiscoveryRadarScreen(),
    );
  }
}
