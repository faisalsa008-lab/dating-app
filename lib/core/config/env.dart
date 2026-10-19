/// Compile-time configuration:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// Preview the UI without a backend:
///   flutter run --dart-define=PULSERIDE_DEMO=true
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const demoMode = bool.fromEnvironment('PULSERIDE_DEMO');

  static void assertConfigured() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Missing SUPABASE_URL / SUPABASE_ANON_KEY. Pass them with --dart-define, '
        'or run with --dart-define=PULSERIDE_DEMO=true.',
      );
    }
  }
}
