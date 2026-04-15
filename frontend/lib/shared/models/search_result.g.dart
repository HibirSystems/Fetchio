// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SearchResultItem _$SearchResultItemFromJson(Map<String, dynamic> json) =>
    SearchResultItem(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      thumbnail: json['thumbnail'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      viewCount: (json['view_count'] as num?)?.toInt(),
      uploader: json['uploader'] as String?,
      uploadDate: json['upload_date'] as String?,
      mediaType:
          $enumDecodeNullable(_$MediaTypeEnumMap, json['media_type']) ??
              MediaType.video,
      platform: json['platform'] as String?,
      description: json['description'] as String?,
    );

Map<String, dynamic> _$SearchResultItemToJson(SearchResultItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'url': instance.url,
      'thumbnail': instance.thumbnail,
      'duration': instance.duration,
      'view_count': instance.viewCount,
      'uploader': instance.uploader,
      'upload_date': instance.uploadDate,
      'media_type': _$MediaTypeEnumMap[instance.mediaType]!,
      'platform': instance.platform,
      'description': instance.description,
    };

const _$MediaTypeEnumMap = {
  MediaType.video: 'video',
  MediaType.audio: 'audio',
  MediaType.playlist: 'playlist',
  MediaType.unknown: 'unknown',
};

SearchResponse _$SearchResponseFromJson(Map<String, dynamic> json) =>
    SearchResponse(
      query: json['query'] as String,
      results: (json['results'] as List<dynamic>)
          .map((e) => SearchResultItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num).toInt(),
      page: (json['page'] as num?)?.toInt() ?? 1,
      perPage: (json['per_page'] as num?)?.toInt() ?? 20,
      provider: json['provider'] as String? ?? 'yt-dlp',
    );

Map<String, dynamic> _$SearchResponseToJson(SearchResponse instance) =>
    <String, dynamic>{
      'query': instance.query,
      'results': instance.results.map((e) => e.toJson()).toList(),
      'total': instance.total,
      'page': instance.page,
      'per_page': instance.perPage,
      'provider': instance.provider,
    };
