import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../errors/app_exceptions.dart';

typedef GeoPoint = ({double lat, double lng});

abstract interface class LocationService {
  Future<GeoPoint> currentPosition();
}

final class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<GeoPoint> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('Turn on location services to scan nearby.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException('Location permission is needed to find people near you.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Location permission is blocked. Enable it in app settings.',
        canOpenSettings: true,
      );
    }

    try {
      // Medium accuracy is plenty: the server fuzzes positions by 100-300 m anyway.
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return (lat: p.latitude, lng: p.longitude);
    } on TimeoutException {
      throw const LocationException('Could not get a location fix. Try again.');
    }
  }
}

/// Used by demo mode so the radar works on emulators and the web without GPS.
final class FixedLocationService implements LocationService {
  const FixedLocationService(this.point);
  final GeoPoint point;

  @override
  Future<GeoPoint> currentPosition() async => point;
}
