import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/constants/app_constants.dart';

// ── Settings model ────────────────────────────────────────────────────────────

class AppSettings {
  AppSettings({
    this.themeMode = 'dark',
    this.maxConcurrentDownloads = 3,
    this.defaultDownloadFormat = 'best_video',
    this.audioOnly = false,
    this.embedThumbnail = true,
    this.preferredQuality = '1080',
    String? apiBaseUrl,
  }) : apiBaseUrl = apiBaseUrl ?? _defaultApiBaseUrl();

  String themeMode;
  int maxConcurrentDownloads;
  String defaultDownloadFormat;
  bool audioOnly;
  bool embedThumbnail;
  String preferredQuality;
  String apiBaseUrl;

  AppSettings copyWith({
    String? themeMode,
    int? maxConcurrentDownloads,
    String? defaultDownloadFormat,
    bool? audioOnly,
    bool? embedThumbnail,
    String? preferredQuality,
    String? apiBaseUrl,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      defaultDownloadFormat:
          defaultDownloadFormat ?? this.defaultDownloadFormat,
      audioOnly: audioOnly ?? this.audioOnly,
      embedThumbnail: embedThumbnail ?? this.embedThumbnail,
      preferredQuality: preferredQuality ?? this.preferredQuality,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
    );
  }
}

String _defaultApiBaseUrl() {
  if (kIsWeb) {
    return 'http://localhost:8000/api/v1';
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'http://10.0.2.2:8000/api/v1';
    default:
      return 'http://localhost:8000/api/v1';
  }
}

// ── Search history ────────────────────────────────────────────────────────────

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super([]) {
    _load();
  }

  late Box<String> _box;

  Future<void> _load() async {
    _box = await Hive.openBox<String>(AppConstants.searchHistoryBox);
    state = _box.values
        .toList()
        .reversed
        .take(AppConstants.maxSearchHistoryItems)
        .toList();
  }

  Future<void> add(String query) async {
    if (query.trim().isEmpty) return;
    final trimmed = query.trim();
    final updated = [trimmed, ...state.where((q) => q != trimmed)]
        .take(AppConstants.maxSearchHistoryItems)
        .toList();
    state = updated;
    await _box.clear();
    for (final q in updated.reversed) {
      await _box.add(q);
    }
  }

  Future<void> remove(String query) async {
    state = state.where((q) => q != query).toList();
    await _box.clear();
    for (final q in state.reversed) {
      await _box.add(q);
    }
  }

  Future<void> clear() async {
    state = [];
    await _box.clear();
  }
}

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>((ref) {
  return SearchHistoryNotifier();
});

// ── Settings ──────────────────────────────────────────────────────────────────

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(AppSettings()) {
    _load();
  }

  late Box<dynamic> _box;

  Future<void> _load() async {
    _box = await Hive.openBox<dynamic>(AppConstants.settingsBox);
    state = AppSettings(
      themeMode: _box.get('themeMode', defaultValue: state.themeMode) as String,
      maxConcurrentDownloads: _box.get('maxConcurrentDownloads',
          defaultValue: state.maxConcurrentDownloads) as int,
      defaultDownloadFormat: _box.get('defaultDownloadFormat',
          defaultValue: state.defaultDownloadFormat) as String,
      audioOnly: _box.get('audioOnly', defaultValue: state.audioOnly) as bool,
      embedThumbnail: _box.get('embedThumbnail',
          defaultValue: state.embedThumbnail) as bool,
      preferredQuality: _box.get('preferredQuality',
          defaultValue: state.preferredQuality) as String,
      apiBaseUrl:
          _box.get('apiBaseUrl', defaultValue: state.apiBaseUrl) as String,
    );
  }

  Future<void> setThemeMode(String mode) async {
    state = state.copyWith(themeMode: mode);
    await _box.put('themeMode', mode);
  }

  Future<void> setAudioOnly(bool value) async {
    state = state.copyWith(audioOnly: value);
    await _box.put('audioOnly', value);
  }

  Future<void> setEmbedThumbnail(bool value) async {
    state = state.copyWith(embedThumbnail: value);
    await _box.put('embedThumbnail', value);
  }

  Future<void> setPreferredQuality(String quality) async {
    state = state.copyWith(preferredQuality: quality);
    await _box.put('preferredQuality', quality);
  }

  Future<void> setApiBaseUrl(String baseUrl) async {
    final normalized =
        baseUrl.trim().isEmpty ? _defaultApiBaseUrl() : baseUrl.trim();
    state = state.copyWith(apiBaseUrl: normalized);
    await _box.put('apiBaseUrl', normalized);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
