import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/backend_download_manager.dart';
import '../shared/models/download_item.dart';
import 'settings_provider.dart';

// ── Notifier ──────────────────────────────────────────────────────────────────

class DownloadNotifier extends StateNotifier<List<DownloadItem>> {
  DownloadNotifier(this._repo, {void Function(AsyncValue<void>)? onSync})
      : _onSync = onSync,
        super([]) {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => loadAll());
  }

  final void Function(AsyncValue<void>)? _onSync;

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

  Future<DownloadItem> retry(String id) async {
    final item = await _repo.retryDownload(id);
    await _refreshFromBackend();
    return item;
  }

  Uri fileUri(String id) => _repo.downloadFileUri(id);

  Future<void> _refreshFromBackend() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    _onSync?.call(const AsyncLoading());
    try {
      final items = await _repo.listDownloads();
      if (!mounted) return;
      state = items;
      _onSync?.call(const AsyncData(null));
    } catch (error, stack) {
      if (mounted) _onSync?.call(AsyncError(error, stack));
    } finally {
      _refreshing = false;
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

final downloadSyncProvider =
    StateProvider<AsyncValue<void>>((ref) => const AsyncData(null));

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, List<DownloadItem>>((ref) {
  final baseUrl = ref.watch(settingsProvider.select((s) => s.apiBaseUrl));
  final repo = BackendDownloadManager(baseUrl);
  ref.onDispose(repo.dispose);
  return DownloadNotifier(repo,
      onSync: (value) => ref.read(downloadSyncProvider.notifier).state = value);
});

final activeDownloadCountProvider = Provider<int>((ref) {
  return ref.watch(downloadProvider).where((d) => d.isActive).length;
});
