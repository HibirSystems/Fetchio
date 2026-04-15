import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/network/dio_client.dart';
import '../core/constants/app_constants.dart';
import '../shared/models/download_item.dart';

// ── Repository ────────────────────────────────────────────────────────────────

class DownloadRepository {
  const DownloadRepository(this._dio);
  final Dio _dio;

  Future<DownloadItem> startDownload({
    required String url,
    String? formatId,
    bool audioOnly = false,
    String? convertTo,
  }) async {
    final body = <String, dynamic>{
      'url': url,
      if (formatId != null) 'format_id': formatId,
      'audio_only': audioOnly,
      if (convertTo != null) 'convert_to': convertTo,
    };
    final response = await _dio.post<Map<String, dynamic>>(
      '/downloads',
      data: body,
    );
    return DownloadItem.fromJson(response.data!);
  }

  Future<DownloadListResponse> listDownloads() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/downloads');
    return DownloadListResponse.fromJson(response.data!);
  }

  Future<DownloadItem> getDownload(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/downloads/$id');
    return DownloadItem.fromJson(response.data!);
  }

  Future<void> cancelDownload(String id) async {
    await _dio.delete<void>('/downloads/$id');
  }

  Future<int> clearCompleted() async {
    final response =
        await _dio.delete<Map<String, dynamic>>('/downloads');
    return (response.data?['cleared'] as int?) ?? 0;
  }

  Stream<DownloadItem> streamProgress(String id) {
    final wsUrl = AppConstants.baseUrl
        .replaceFirst('http', 'ws')
        .replaceFirst('https', 'wss');
    final channel =
        WebSocketChannel.connect(Uri.parse('$wsUrl/downloads/$id/ws'));

    return channel.stream.map((event) {
      final json = jsonDecode(event as String) as Map<String, dynamic>;
      return DownloadItem.fromJson(json);
    });
  }
}

final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  return DownloadRepository(ref.watch(dioProvider));
});

// ── State ─────────────────────────────────────────────────────────────────────

class DownloadNotifier extends StateNotifier<List<DownloadItem>> {
  DownloadNotifier(this._repo) : super([]);

  final DownloadRepository _repo;
  final Map<String, StreamSubscription<DownloadItem>> _subscriptions = {};

  Future<DownloadItem> startDownload({
    required String url,
    String? formatId,
    bool audioOnly = false,
    String? convertTo,
  }) async {
    final item = await _repo.startDownload(
      url: url,
      formatId: formatId,
      audioOnly: audioOnly,
      convertTo: convertTo,
    );
    state = [item, ...state];
    _subscribeToProgress(item.downloadId);
    return item;
  }

  Future<void> loadAll() async {
    final response = await _repo.listDownloads();
    state = response.downloads;
    for (final item in response.downloads.where((d) => d.isActive)) {
      _subscribeToProgress(item.downloadId);
    }
  }

  Future<void> cancel(String id) async {
    await _repo.cancelDownload(id);
    _subscriptions[id]?.cancel();
    _subscriptions.remove(id);
    _updateItem(id, (d) => DownloadItem(
          downloadId: d.downloadId,
          status: DownloadStatus.cancelled,
          url: d.url,
          title: d.title,
          thumbnail: d.thumbnail,
          filename: d.filename,
        ));
  }

  Future<void> clearCompleted() async {
    await _repo.clearCompleted();
    state = state
        .where((d) =>
            d.status == DownloadStatus.downloading ||
            d.status == DownloadStatus.queued ||
            d.status == DownloadStatus.processing)
        .toList();
  }

  void _subscribeToProgress(String id) {
    _subscriptions[id]?.cancel();
    _subscriptions[id] = _repo.streamProgress(id).listen(
      (updated) {
        _updateItem(id, (_) => updated);
        if (updated.isTerminal) {
          _subscriptions[id]?.cancel();
          _subscriptions.remove(id);
        }
      },
      onError: (_) {
        _subscriptions.remove(id);
      },
    );
  }

  void _updateItem(String id, DownloadItem Function(DownloadItem) updater) {
    state = [
      for (final d in state)
        if (d.downloadId == id) updater(d) else d,
    ];
  }

  @override
  void dispose() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    super.dispose();
  }
}

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, List<DownloadItem>>((ref) {
  return DownloadNotifier(ref.watch(downloadRepositoryProvider));
});

final activeDownloadCountProvider = Provider<int>((ref) {
  return ref.watch(downloadProvider).where((d) => d.isActive).length;
});
