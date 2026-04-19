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
    _ready = true;
  }
}
