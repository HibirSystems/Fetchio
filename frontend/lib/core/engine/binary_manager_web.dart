class BinaryManager {
  BinaryManager._();

  static final BinaryManager instance = BinaryManager._();

  bool _ready = false;

  String get ytDlpPath {
    throw UnsupportedError('Local yt-dlp binaries are not supported on web.');
  }

  String? get ffmpegPath => null;

  bool get isReady => _ready;

  Future<void> ensureReady() async {
    throw UnsupportedError('Local yt-dlp binaries are not supported on web.');
  }

  Future<void> installOrUpdateYtDlp() {
    throw UnsupportedError('Local yt-dlp binaries are not supported on web.');
  }

  Future<void> removeYtDlp() async {
    _ready = false;
  }

  Future<bool> refreshStatus() async {
    _ready = false;
    return false;
  }
}
