import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/constants/app_constants.dart';

const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

String? validateApiBaseUrl(String value) {
  final trimmed = value.trim();
  if (RegExp(r'\s').hasMatch(trimmed)) {
    return 'URL must not contain whitespace.';
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.isAbsolute || uri.host.isEmpty) {
    return 'Enter a valid URL with a hostname.';
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return 'URL must use http or https.';
  }
  if (uri.userInfo.isNotEmpty) {
    return 'URL must not contain credentials.';
  }
  if (uri.hasQuery || uri.hasFragment) {
    return 'URL must not contain a query or fragment.';
  }
  return null;
}

String defaultApiBaseUrl({
  bool? isWeb,
  TargetPlatform? platform,
  Uri? webBaseUri,
  String? override,
}) {
  final configured = (override ?? _apiBaseUrlOverride).trim();
  if (configured.isNotEmpty && validateApiBaseUrl(configured) == null) {
    return configured;
  }

  if (isWeb ?? kIsWeb) {
    return (webBaseUri ?? Uri.base).resolve('/api/v1').toString();
  }
  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'http://10.0.2.2:8000/api/v1';
    default:
      return 'http://localhost:8000/api/v1';
  }
}

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
  }) : apiBaseUrl = apiBaseUrl ?? defaultApiBaseUrl();

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

// ── Search history ────────────────────────────────────────────────────────────

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super([]) {
    _ready = _load();
  }

  late final Future<void> _ready;
  late final Box<String> _box;
  Future<void> _writes = Future<void>.value();

  Future<void> _load() async {
    _box = await Hive.openBox<String>(AppConstants.searchHistoryBox);
    if (mounted) {
      state = _box.values
          .toList()
          .reversed
          .take(AppConstants.maxSearchHistoryItems)
          .toList();
    }
  }

  Future<void> add(String query) async {
    if (query.trim().isEmpty) return;
    await _ready;
    if (!mounted) return;
    final trimmed = query.trim();
    final updated = [trimmed, ...state.where((q) => q != trimmed)]
        .take(AppConstants.maxSearchHistoryItems)
        .toList();
    state = updated;
    await _persist(updated);
  }

  Future<void> remove(String query) async {
    await _ready;
    if (!mounted) return;
    state = state.where((q) => q != query).toList();
    await _persist(state);
  }

  Future<void> clear() async {
    await _ready;
    if (!mounted) return;
    state = [];
    await _persist(const []);
  }

  Future<void> _persist(List<String> values) async {
    final snapshot = List<String>.of(values);
    final write = _writes.then((_) async {
      await _box.clear();
      for (final query in snapshot.reversed) {
        await _box.add(query);
      }
    });
    _writes = write.catchError((Object _) {});
    await write;
  }
}

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>((ref) {
  return SearchHistoryNotifier();
});

// ── Settings ──────────────────────────────────────────────────────────────────

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(AppSettings()) {
    _ready = _load();
  }

  late final Future<void> _ready;
  late final Box<dynamic> _box;
  Future<void> _writes = Future<void>.value();

  Future<void> _load() async {
    _box = await Hive.openBox<dynamic>(AppConstants.settingsBox);
    if (!mounted) return;
    final storedApiBaseUrl =
        _box.get('apiBaseUrl', defaultValue: state.apiBaseUrl) as String;
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
      apiBaseUrl: validateApiBaseUrl(storedApiBaseUrl) == null
          ? storedApiBaseUrl
          : defaultApiBaseUrl(),
    );
  }

  Future<void> setThemeMode(String mode) async {
    await _ready;
    if (!mounted) return;
    state = state.copyWith(themeMode: mode);
    await _persist('themeMode', mode);
  }

  Future<void> setAudioOnly(bool value) async {
    await _ready;
    if (!mounted) return;
    state = state.copyWith(audioOnly: value);
    await _persist('audioOnly', value);
  }

  Future<void> setEmbedThumbnail(bool value) async {
    await _ready;
    if (!mounted) return;
    state = state.copyWith(embedThumbnail: value);
    await _persist('embedThumbnail', value);
  }

  Future<void> setPreferredQuality(String quality) async {
    await _ready;
    if (!mounted) return;
    state = state.copyWith(preferredQuality: quality);
    await _persist('preferredQuality', quality);
  }

  Future<void> setApiBaseUrl(String baseUrl) async {
    final normalized = baseUrl.trim();
    final validationError = validateApiBaseUrl(normalized);
    if (validationError != null) {
      throw ArgumentError.value(baseUrl, 'baseUrl', validationError);
    }
    await _ready;
    if (!mounted) return;
    state = state.copyWith(apiBaseUrl: normalized);
    await _persist('apiBaseUrl', normalized);
  }

  Future<void> _persist(String key, Object value) async {
    final write = _writes.then((_) => _box.put(key, value));
    _writes = write.catchError((Object _) {});
    await write;
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
