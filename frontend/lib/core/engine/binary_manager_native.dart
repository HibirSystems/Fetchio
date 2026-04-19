import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Manages lifecycle of yt-dlp binaries downloaded after app installation.
class BinaryManager {
  BinaryManager._();

  static final BinaryManager instance = BinaryManager._();

  static const String _engineMissingMessage =
      'yt-dlp engine is not installed. Open Settings > Engine and tap "Download Engine".';

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

    final dir = await getApplicationSupportDirectory();
    final binDir = Directory('${dir.path}/binaries/$abi');
    await binDir.create(recursive: true);

    final file = File('${binDir.path}/yt-dlp');
    final url = _ytDlpDownloadUrl(abi);

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

      final sink = file.openWrite();
      await response.pipe(sink);
      await sink.flush();
      await sink.close();

      final chmod = await Process.run('chmod', ['755', file.path]);
      if (chmod.exitCode != 0) {
        throw ProcessException(
          'chmod',
          ['755', file.path],
          chmod.stderr.toString(),
          chmod.exitCode,
        );
      }

      _ytDlpPath = file.path;
      _ffmpegPath = null;
      _ready = true;
    } finally {
      client.close(force: true);
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
    final file = await _ytDlpFileForAbi(abi);
    if (await file.exists()) {
      await file.delete();
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

    final file = await _ytDlpFileForAbi(abi);
    if (await file.exists() && await file.length() > 0) {
      _ytDlpPath = file.path;
      _ffmpegPath = null;
      _ready = true;
      return true;
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

  Future<File> _ytDlpFileForAbi(String abi) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/binaries/$abi/yt-dlp');
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
