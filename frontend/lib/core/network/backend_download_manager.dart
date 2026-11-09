import 'package:http/http.dart' as http;

import '../../shared/models/download_item.dart';
import 'backend_api_client.dart';

class BackendDownloadManager {
  BackendDownloadManager(String baseUrl, {http.Client? client})
      : _client = BackendApiClient(baseUrl: baseUrl, client: client);

  final BackendApiClient _client;

  Future<DownloadItem> startDownload({
    required String url,
    String? formatId,
    required String formatSelector,
    bool audioOnly = false,
    String? convertTo,
    bool embedThumbnail = true,
  }) {
    return _client.startDownload(
      url: url,
      formatId: formatId,
      formatSelector: formatSelector,
      audioOnly: audioOnly,
      convertTo: convertTo,
      embedThumbnail: embedThumbnail,
    );
  }

  Future<List<DownloadItem>> listDownloads() async {
    final response = await _client.listDownloads();
    return response.downloads;
  }

  Future<DownloadItem?> getDownload(String downloadId) {
    return _client.getDownload(downloadId);
  }

  Future<bool> cancelDownload(String downloadId) {
    return _client.cancelDownload(downloadId);
  }

  Future<DownloadItem> retryDownload(String downloadId) =>
      _client.retryDownload(downloadId);

  Uri downloadFileUri(String downloadId) => _client.downloadFileUri(downloadId);

  Future<int> clearCompleted() {
    return _client.clearCompleted();
  }

  void dispose() => _client.dispose();
}
