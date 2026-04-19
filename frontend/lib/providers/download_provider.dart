import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/backend_download_manager.dart';
import '../shared/models/download_item.dart';
import 'settings_provider.dart';

// ── Notifier ──────────────────────────────────────────────────────────────────

class DownloadNotifier extends StateNotifier<List<DownloadItem>> {
  DownloadNotifier(this._repo) : super([]);

  final BackendDownloadManager _repo;
  Timer? _pollTimer;
  bool _refreshing = false;

  Future<DownloadItem> startDownload({
    required String url,
    String? formatId,
    bool audioOnly = false,
    String? convertTo,
    String preferredQuality = 'best',
    bool embedThumbnail = true,
  }) async {
    final item = await _repo.startDownload(
      url: url,
      formatId: formatId,
      formatSelector: _buildFormatSelector(
        audioOnly: audioOnly,
        preferredQuality: preferredQuality,
      ),
      audioOnly: audioOnly,
      convertTo: convertTo,
      embedThumbnail: embedThumbnail,
    );

    await _refreshFromBackend();
    return item;
  }

  /// Populates state from the backend's list (e.g. after navigation).
  Future<void> loadAll() async {
    await _refreshFromBackend();
  }

  Future<void> cancel(String id) async {
    await _repo.cancelDownload(id);
    await _refreshFromBackend();
  }

  Future<void> clearCompleted() async {
    await _repo.clearCompleted();
    await _refreshFromBackend();
  }

  Future<void> _refreshFromBackend() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      state = await _repo.listDownloads();
    } catch (_) {
      // Keep the last known state when the backend is temporarily unavailable.
    } finally {
      _refreshing = false;
      _syncPolling();
    }
  }

  void _syncPolling() {
    final hasActive = state.any((item) => item.isActive);
    if (hasActive && _pollTimer == null) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _refreshFromBackend(),
      );
    } else if (!hasActive && _pollTimer != null) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  String _buildFormatSelector({
    required bool audioOnly,
    required String preferredQuality,
  }) {
    if (audioOnly) {
      return 'bestaudio[ext=m4a]/bestaudio[ext=mp3]/bestaudio';
    }
    switch (preferredQuality) {
      case '1080':
        return 'bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=1080]+bestaudio/best[height<=1080]/best';
      case '720':
        return 'bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=720]+bestaudio/best[height<=720]/best';
      case '480':
        return 'bestvideo[height<=480][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=480]+bestaudio/best[height<=480]/best';
      case '360':
        return 'bestvideo[height<=360][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=360]+bestaudio/best[height<=360]/best';
      default:
        return 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best';
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, List<DownloadItem>>((ref) {
  final baseUrl = ref.watch(settingsProvider.select((s) => s.apiBaseUrl));
  final repo = BackendDownloadManager(baseUrl);
  ref.onDispose(repo.dispose);
  return DownloadNotifier(repo);
});

final activeDownloadCountProvider = Provider<int>((ref) {
  return ref.watch(downloadProvider).where((d) => d.isActive).length;
});
