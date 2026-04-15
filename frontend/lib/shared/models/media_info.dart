// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

import 'package:json_annotation/json_annotation.dart';

import 'search_result.dart';

part 'media_info.g.dart';

@JsonSerializable()
class VideoFormat {
  const VideoFormat({
    required this.formatId,
    required this.ext,
    this.resolution,
    this.fps,
    this.vcodec,
    this.acodec,
    this.filesize,
    this.filesizeApprox,
    this.tbr,
    this.vbr,
    this.abr,
    this.quality,
    this.formatNote,
    this.protocol,
  });

  @JsonKey(name: 'format_id')
  final String formatId;
  final String ext;
  final String? resolution;
  final double? fps;
  final String? vcodec;
  final String? acodec;
  final int? filesize;
  @JsonKey(name: 'filesize_approx')
  final int? filesizeApprox;
  final double? tbr;
  final double? vbr;
  final double? abr;
  final double? quality;
  @JsonKey(name: 'format_note')
  final String? formatNote;
  final String? protocol;

  int? get effectiveFilesize => filesize ?? filesizeApprox;

  factory VideoFormat.fromJson(Map<String, dynamic> json) =>
      _$VideoFormatFromJson(json);

  Map<String, dynamic> toJson() => _$VideoFormatToJson(this);
}

@JsonSerializable()
class MediaInfo {
  const MediaInfo({
    required this.id,
    required this.title,
    required this.url,
    this.webpageUrl,
    this.thumbnail,
    this.thumbnails = const [],
    this.description,
    this.duration,
    this.uploader,
    this.uploaderId,
    this.uploadDate,
    this.viewCount,
    this.likeCount,
    this.commentCount,
    this.tags = const [],
    this.categories = const [],
    this.mediaType = MediaType.video,
    this.platform,
    this.formats = const [],
    this.chapters = const [],
  });

  final String id;
  final String title;
  final String url;
  @JsonKey(name: 'webpage_url')
  final String? webpageUrl;
  final String? thumbnail;
  final List<Map<String, dynamic>> thumbnails;
  final String? description;
  final int? duration;
  final String? uploader;
  @JsonKey(name: 'uploader_id')
  final String? uploaderId;
  @JsonKey(name: 'upload_date')
  final String? uploadDate;
  @JsonKey(name: 'view_count')
  final int? viewCount;
  @JsonKey(name: 'like_count')
  final int? likeCount;
  @JsonKey(name: 'comment_count')
  final int? commentCount;
  final List<String> tags;
  final List<String> categories;
  @JsonKey(name: 'media_type')
  final MediaType mediaType;
  final String? platform;
  final List<VideoFormat> formats;
  final List<Map<String, dynamic>> chapters;

  factory MediaInfo.fromJson(Map<String, dynamic> json) =>
      _$MediaInfoFromJson(json);

  Map<String, dynamic> toJson() => _$MediaInfoToJson(this);
}
