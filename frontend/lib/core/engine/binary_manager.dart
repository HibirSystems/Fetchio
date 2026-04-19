import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:path_provider/path_provider.dart';

/// Manages extraction and lifecycle of the bundled yt-dlp and ffmpeg binaries.
///
/// On Android, binaries are bundled under `android/app/src/main/jniLibs/{abi}/`
/// and resolved from `nativeLibraryDir` (read-only executable location).
/// On non-Android platforms, binaries fall back to Flutter assets.
class BinaryManager {
  BinaryManager._();

  static final BinaryManager instance = BinaryManager._();
  static const MethodChannel _runtimeChannel =
      MethodChannel('com.hibir.fetchio/runtime');

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

    final abi = _currentAbi();
    if (abi == null) {
      throw UnsupportedError(
        'Unsupported CPU architecture: ${Abi.current()}. '
        'Only arm64-v8a, armeabi-v7a, and x86_64 Android ABIs are supported.',
      );
    }

    if (Platform.isAndroid) {
      _ytDlpPath = await _resolveBundledAndroidBinary('libfetchio_ytdlp.so');
      _ffmpegPath = await _tryResolveBundledAndroidBinary('libfetchio_ffmpeg.so');
      _ready = true;
      return;
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

  Future<String> _resolveBundledAndroidBinary(String filename) async {
    final nativeLibDir =
        await _runtimeChannel.invokeMethod<String>('getNativeLibraryDir');
    if (nativeLibDir == null || nativeLibDir.isEmpty) {
      throw StateError('Failed to resolve Android native library directory.');
    }

    final file = File('$nativeLibDir/$filename');
    if (!file.existsSync()) {
      throw FileSystemException(
        'Bundled binary "$filename" not found in native library directory',
        file.path,
      );
    }

    return file.path;
  }

  Future<String?> _tryResolveBundledAndroidBinary(String filename) async {
    try {
      return await _resolveBundledAndroidBinary(filename);
    } catch (e) {
      debugPrint(
        'Optional Android binary "$filename" is unavailable. '
        'Audio extraction and best-stream merge features may be limited: $e',
      );
      return null;
    }
  }

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
  /// executable. Skips the copy if the file already exists and is non-empty.
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
