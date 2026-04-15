// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DownloadItem _$DownloadItemFromJson(Map<String, dynamic> json) => DownloadItem(
      downloadId: json['download_id'] as String,
      status: $enumDecode(_$DownloadStatusEnumMap, json['status']),
      url: json['url'] as String,
      title: json['title'] as String?,
      thumbnail: json['thumbnail'] as String?,
      percent: (json['percent'] as num?)?.toDouble() ?? 0.0,
      downloadedBytes: (json['downloaded_bytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['total_bytes'] as num?)?.toInt(),
      speed: (json['speed'] as num?)?.toDouble(),
      eta: (json['eta'] as num?)?.toInt(),
      formatId: json['format_id'] as String?,
      filename: json['filename'] as String?,
      error: json['error'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
    );

Map<String, dynamic> _$DownloadItemToJson(DownloadItem instance) =>
    <String, dynamic>{
      'download_id': instance.downloadId,
      'status': _$DownloadStatusEnumMap[instance.status]!,
      'url': instance.url,
      'title': instance.title,
      'thumbnail': instance.thumbnail,
      'percent': instance.percent,
      'downloaded_bytes': instance.downloadedBytes,
      'total_bytes': instance.totalBytes,
      'speed': instance.speed,
      'eta': instance.eta,
      'format_id': instance.formatId,
      'filename': instance.filename,
      'error': instance.error,
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
      'completed_at': instance.completedAt?.toIso8601String(),
    };

const _$DownloadStatusEnumMap = {
  DownloadStatus.queued: 'queued',
  DownloadStatus.downloading: 'downloading',
  DownloadStatus.processing: 'processing',
  DownloadStatus.completed: 'completed',
  DownloadStatus.failed: 'failed',
  DownloadStatus.cancelled: 'cancelled',
  DownloadStatus.paused: 'paused',
};

DownloadListResponse _$DownloadListResponseFromJson(
        Map<String, dynamic> json) =>
    DownloadListResponse(
      downloads: (json['downloads'] as List<dynamic>)
          .map((e) => DownloadItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num).toInt(),
      active: (json['active'] as num).toInt(),
      completed: (json['completed'] as num).toInt(),
      failed: (json['failed'] as num).toInt(),
    );

Map<String, dynamic> _$DownloadListResponseToJson(
        DownloadListResponse instance) =>
    <String, dynamic>{
      'downloads': instance.downloads.map((e) => e.toJson()).toList(),
      'total': instance.total,
      'active': instance.active,
      'completed': instance.completed,
      'failed': instance.failed,
    };
