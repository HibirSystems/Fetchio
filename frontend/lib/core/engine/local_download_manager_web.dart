import '../../shared/models/download_item.dart';

class LocalDownloadManager {
  LocalDownloadManager._();

  static final LocalDownloadManager instance = LocalDownloadManager._();

  final Map<String, DownloadItem> _downloads = {};

  List<DownloadItem> get downloads => List.unmodifiable(_downloads.values);

  Future<DownloadItem> startDownload({
    required String url,
    String? formatId,
    bool audioOnly = false,
    String? convertTo,
    String preferredQuality = 'best',
    bool embedThumbnail = false,
  }) async {
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    final item = DownloadItem(
      downloadId: id,
      status: DownloadStatus.failed,
      url: url,
      error: 'Local downloads are not supported on web.',
      createdAt: now,
      updatedAt: now,
    );
    _downloads[id] = item;
    return item;
  }

  Stream<DownloadItem> watchDownload(String id) {
    final item = _downloads[id];
    if (item == null) return const Stream.empty();
    return Stream<DownloadItem>.value(item);
  }

  Future<void> cancelDownload(String id) async {
    final current = _downloads[id];
    if (current == null) return;
    _downloads[id] = DownloadItem(
      downloadId: current.downloadId,
      status: DownloadStatus.cancelled,
      url: current.url,
      title: current.title,
      thumbnail: current.thumbnail,
      percent: current.percent,
      downloadedBytes: current.downloadedBytes,
      totalBytes: current.totalBytes,
      speed: current.speed,
      eta: current.eta,
      formatId: current.formatId,
      filename: current.filename,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
      completedAt: current.completedAt,
    );
  }

  Future<void> clearCompleted() async {
    _downloads.removeWhere((_, item) => item.isTerminal);
  }
}
