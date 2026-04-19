import '../../shared/models/media_info.dart';
import 'backend_api_client.dart';

class BackendMediaRepository {
  BackendMediaRepository(String baseUrl)
      : _client = BackendApiClient(baseUrl: baseUrl);

  final BackendApiClient _client;

  Future<MediaInfo> getInfo(String url) {
    return _client.getMediaInfo(url);
  }

  void dispose() => _client.dispose();
}
