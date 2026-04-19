import '../../shared/models/media_info.dart';
import '../../shared/models/search_result.dart';
import 'ytdlp_runner.dart';

/// Converts a raw yt-dlp info dict into the app's [MediaType] enum string.
String _mediaTypeString(Map<String, dynamic> info) {
  if (info['_type'] == 'playlist') return 'playlist';
  final vcodec = info['vcodec'] as String?;
  final acodec = info['acodec'] as String?;
  if (vcodec != null && vcodec != 'none') return 'video';
  if (acodec != null && acodec != 'none') return 'audio';
  return 'video';
}

/// Normalises a raw yt-dlp entry to the keys expected by
/// [SearchResultItem.fromJson].
Map<String, dynamic> _toSearchItemJson(Map<String, dynamic> raw) {
  return {
    'id': raw['id'] ?? '',
    'title': raw['title'] ?? 'Untitled',
    'url': raw['webpage_url'] ?? raw['url'] ?? '',
    'thumbnail': raw['thumbnail'],
    'duration': raw['duration'],
    'view_count': raw['view_count'],
    'uploader': raw['uploader'] ?? raw['channel'],
    'upload_date': raw['upload_date'],
    'media_type': _mediaTypeString(raw),
    'platform': raw['extractor_key'] ?? raw['extractor'],
    'description': raw['description'],
  };
}

/// Normalises a raw yt-dlp format entry to the keys expected by
/// [VideoFormat.fromJson].
Map<String, dynamic> _toFormatJson(Map<String, dynamic> fmt) {
  String? resolution = fmt['resolution'] as String?;
  if (resolution == null) {
    final h = fmt['height'];
    final w = fmt['width'];
    if (h != null && w != null) {
      resolution = '${w}x$h';
    } else if (h != null) {
      resolution = '${h}p';
    }
  }
  return {
    'format_id': fmt['format_id'] ?? '',
    'ext': fmt['ext'] ?? '',
    'resolution': resolution,
    'fps': fmt['fps'],
    'vcodec': fmt['vcodec'],
    'acodec': fmt['acodec'],
    'filesize': fmt['filesize'],
    'filesize_approx': fmt['filesize_approx'],
    'tbr': fmt['tbr'],
    'vbr': fmt['vbr'],
    'abr': fmt['abr'],
    'quality': fmt['quality'],
    'format_note': fmt['format_note'],
    'protocol': fmt['protocol'],
  };
}

/// Normalises a raw yt-dlp info dict to the keys expected by [MediaInfo.fromJson].
Map<String, dynamic> _toMediaInfoJson(Map<String, dynamic> raw) {
  final formats = (raw['formats'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .map(_toFormatJson)
          .toList() ??
      [];
  return {
    'id': raw['id'] ?? '',
    'title': raw['title'] ?? 'Untitled',
    'url': raw['url'] ?? raw['webpage_url'] ?? '',
    'webpage_url': raw['webpage_url'],
    'thumbnail': raw['thumbnail'],
    'thumbnails': raw['thumbnails'] ?? [],
    'description': raw['description'],
    'duration': raw['duration'],
    'uploader': raw['uploader'] ?? raw['channel'],
    'uploader_id': raw['uploader_id'] ?? raw['channel_id'],
    'upload_date': raw['upload_date'],
    'view_count': raw['view_count'],
    'like_count': raw['like_count'],
    'comment_count': raw['comment_count'],
    'tags': raw['tags'] ?? [],
    'categories': raw['categories'] ?? [],
    'media_type': _mediaTypeString(raw),
    'platform': raw['extractor_key'] ?? raw['extractor'],
    'formats': formats,
    'chapters': raw['chapters'] ?? [],
  };
}

// ── Repository ────────────────────────────────────────────────────────────────

/// Fetches media metadata using the bundled yt-dlp binary.
class LocalMediaRepository {
  const LocalMediaRepository();

  Future<MediaInfo> getInfo(String url) async {
    final raw = await YtDlpRunner.instance.extractInfo(url);
    return MediaInfo.fromJson(_toMediaInfoJson(raw));
  }
}

/// Searches using yt-dlp's `ytsearch` extractor.
class LocalSearchRepository {
  const LocalSearchRepository();

  static const String _provider = 'yt-dlp';

  Future<SearchResponse> search({
    required String query,
    int page = 1,
    int perPage = 20,
  }) async {
    // yt-dlp doesn't natively paginate ytsearch, so we fetch enough items
    // and slice the requested page.
    final fetchLimit = page * perPage;
    final rawEntries = await YtDlpRunner.instance.search(query, fetchLimit);

    final allItems = <SearchResultItem>[];
    for (final raw in rawEntries) {
      try {
        allItems.add(SearchResultItem.fromJson(_toSearchItemJson(raw)));
      } catch (_) {
        // Skip malformed entries.
      }
    }

    final start = (page - 1) * perPage;
    final end = start + perPage;
    final pageItems = allItems.length > start
        ? allItems.sublist(start, end.clamp(0, allItems.length))
        : <SearchResultItem>[];

    return SearchResponse(
      query: query,
      results: pageItems,
      total: allItems.length,
      page: page,
      perPage: perPage,
      provider: _provider,
    );
  }
}
