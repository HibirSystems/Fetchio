import 'dart:async';

class YtDlpProgress {
  const YtDlpProgress({
    required this.status,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.speed,
    this.eta,
    this.filename,
  });

  final String status;
  final int downloadedBytes;
  final int? totalBytes;
  final double? speed;
  final int? eta;
  final String? filename;

  double get percent {
    if (totalBytes == null || totalBytes == 0) return 0;
    return (downloadedBytes / totalBytes!) * 100;
  }
}

class YtDlpRunner {
  YtDlpRunner._();

  static final YtDlpRunner instance = YtDlpRunner._();

  Future<Map<String, dynamic>> extractInfo(String url) {
    throw UnsupportedError('yt-dlp execution is not supported on web.');
  }

  Future<List<Map<String, dynamic>>> search(String query, int limit) {
    throw UnsupportedError('yt-dlp execution is not supported on web.');
  }

  Stream<YtDlpProgress> download({
    required String downloadId,
    required String url,
    required String outputDir,
    required String formatSelector,
    String? audioFormat,
  }) {
    return Stream<YtDlpProgress>.error(
      UnsupportedError('yt-dlp execution is not supported on web.'),
    );
  }

  void cancelDownload(String downloadId) {}
}
