import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../shared/models/download_item.dart';
import 'binary_manager.dart';
import 'ytdlp_runner.dart';

/// MethodChannel used to insert completed files into the public
/// Downloads / media collection via the Android MediaStore API.
const _kMediaStoreChannel = MethodChannel('com.hibir.fetchio/media_store');

/// Determines the MIME type from a file extension.
String _mimeType(String ext) {
  switch (ext.toLowerCase()) {
    case 'mp4':
    case 'mkv':
    case 'webm':
    case 'mov':
    case 'avi':
      return 'video/$ext';
    case 'm4a':
    case 'mp3':
    case 'ogg':
    case 'flac':
    case 'wav':
    case 'opus':
      return 'audio/$ext';
    default:
      return 'application/octet-stream';
  }
}

/// Manages the full lifecycle of local downloads.
///
/// Downloads run as isolated [Process] invocations via [YtDlpRunner].
/// Progress is broadcast through per-download [StreamController]s so that
/// UI listeners receive real-time updates without polling.
class LocalDownloadManager {
  LocalDownloadManager._();

  static final LocalDownloadManager instance = LocalDownloadManager._();

  final _uuid = const Uuid();

  // In-memory download state.
  final Map<String, DownloadItem> _downloads = {};

  // Per-download progress broadcast controllers.
  final Map<String, StreamController<DownloadItem>> _controllers = {};

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns all currently known download items (snapshot).
  List<DownloadItem> get downloads => List.unmodifiable(_downloads.values);

  /// Starts a new download and returns the initial [DownloadItem].
  ///
  /// Progress can be tracked via [watchDownload].
  Future<DownloadItem> startDownload({
    required String url,
    String? formatId,
    bool audioOnly = false,
    String? convertTo,
    String preferredQuality = 'best',
    bool embedThumbnail = false,
  }) async {
    await BinaryManager.instance.ensureReady();

    final id = _uuid.v4();
    final now = DateTime.now();

    final item = DownloadItem(
      downloadId: id,
      status: DownloadStatus.queued,
      url: url,
      createdAt: now,
      updatedAt: now,
    );

    _downloads[id] = item;
    _controllers[id] = StreamController<DownloadItem>.broadcast();

    // Start the download asynchronously.
    _runDownload(
      id: id,
      url: url,
      formatId: formatId,
      audioOnly: audioOnly,
      convertTo: convertTo,
      preferredQuality: preferredQuality,
    );

    return item;
  }

  /// Returns a broadcast stream that emits [DownloadItem] updates for [id].
  Stream<DownloadItem> watchDownload(String id) {
    return _controllers[id]?.stream ?? const Stream.empty();
  }

  /// Cancels an active download.
  Future<void> cancelDownload(String id) async {
    YtDlpRunner.instance.cancelDownload(id);
    _updateState(
      id,
      (d) => DownloadItem(
        downloadId: d.downloadId,
        status: DownloadStatus.cancelled,
        url: d.url,
        title: d.title,
        thumbnail: d.thumbnail,
        filename: d.filename,
        createdAt: d.createdAt,
        updatedAt: DateTime.now(),
      ),
    );
    await _controllers[id]?.close();
    _controllers.remove(id);
  }

  /// Removes all completed / failed / cancelled downloads from memory.
  void clearCompleted() {
    final toRemove = _downloads.values
        .where((d) => d.isTerminal)
        .map((d) => d.downloadId)
        .toList();
    for (final id in toRemove) {
      _downloads.remove(id);
      _controllers[id]?.close();
      _controllers.remove(id);
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<void> _runDownload({
    required String id,
    required String url,
    String? formatId,
    bool audioOnly = false,
    String? convertTo,
    String preferredQuality = 'best',
  }) async {
    // Temp directory for in-progress download files.
    final appDir = await getApplicationSupportDirectory();
    final tmpDir = Directory('${appDir.path}/ytdlp_tmp');
    await tmpDir.create(recursive: true);

    final format = formatId ??
        _buildFormatSelector(
          audioOnly: audioOnly,
          quality: preferredQuality,
          hasFfmpeg: BinaryManager.instance.ffmpegPath != null,
        );

    // Transition to downloading state.
    _updateState(
      id,
      (d) => DownloadItem(
        downloadId: d.downloadId,
        status: DownloadStatus.downloading,
        url: d.url,
        createdAt: d.createdAt,
        updatedAt: DateTime.now(),
      ),
    );

    String? tempFilePath;

    try {
      await for (final progress in YtDlpRunner.instance.download(
        downloadId: id,
        url: url,
        outputDir: tmpDir.path,
        formatSelector: format,
        audioFormat: convertTo,
      )) {
        if (progress.filename != null) tempFilePath = progress.filename;

        if (progress.status == 'finished') {
          // File complete — move to public Downloads.
          final publicPath = await _publishToDownloads(tempFilePath);
          _updateState(
            id,
            (d) => DownloadItem(
              downloadId: d.downloadId,
              status: DownloadStatus.completed,
              url: d.url,
              title: d.title,
              thumbnail: d.thumbnail,
              filename: publicPath ?? tempFilePath,
              percent: 100,
              createdAt: d.createdAt,
              updatedAt: DateTime.now(),
              completedAt: DateTime.now(),
            ),
          );
        } else {
          _updateState(
            id,
            (d) => DownloadItem(
              downloadId: d.downloadId,
              status: DownloadStatus.downloading,
              url: d.url,
              title: d.title,
              thumbnail: d.thumbnail,
              percent: progress.percent,
              downloadedBytes: progress.downloadedBytes,
              totalBytes: progress.totalBytes,
              speed: progress.speed,
              eta: progress.eta,
              createdAt: d.createdAt,
              updatedAt: DateTime.now(),
            ),
          );
        }
      }
    } catch (e) {
      final isCancelled = e.toString().contains('cancelled');
      _updateState(
        id,
        (d) => DownloadItem(
          downloadId: d.downloadId,
          status: isCancelled
              ? DownloadStatus.cancelled
              : DownloadStatus.failed,
          url: d.url,
          title: d.title,
          thumbnail: d.thumbnail,
          error: isCancelled ? null : e.toString(),
          createdAt: d.createdAt,
          updatedAt: DateTime.now(),
        ),
      );
    } finally {
      await _controllers[id]?.close();
      _controllers.remove(id);
    }
  }

  /// Uses the Android MediaStore MethodChannel to copy [filePath] into the
  /// public Downloads (or Video/Audio) directory so it is visible in the
  /// device's Downloads app and Gallery.
  ///
  /// Returns the public file path on success, or `null` if MediaStore is
  /// unavailable (e.g., on non-Android platforms or API < 29).
  Future<String?> _publishToDownloads(String? filePath) async {
    if (filePath == null) return null;
    final file = File(filePath);
    if (!file.existsSync()) return null;

    final name = file.uri.pathSegments.last;
    final ext = name.contains('.') ? name.split('.').last : '';
    final mime = _mimeType(ext);

    try {
      final result = await _kMediaStoreChannel.invokeMethod<String>(
        'saveToDownloads',
        {
          'sourcePath': filePath,
          'displayName': name,
          'mimeType': mime,
        },
      );
      // Clean up the temp file after a successful copy.
      try {
        await file.delete();
      } catch (_) {}
      return result;
    } on PlatformException {
      // MediaStore not available — return the local path as-is.
      return filePath;
    }
  }

  void _updateState(String id, DownloadItem Function(DownloadItem) updater) {
    final current = _downloads[id];
    if (current == null) return;
    final updated = updater(current);
    _downloads[id] = updated;
    _controllers[id]?.add(updated);
  }

  // ── Format selector builder ───────────────────────────────────────────────

  static String _buildFormatSelector({
    required bool audioOnly,
    required String quality,
    required bool hasFfmpeg,
  }) {
    if (audioOnly) {
      return 'bestaudio[ext=m4a]/bestaudio[ext=mp3]/bestaudio';
    }

    if (!hasFfmpeg) {
      // Without ffmpeg we must select a pre-muxed (combined video+audio) stream.
      if (quality == 'best') {
        return 'best[ext=mp4][vcodec!=none][acodec!=none]/best[vcodec!=none][acodec!=none]/best';
      }
      // Height-constrained pre-muxed stream.
      return 'best[height<=$quality][ext=mp4][vcodec!=none][acodec!=none]'
          '/best[height<=$quality][vcodec!=none][acodec!=none]'
          '/best[height<=$quality]'
          '/best';
    }

    // With ffmpeg, prefer separate best-quality streams and merge them.
    switch (quality) {
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
}
