import '../../shared/models/search_result.dart';
import 'backend_api_client.dart';

class BackendSearchRepository {
  BackendSearchRepository(String baseUrl)
      : _client = BackendApiClient(baseUrl: baseUrl);

  final BackendApiClient _client;

  Future<SearchResponse> search({
    required String query,
    int page = 1,
    int perPage = 20,
  }) {
    return _client.search(query: query, page: page, perPage: perPage);
  }

  void dispose() => _client.dispose();
}
