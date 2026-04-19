/// App-wide constants.
library;

class AppConstants {
  AppConstants._();

  // ── Hive boxes ─────────────────────────────────────────────────────────────
  static const String downloadsBox = 'downloads_box';
  static const String settingsBox = 'settings_box';
  static const String searchHistoryBox = 'search_history_box';

  // ── Misc ───────────────────────────────────────────────────────────────────
  static const int maxSearchHistoryItems = 30;
  static const Duration splashDuration = Duration(seconds: 2);
}
