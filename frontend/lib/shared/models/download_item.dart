// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

import 'package:json_annotation/json_annotation.dart';

part 'download_item.g.dart';

enum DownloadStatus {
  queued,
  downloading,
  processing,
  completed,
  failed,
  cancelled,
  paused,
}

@JsonSerializable()
class DownloadItem {
  const DownloadItem({
    required this.downloadId,
    required this.status,
    required this.url,
    this.title,
    this.thumbnail,
    this.percent = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.speed,
    this.eta,
    this.formatId,
    this.filename,
    this.error,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  @JsonKey(name: 'download_id')
  final String downloadId;
  final DownloadStatus status;
  final String url;
  final String? title;
  final String? thumbnail;
  final double percent;
  @JsonKey(name: 'downloaded_bytes')
  final int downloadedBytes;
  @JsonKey(name: 'total_bytes')
  final int? totalBytes;
  final double? speed; // bytes/sec
  final int? eta; // seconds remaining
  @JsonKey(name: 'format_id')
  final String? formatId;
  final String? filename;
  final String? error;
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;
  @JsonKey(name: 'updated_at')
  final DateTime? updatedAt;
  @JsonKey(name: 'completed_at')
  final DateTime? completedAt;

  bool get isActive =>
      status == DownloadStatus.queued ||
      status == DownloadStatus.downloading ||
      status == DownloadStatus.processing;

  bool get isTerminal =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;

  factory DownloadItem.fromJson(Map<String, dynamic> json) =>
      _$DownloadItemFromJson(json);

  Map<String, dynamic> toJson() => _$DownloadItemToJson(this);
}

@JsonSerializable()
class DownloadListResponse {
  const DownloadListResponse({
    required this.downloads,
    required this.total,
    required this.active,
    required this.completed,
    required this.failed,
  });

  final List<DownloadItem> downloads;
  final int total;
  final int active;
  final int completed;
  final int failed;

  factory DownloadListResponse.fromJson(Map<String, dynamic> json) =>
      _$DownloadListResponseFromJson(json);

  Map<String, dynamic> toJson() => _$DownloadListResponseToJson(this);
}
