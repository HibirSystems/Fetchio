import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../shared/models/download_item.dart';
import '../../shared/models/media_info.dart';
import '../../shared/models/search_result.dart';

class BackendApiClient {
  BackendApiClient({required String baseUrl, http.Client? client})
      : _client = client ?? http.Client(),
        baseUri = _normalizeBaseUrl(baseUrl);

  final Uri baseUri;
  final http.Client _client;

  static Uri _normalizeBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'must not be empty');
    }
    final normalized = trimmed.endsWith('/') ? trimmed : '$trimmed/';
    return Uri.parse(normalized);
  }

  Uri _resolve(String path, [Map<String, String?>? queryParameters]) {
    final uri = baseUri.resolve(path);
    if (queryParameters == null || queryParameters.isEmpty) return uri;
    return uri.replace(
      queryParameters: {
        for (final entry in queryParameters.entries)
          if (entry.value != null && entry.value!.isNotEmpty)
            entry.key: entry.value!,
      },
    );
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) return const {};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Expected JSON object');
  }

  Never _throwHttpError(http.Response response, Uri uri) {
    String message =
        'Request to $uri failed with status ${response.statusCode}';
    final body = response.body.trim();
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          final detail = decoded['detail'];
          if (detail != null) {
            message = detail.toString();
          }
        } else {
          message = body;
        }
      } catch (_) {
        message = body;
      }
    }
    throw Exception(message);
  }

  Future<Map<String, dynamic>> _getJson(
    String path, [
    Map<String, String?>? queryParameters,
  ]) async {
    final uri = _resolve(path, queryParameters);
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttpError(response, uri);
    }
    return _decodeJson(response);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = _resolve(path);
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttpError(response, uri);
    }
    return _decodeJson(response);
  }

  Future<SearchResponse> search({
    required String query,
    int page = 1,
    int perPage = 20,
    String? mediaType,
  }) async {
    final json = await _getJson('search', {
      'q': query,
      'page': page.toString(),
      'per_page': perPage.toString(),
      if (mediaType != null) 'media_type': mediaType,
    });
    return SearchResponse.fromJson(json);
  }

  Future<MediaInfo> getMediaInfo(String url) async {
    final json = await _getJson('media/info', {'url': url});
    return MediaInfo.fromJson(json);
  }

  Future<DownloadItem> startDownload({
    required String url,
    String? formatId,
    required String formatSelector,
    bool audioOnly = false,
    String? convertTo,
    bool embedThumbnail = true,
  }) async {
    final json = await _postJson('downloads', {
      'url': url,
      if (formatId != null) 'format_id': formatId,
      'format_selector': formatSelector,
      'audio_only': audioOnly,
      if (convertTo != null) 'convert_to': convertTo,
      'embed_thumbnail': embedThumbnail,
    });
    return DownloadItem.fromJson(json);
  }

  Future<DownloadListResponse> listDownloads() async {
    final json = await _getJson('downloads');
    return DownloadListResponse.fromJson(json);
  }

  Future<DownloadItem?> getDownload(String downloadId) async {
    final uri = _resolve('downloads/$downloadId');
    final response = await _client.get(uri);
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttpError(response, uri);
    }
    return DownloadItem.fromJson(_decodeJson(response));
  }

  Future<bool> cancelDownload(String downloadId) async {
    final uri = _resolve('downloads/$downloadId');
    final response = await _client.delete(uri);
    if (response.statusCode == 404) return false;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttpError(response, uri);
    }
    return true;
  }

  Future<int> clearCompleted() async {
    final uri = _resolve('downloads');
    final response = await _client.delete(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttpError(response, uri);
    }
    final json = _decodeJson(response);
    final cleared = json['cleared'];
    if (cleared is int) return cleared;
    if (cleared is String) return int.tryParse(cleared) ?? 0;
    return 0;
  }

  void dispose() {
    _client.close();
  }
}
