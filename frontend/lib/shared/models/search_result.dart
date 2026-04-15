// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

import 'package:json_annotation/json_annotation.dart';

part 'search_result.g.dart';

enum MediaType {
  video,
  audio,
  playlist,
  unknown,
}

@JsonSerializable()
class SearchResultItem {
  const SearchResultItem({
    required this.id,
    required this.title,
    required this.url,
    this.thumbnail,
    this.duration,
    this.viewCount,
    this.uploader,
    this.uploadDate,
    this.mediaType = MediaType.video,
    this.platform,
    this.description,
  });

  final String id;
  final String title;
  final String url;
  final String? thumbnail;
  final int? duration;
  @JsonKey(name: 'view_count')
  final int? viewCount;
  final String? uploader;
  @JsonKey(name: 'upload_date')
  final String? uploadDate;
  @JsonKey(name: 'media_type')
  final MediaType mediaType;
  final String? platform;
  final String? description;

  factory SearchResultItem.fromJson(Map<String, dynamic> json) =>
      _$SearchResultItemFromJson(json);

  Map<String, dynamic> toJson() => _$SearchResultItemToJson(this);
}

@JsonSerializable()
class SearchResponse {
  const SearchResponse({
    required this.query,
    required this.results,
    required this.total,
    this.page = 1,
    this.perPage = 20,
    this.provider = 'yt-dlp',
  });

  final String query;
  final List<SearchResultItem> results;
  final int total;
  final int page;
  @JsonKey(name: 'per_page')
  final int perPage;
  final String provider;

  factory SearchResponse.fromJson(Map<String, dynamic> json) =>
      _$SearchResponseFromJson(json);

  Map<String, dynamic> toJson() => _$SearchResponseToJson(this);
}
