import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'binary_manager.dart';

/// Encapsulates a yt-dlp download progress snapshot.
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

  final Map<String, Process> _activeProcesses = {};

  Future<Map<String, dynamic>> extractInfo(String url) async {
    await BinaryManager.instance.ensureReady();
    final ffmpegPath = BinaryManager.instance.ffmpegPath;
    final args = [
      '--dump-json',
      '--no-playlist',
      '--no-warnings',
      '--quiet',
      if (ffmpegPath != null) ...['--ffmpeg-location', ffmpegPath] else
        '--no-check-formats',
      url,
    ];

    final result = await Process.run(
      BinaryManager.instance.ytDlpPath,
      args,
    );

    if (result.exitCode != 0) {
      final err = result.stderr.toString().trim();
      throw Exception('yt-dlp failed: $err');
    }

    final raw = result.stdout.toString().trim();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> search(String query, int limit) async {
    await BinaryManager.instance.ensureReady();
    final result = await Process.run(
      BinaryManager.instance.ytDlpPath,
      [
        '--dump-json',
        '--flat-playlist',
        '--no-warnings',
        '--quiet',
        'ytsearch$limit:$query',
      ],
    );

    if (result.exitCode != 0) {
      final err = result.stderr.toString().trim();
      throw Exception('yt-dlp search failed: $err');
    }

    final lines =
        result.stdout.toString().split('\n').where((l) => l.trim().isNotEmpty);

    final entries = <Map<String, dynamic>>[];
    for (final line in lines) {
      try {
        final obj = jsonDecode(line);
        if (obj is Map<String, dynamic>) {
          entries.add(obj);
        }
      } catch (_) {}
    }
    return entries;
  }

  Stream<YtDlpProgress> download({
    required String downloadId,
    required String url,
    required String outputDir,
    required String formatSelector,
    String? audioFormat,
  }) {
    final controller = StreamController<YtDlpProgress>();

    _startDownload(
      downloadId: downloadId,
      url: url,
      outputDir: outputDir,
      formatSelector: formatSelector,
      audioFormat: audioFormat,
      controller: controller,
    );

    return controller.stream;
  }

  void cancelDownload(String downloadId) {
    _activeProcesses[downloadId]?.kill();
    _activeProcesses.remove(downloadId);
  }

  Future<void> _startDownload({
    required String downloadId,
    required String url,
    required String outputDir,
    required String formatSelector,
    String? audioFormat,
    required StreamController<YtDlpProgress> controller,
  }) async {
    await BinaryManager.instance.ensureReady();
    final outtmpl = '$outputDir/%(title)s [%(id)s].%(ext)s';
    final hasFfmpeg = BinaryManager.instance.ffmpegPath != null;

    final args = [
      '--format',
      formatSelector,
      '--output',
      outtmpl,
      '--progress',
      '--newline',
      '--no-warnings',
      '--progress-template',
      r'[PROGRESS]%(progress.downloaded_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s|%(progress.status)s',
      if (hasFfmpeg) ...[
        '--ffmpeg-location',
        BinaryManager.instance.ffmpegPath!,
        if (audioFormat != null) ...[
          '-x',
          '--audio-format',
          audioFormat,
        ] else ...[
          '--merge-output-format',
          'mp4',
        ],
      ],
      url,
    ];

    Process process;
    try {
      process = await Process.start(
        BinaryManager.instance.ytDlpPath,
        args,
        workingDirectory: outputDir,
      );
    } catch (e) {
      controller
        ..addError(Exception('Failed to start yt-dlp: $e'))
        ..close();
      return;
    }

    _activeProcesses[downloadId] = process;

    String? lastFilename;
    final stderrBuffer = StringBuffer();

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.startsWith('[PROGRESS]')) {
          final progress = _parseProgress(line.substring(10));
          if (progress != null) {
            if (progress.filename != null) lastFilename = progress.filename;
            controller.add(progress);
          }
        } else if (line.startsWith('[download] Destination:')) {
          lastFilename =
              line.replaceFirst('[download] Destination:', '').trim();
        } else if (line.contains('Merging formats into')) {
          final match = RegExp(r'Merging formats into "(.+)"').firstMatch(line);
          if (match != null) lastFilename = match.group(1);
        }
      },
      onError: (Object err) => stderrBuffer.writeln(err),
    );

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) => stderrBuffer.writeln(line),
          onError: (_) {},
        );

    final exitCode = await process.exitCode;
    _activeProcesses.remove(downloadId);

    if (exitCode == 0) {
      controller.add(
        YtDlpProgress(
          status: 'finished',
          downloadedBytes: 0,
          filename: lastFilename,
        ),
      );
    } else {
      final errMsg = stderrBuffer.toString().trim();
      controller.addError(Exception(
        exitCode == -15
            ? 'Download cancelled'
            : 'yt-dlp exited with code $exitCode: $errMsg',
      ));
    }

    await controller.close();
  }

  YtDlpProgress? _parseProgress(String raw) {
    final parts = raw.split('|');
    if (parts.length < 5) return null;

    int? parseInt(String s) {
      final cleaned = s.trim().replaceAll(RegExp(r'[^\d.]'), '');
      if (cleaned.isEmpty) return null;
      return double.tryParse(cleaned)?.toInt();
    }

    double? parseDouble(String s) {
      final cleaned = s.trim().replaceAll(RegExp(r'[^\d.]'), '');
      return double.tryParse(cleaned);
    }

    return YtDlpProgress(
      downloadedBytes: parseInt(parts[0]) ?? 0,
      totalBytes: parseInt(parts[1]),
      speed: parseDouble(parts[2]),
      eta: parseInt(parts[3]),
      status: parts[4].trim().isEmpty ? 'downloading' : parts[4].trim(),
    );
  }
}
