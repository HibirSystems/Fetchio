class SavedMedia {
  const SavedMedia(
      {required this.uri, required this.name, required this.mimeType});
  final String uri;
  final String name;
  final String mimeType;
}

String mediaFilename(String? filename, String id) {
  final name = (filename ?? '').replaceAll('\\', '/').split('/').last;
  final safe = name.replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), '_').trim();
  return safe.isEmpty || safe == '.' || safe == '..' ? 'fetchio-$id.mp4' : safe;
}

String mediaMimeType(String name) {
  switch (name.split('.').last.toLowerCase()) {
    case 'mp4':
      return 'video/mp4';
    case 'mkv':
      return 'video/x-matroska';
    case 'webm':
      return 'video/webm';
    case 'mov':
      return 'video/quicktime';
    case 'mp3':
      return 'audio/mpeg';
    case 'm4a':
      return 'audio/mp4';
    case 'opus':
      return 'audio/opus';
    case 'ogg':
      return 'audio/ogg';
    case 'flac':
      return 'audio/flac';
    case 'wav':
      return 'audio/wav';
    default:
      return 'application/octet-stream';
  }
}
