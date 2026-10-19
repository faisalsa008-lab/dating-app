sealed class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

final class LocationException extends AppException {
  const LocationException(super.message, {this.canOpenSettings = false});
  final bool canOpenSettings;
}

final class DiscoveryException extends AppException {
  const DiscoveryException(super.message, {this.code});
  final String? code;
}
