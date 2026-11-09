import 'package:url_launcher/url_launcher.dart';
import '../../shared/models/download_item.dart';
import 'device_media_types.dart';

class DeviceMedia {
  bool get supportsLocalFiles => false;
  Future<SavedMedia?> find(Uri source) async => null;
  Future<SavedMedia> save(DownloadItem item, Uri source,
      {void Function(double?)? onProgress}) async {
    if (!await launchUrl(source, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open file download');
    }
    return SavedMedia(
        uri: source.toString(),
        name: mediaFilename(item.filename, item.downloadId),
        mimeType: mediaMimeType(item.filename ?? ''));
  }

  Future<void> open(SavedMedia media) async {
    if (!await launchUrl(Uri.parse(media.uri),
        mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open media');
    }
  }
}
