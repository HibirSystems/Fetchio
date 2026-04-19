import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/backend_media_repository.dart';
import 'settings_provider.dart';
import '../shared/models/media_info.dart';

final mediaRepositoryProvider = Provider<BackendMediaRepository>((ref) {
  final baseUrl = ref.watch(settingsProvider.select((s) => s.apiBaseUrl));
  final repo = BackendMediaRepository(baseUrl);
  ref.onDispose(repo.dispose);
  return repo;
});

final mediaInfoProvider =
    FutureProvider.family<MediaInfo, String>((ref, url) async {
  return ref.watch(mediaRepositoryProvider).getInfo(url);
});
