import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../core/network/dio_client.dart';
import '../shared/models/media_info.dart';

class MediaRepository {
  const MediaRepository(this._dio);
  final Dio _dio;

  Future<MediaInfo> getInfo(String url) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/media/info',
      queryParameters: {'url': url},
    );
    return MediaInfo.fromJson(response.data!);
  }
}

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(ref.watch(dioProvider));
});

final mediaInfoProvider =
    FutureProvider.family<MediaInfo, String>((ref, url) async {
  return ref.watch(mediaRepositoryProvider).getInfo(url);
});
