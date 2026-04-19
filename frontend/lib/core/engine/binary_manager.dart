import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Manages extraction and lifecycle of the bundled yt-dlp and ffmpeg binaries.
///
/// Binaries are shipped as Flutter assets under `assets/binaries/{abi}/`.
/// On first run they are copied into the app's private files directory,
/// made executable, and their paths are cached for the session.
class BinaryManager {
  BinaryManager._();

  static final BinaryManager instance = BinaryManager._();

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

  /// Extracts binaries from assets if they are missing or outdated.
  ///
  /// Safe to call multiple times; subsequent calls are no-ops.
  Future<void> ensureReady() async {
    if (_ready) return;

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

    _ytDlpPath = await _extractAsset(
      assetPath: 'assets/binaries/$abi/yt-dlp',
      destFile: File('${binDir.path}/yt-dlp'),
    );

    // ffmpeg is optional — app still works for single-stream downloads without it.
    try {
      _ffmpegPath = await _extractAsset(
        assetPath: 'assets/binaries/$abi/ffmpeg',
        destFile: File('${binDir.path}/ffmpeg'),
      );
    } catch (_) {
      _ffmpegPath = null;
    }

    _ready = true;
  }

  // ── helpers ──────────────────────────────────────────────────────────────

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

  /// Copies [assetPath] from the Flutter bundle to [destFile] and makes it
  /// executable.  Skips the copy if the file already exists and is non-empty.
  Future<String> _extractAsset({
    required String assetPath,
    required File destFile,
  }) async {
    if (!destFile.existsSync() || destFile.lengthSync() == 0) {
      final data = await rootBundle.load(assetPath);
      await destFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    // Ensure the file is executable.
    final chmod = await Process.run('chmod', ['755', destFile.path]);
    if (chmod.exitCode != 0) {
      throw ProcessException(
        'chmod',
        ['755', destFile.path],
        chmod.stderr.toString(),
        chmod.exitCode,
      );
    }

    return destFile.path;
  }
}
