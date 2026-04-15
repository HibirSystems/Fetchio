/// App-wide constants.
library;

class AppConstants {
  AppConstants._();

  // ── API ────────────────────────────────────────────────────────────────────
  static const String baseUrl = 'http://10.0.2.2:8000/api/v1'; // Android emulator
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 60);

  // ── Hive boxes ─────────────────────────────────────────────────────────────
  static const String downloadsBox = 'downloads_box';
  static const String settingsBox = 'settings_box';
  static const String searchHistoryBox = 'search_history_box';

  // ── Misc ───────────────────────────────────────────────────────────────────
  static const int maxSearchHistoryItems = 30;
  static const Duration splashDuration = Duration(seconds: 2);
  static const int wsReconnectDelayMs = 2000;
}
