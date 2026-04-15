// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VideoFormat _$VideoFormatFromJson(Map<String, dynamic> json) => VideoFormat(
      formatId: json['format_id'] as String,
      ext: json['ext'] as String,
      resolution: json['resolution'] as String?,
      fps: (json['fps'] as num?)?.toDouble(),
      vcodec: json['vcodec'] as String?,
      acodec: json['acodec'] as String?,
      filesize: (json['filesize'] as num?)?.toInt(),
      filesizeApprox: (json['filesize_approx'] as num?)?.toInt(),
      tbr: (json['tbr'] as num?)?.toDouble(),
      vbr: (json['vbr'] as num?)?.toDouble(),
      abr: (json['abr'] as num?)?.toDouble(),
      quality: (json['quality'] as num?)?.toDouble(),
      formatNote: json['format_note'] as String?,
      protocol: json['protocol'] as String?,
    );

Map<String, dynamic> _$VideoFormatToJson(VideoFormat instance) =>
    <String, dynamic>{
      'format_id': instance.formatId,
      'ext': instance.ext,
      'resolution': instance.resolution,
      'fps': instance.fps,
      'vcodec': instance.vcodec,
      'acodec': instance.acodec,
      'filesize': instance.filesize,
      'filesize_approx': instance.filesizeApprox,
      'tbr': instance.tbr,
      'vbr': instance.vbr,
      'abr': instance.abr,
      'quality': instance.quality,
      'format_note': instance.formatNote,
      'protocol': instance.protocol,
    };

MediaInfo _$MediaInfoFromJson(Map<String, dynamic> json) => MediaInfo(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      webpageUrl: json['webpage_url'] as String?,
      thumbnail: json['thumbnail'] as String?,
      thumbnails: (json['thumbnails'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      description: json['description'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      uploader: json['uploader'] as String?,
      uploaderId: json['uploader_id'] as String?,
      uploadDate: json['upload_date'] as String?,
      viewCount: (json['view_count'] as num?)?.toInt(),
      likeCount: (json['like_count'] as num?)?.toInt(),
      commentCount: (json['comment_count'] as num?)?.toInt(),
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
      categories: (json['categories'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      mediaType:
          $enumDecodeNullable(_$MediaTypeEnumMap, json['media_type']) ??
              MediaType.video,
      platform: json['platform'] as String?,
      formats: (json['formats'] as List<dynamic>?)
              ?.map((e) => VideoFormat.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      chapters: (json['chapters'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$MediaInfoToJson(MediaInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'url': instance.url,
      'webpage_url': instance.webpageUrl,
      'thumbnail': instance.thumbnail,
      'thumbnails': instance.thumbnails,
      'description': instance.description,
      'duration': instance.duration,
      'uploader': instance.uploader,
      'uploader_id': instance.uploaderId,
      'upload_date': instance.uploadDate,
      'view_count': instance.viewCount,
      'like_count': instance.likeCount,
      'comment_count': instance.commentCount,
      'tags': instance.tags,
      'categories': instance.categories,
      'media_type': _$MediaTypeEnumMap[instance.mediaType]!,
      'platform': instance.platform,
      'formats': instance.formats.map((e) => e.toJson()).toList(),
      'chapters': instance.chapters,
    };

const _$MediaTypeEnumMap = {
  MediaType.video: 'video',
  MediaType.audio: 'audio',
  MediaType.playlist: 'playlist',
  MediaType.unknown: 'unknown',
};
