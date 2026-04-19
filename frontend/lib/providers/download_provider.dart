import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/engine/local_download_manager.dart';
import '../shared/models/download_item.dart';

// ── Notifier ──────────────────────────────────────────────────────────────────

class DownloadNotifier extends StateNotifier<List<DownloadItem>> {
  DownloadNotifier() : super([]);

  final Map<String, StreamSubscription<DownloadItem>> _subscriptions = {};

  Future<DownloadItem> startDownload({
    required String url,
    String? formatId,
    bool audioOnly = false,
    String? convertTo,
    String preferredQuality = 'best',
  }) async {
    final item = await LocalDownloadManager.instance.startDownload(
      url: url,
      formatId: formatId,
      audioOnly: audioOnly,
      convertTo: convertTo,
      preferredQuality: preferredQuality,
    );

    state = [item, ...state];
    _subscribeToProgress(item.downloadId);
    return item;
  }

  /// Populates state from the manager's in-memory list (e.g. after navigation).
  void loadAll() {
    state = LocalDownloadManager.instance.downloads;
    for (final item in state.where((d) => d.isActive)) {
      _subscribeToProgress(item.downloadId);
    }
  }

  Future<void> cancel(String id) async {
    await LocalDownloadManager.instance.cancelDownload(id);
    _subscriptions[id]?.cancel();
    _subscriptions.remove(id);
    _reload();
  }

  Future<void> clearCompleted() async {
    await LocalDownloadManager.instance.clearCompleted();
    await Future.wait(
      _subscriptions.values.map((sub) async => sub.cancel()),
    );
    _subscriptions.clear();
    _reload();
  }

  void _subscribeToProgress(String id) {
    _subscriptions[id]?.cancel();
    _subscriptions[id] =
        LocalDownloadManager.instance.watchDownload(id).listen(
      (updated) => _updateItem(id, updated),
      onError: (_) => _subscriptions.remove(id),
      onDone: () => _subscriptions.remove(id),
    );
  }

  void _updateItem(String id, DownloadItem updated) {
    state = [
      for (final d in state)
        if (d.downloadId == id) updated else d,
    ];
  }

  void _reload() {
    state = List.of(LocalDownloadManager.instance.downloads);
  }

  @override
  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, List<DownloadItem>>((ref) {
  return DownloadNotifier();
});

final activeDownloadCountProvider = Provider<int>((ref) {
  return ref.watch(downloadProvider).where((d) => d.isActive).length;
});
