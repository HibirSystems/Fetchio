import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/engine/local_media_repository.dart';
import '../shared/models/media_info.dart';

final mediaRepositoryProvider = Provider<LocalMediaRepository>((ref) {
  return const LocalMediaRepository();
});

final mediaInfoProvider =
    FutureProvider.family<MediaInfo, String>((ref, url) async {
  return ref.watch(mediaRepositoryProvider).getInfo(url);
});
