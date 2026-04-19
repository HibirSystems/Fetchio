import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Manages lifecycle of yt-dlp binaries downloaded after app installation.
class BinaryManager {
  BinaryManager._();

  static final BinaryManager instance = BinaryManager._();

  static const String _engineMissingMessage =
      'yt-dlp engine is not installed. Open Settings > Engine and tap "Download Engine".';
  static const String _engineNotExecutableMessage =
      'yt-dlp was downloaded but cannot be executed on this device. '
      'This Android build may block executable files in app storage.';

  String? _ytDlpPath;
  String? _ffmpegPath;
  bool _ready = false;

  /// Path to the extracted yt-dlp binary, available after [ensureReady].
  String get ytDlpPath {
    assert(_ready, 'BinaryManager.ensureReady() must be called first');
    return _ytDlpPath!;
  }

  /// Path to the extracted ffmpeg binary, available after [ensureReady].
  /// May be `null` if the ffmpeg asset is not bundled for this ABI.
  String? get ffmpegPath => _ffmpegPath;

  bool get isReady => _ready;

  /// Resolves bundled binaries and caches their absolute paths.
  ///
  /// Safe to call multiple times; subsequent calls are no-ops.
  Future<void> ensureReady() async {
    if (_ready) return;
    final isInstalled = await refreshStatus();
    if (!isInstalled) {
      throw StateError(_engineMissingMessage);
    }
  }

  /// Installs or updates yt-dlp for the current ABI.
  Future<void> installOrUpdateYtDlp() async {
    final abi = _currentAbi();
    if (abi == null) {
      throw UnsupportedError(
        'Unsupported CPU architecture: ${Abi.current()}. '
        'Only arm64-v8a, armeabi-v7a, and x86_64 Android ABIs are supported.',
      );
    }

    final url = _ytDlpDownloadUrl(abi);
    final tempDir = await getTemporaryDirectory();
    final downloadedFile = File('${tempDir.path}/yt-dlp_download_$abi.bin');

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Failed to download yt-dlp (HTTP ${response.statusCode})',
          uri: Uri.parse(url),
        );
      }

      final sink = downloadedFile.openWrite();
      await response.pipe(sink);
      await sink.flush();
      await sink.close();

      for (final target in await _candidateBinaryFiles(abi)) {
        await target.parent.create(recursive: true);
        await downloadedFile.copy(target.path);

        if (await _ensureExecutable(target) && await _isRunnable(target)) {
          _ytDlpPath = target.path;
          _ffmpegPath = null;
          _ready = true;
          return;
        }
      }

      throw StateError(_engineNotExecutableMessage);
    } finally {
      client.close(force: true);
      if (await downloadedFile.exists()) {
        try {
          await downloadedFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Deletes installed yt-dlp binary.
  Future<void> removeYtDlp() async {
    final abi = _currentAbi();
    if (abi == null) {
      _ready = false;
      _ytDlpPath = null;
      _ffmpegPath = null;
      return;
    }
    for (final file in await _candidateBinaryFiles(abi)) {
      if (await file.exists()) {
        await file.delete();
      }
    }
    _ready = false;
    _ytDlpPath = null;
    _ffmpegPath = null;
  }

  /// Re-evaluates whether yt-dlp is installed and executable.
  Future<bool> refreshStatus() async {
    final abi = _currentAbi();
    if (abi == null) {
      _ready = false;
      _ytDlpPath = null;
      _ffmpegPath = null;
      return false;
    }

    for (final file in await _candidateBinaryFiles(abi)) {
      if (await _isRunnable(file)) {
        _ytDlpPath = file.path;
        _ffmpegPath = null;
        _ready = true;
        return true;
      }
    }

    _ytDlpPath = null;
    _ffmpegPath = null;
    _ready = false;
    return false;
  }

  // -- helpers ---------------------------------------------------------------

  /// Maps the current [Abi] to an Android ABI directory name.
  String? _currentAbi() {
    switch (Abi.current()) {
      case Abi.androidArm64:
        return 'arm64-v8a';
      case Abi.androidArm:
        return 'armeabi-v7a';
      case Abi.androidX64:
        return 'x86_64';
      case Abi.androidIA32:
        // 32-bit x86 devices are rare; fall back to armeabi-v7a via houdini.
        return 'armeabi-v7a';
      default:
        return null;
    }
  }

  Future<List<File>> _candidateBinaryFiles(String abi) async {
    final supportDir = await getApplicationSupportDirectory();
    final tempDir = await getTemporaryDirectory();
    return [
      File('${tempDir.path}/binaries/$abi/yt-dlp'),
      File('${supportDir.path}/binaries/$abi/yt-dlp'),
    ];
  }

  Future<bool> _ensureExecutable(File file) async {
    final commands = <List<String>>[
      ['chmod', '755', file.path],
      ['/system/bin/chmod', '755', file.path],
      ['toybox', 'chmod', '755', file.path],
    ];

    for (final cmd in commands) {
      try {
        final result = await Process.run(cmd.first, cmd.sublist(1));
        if (result.exitCode == 0) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<bool> _isRunnable(File file) async {
    if (!await file.exists()) return false;
    if (await file.length() == 0) return false;

    await _ensureExecutable(file);

    try {
      final result = await Process.run(file.path, ['--version']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    } catch (_) {
      return false;
    }
  }

  String _ytDlpDownloadUrl(String abi) {
    switch (abi) {
      case 'arm64-v8a':
        return 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_aarch64';
      case 'armeabi-v7a':
        return 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_armv7l';
      case 'x86_64':
        return 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux_x86_64';
      default:
        throw UnsupportedError('Unsupported ABI: $abi');
    }
  }
}
