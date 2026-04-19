import '../../shared/models/download_item.dart';
import 'backend_api_client.dart';

class BackendDownloadManager {
  BackendDownloadManager(String baseUrl)
      : _client = BackendApiClient(baseUrl: baseUrl);

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

  Future<int> clearCompleted() {
    return _client.clearCompleted();
  }

  void dispose() => _client.dispose();
}
