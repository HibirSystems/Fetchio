import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/backend_download_manager.dart';
import '../core/storage/device_media.dart';
import '../shared/models/download_item.dart';
import 'settings_provider.dart';

class DeviceDownloadState {
  const DeviceDownloadState({
    this.saving = false,
    this.progress,
    this.saved,
    this.error,
  });

  final bool saving;
  final double? progress;
  final SavedMedia? saved;
  final String? error;
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class DownloadNotifier extends StateNotifier<List<DownloadItem>> {
  DownloadNotifier(this._repo,
      {DeviceMedia? deviceMedia,
      void Function(String, DeviceDownloadState)? onDeviceState,
      void Function(AsyncValue<void>)? onSync})
      : _deviceMedia = deviceMedia,
        _onDeviceState = onDeviceState,
        _onSync = onSync,
        super([]) {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => loadAll());
  }

  final DeviceMedia? _deviceMedia;
  final void Function(String, DeviceDownloadState)? _onDeviceState;
  final void Function(AsyncValue<void>)? _onSync;

  final BackendDownloadManager _repo;
  Timer? _pollTimer;
  bool _refreshing = false;
  bool _pendingRestored = false;
  final Set<String> _pendingSources = {};
  final Set<String> _automaticAttempts = {};
  final Set<String> _automaticRunning = {};
  final Map<String, Future<SavedMedia?>> _deviceSaves = {};

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

    await _trackOnDevice(item.downloadId);
    await _refreshFromBackend();
    if (mounted) {
      final current = _itemFor(item.downloadId);
      if (current == null ||
          (item.status == DownloadStatus.completed &&
              current.status != DownloadStatus.completed)) {
        state = [
          ...state.where((entry) => entry.downloadId != item.downloadId),
          item,
        ];
      }
      _saveTrackedCompleted(state);
    }
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
    await _trackOnDevice(item.downloadId);
    await _refreshFromBackend();
    return item;
  }

  Uri fileUri(String id) => _repo.downloadFileUri(id);

  Future<SavedMedia?> saveToDevice(String id, {bool play = false}) {
    _automaticAttempts.remove(id);
    return _saveToDevice(id, play: play);
  }

  Future<SavedMedia?> retryDevice(String id) => saveToDevice(id);

  Future<void> play(String id) async {
    await saveToDevice(id, play: true);
  }

  Future<void> _trackOnDevice(String id) async {
    final media = _deviceMedia;
    if (media == null || !media.supportsLocalFiles) return;
    final source = fileUri(id);
    try {
      await media.track(source);
      _pendingSources.add(source.toString());
    } catch (error) {
      _publishDeviceState(id, DeviceDownloadState(error: error.toString()));
    }
  }

  Future<SavedMedia?> _saveToDevice(String id, {bool play = false}) {
    final media = _deviceMedia;
    final active = _deviceSaves[id];
    if (active != null) {
      return play && media != null ? _openAfterSave(active, media) : active;
    }
    final item = _itemFor(id);
    if (item == null ||
        item.status != DownloadStatus.completed ||
        media == null ||
        !media.supportsLocalFiles) {
      return Future.value(null);
    }

    late final Future<SavedMedia?> saving;
    saving = () async {
      try {
        final source = fileUri(id);
        if (!_pendingSources.contains(source.toString())) {
          await media.track(source);
          _pendingSources.add(source.toString());
        }
        final existing = await media.find(source);
        final saved = existing ??
            await media.save(item, source, onProgress: (progress) {
              _publishDeviceState(
                  id, DeviceDownloadState(saving: true, progress: progress));
            });
        _publishDeviceState(id, DeviceDownloadState(saved: saved));
        return saved;
      } catch (error) {
        _publishDeviceState(id, DeviceDownloadState(error: error.toString()));
        rethrow;
      } finally {
        _deviceSaves.remove(id);
      }
    }();
    _deviceSaves[id] = saving;
    _publishDeviceState(id, const DeviceDownloadState(saving: true));
    return play ? _openAfterSave(saving, media) : saving;
  }

  Future<SavedMedia?> _openAfterSave(
      Future<SavedMedia?> saving, DeviceMedia media) async {
    final saved = await saving;
    if (saved != null && mounted) await media.open(saved);
    return saved;
  }

  DownloadItem? _itemFor(String id) {
    for (final item in state) {
      if (item.downloadId == id) return item;
    }
    return null;
  }

  void _publishDeviceState(String id, DeviceDownloadState value) {
    if (mounted) _onDeviceState?.call(id, value);
  }

  Future<void> _restorePendingSources() async {
    final media = _deviceMedia;
    if (_pendingRestored || media == null || !media.supportsLocalFiles) return;
    final pending = await media.pendingDownloads();
    _pendingSources.addAll(pending.map((uri) => uri.toString()));
    _pendingRestored = true;
  }

  void _saveTrackedCompleted(List<DownloadItem> items) {
    final media = _deviceMedia;
    if (media == null || !media.supportsLocalFiles) return;
    for (final item in items) {
      final id = item.downloadId;
      if (item.status != DownloadStatus.completed ||
          !_pendingSources.contains(fileUri(id).toString()) ||
          !_automaticAttempts.add(id) ||
          !_automaticRunning.add(id)) {
        continue;
      }
      _saveToDevice(id)
          .then<void>((_) {}, onError: (Object _, StackTrace __) {})
          .whenComplete(() => _automaticRunning.remove(id));
    }
  }

  Future<void> _refreshFromBackend() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    _onSync?.call(const AsyncLoading());
    try {
      final items = await _repo.listDownloads();
      if (!mounted) return;
      try {
        await _restorePendingSources();
      } catch (_) {
        // Retry restoring the queue on the next refresh.
      }
      if (!mounted) return;
      state = items;
      _saveTrackedCompleted(items);
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

final deviceMediaProvider = Provider<DeviceMedia>((ref) => DeviceMedia());

final deviceDownloadProvider =
    StateProvider<Map<String, DeviceDownloadState>>((ref) => {});

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, List<DownloadItem>>((ref) {
  final baseUrl = ref.watch(settingsProvider.select((s) => s.apiBaseUrl));
  final repo = BackendDownloadManager(baseUrl);
  ref.onDispose(repo.dispose);
  return DownloadNotifier(repo,
      deviceMedia: ref.watch(deviceMediaProvider),
      onDeviceState: (id, value) {
        final states = ref.read(deviceDownloadProvider);
        ref.read(deviceDownloadProvider.notifier).state = {
          ...states,
          id: value
        };
      },
      onSync: (value) => ref.read(downloadSyncProvider.notifier).state = value);
});

final activeDownloadCountProvider = Provider<int>((ref) {
  final downloads = ref.watch(downloadProvider);
  final transfers = ref.watch(deviceDownloadProvider);
  final activeIds = downloads
      .where((item) => item.isActive)
      .map((item) => item.downloadId)
      .toSet();
  return activeIds.length +
      transfers.entries
          .where(
              (entry) => entry.value.saving && !activeIds.contains(entry.key))
          .length;
});
