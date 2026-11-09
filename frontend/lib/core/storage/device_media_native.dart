import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../shared/models/download_item.dart';
import 'device_media_types.dart';

class DeviceMedia {
  DeviceMedia(
      {http.Client? client,
      Future<Directory> Function()? temporaryDirectory,
      MethodChannel? channel,
      bool? android})
      : _client = client,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
        _channel =
            channel ?? const MethodChannel('com.hibir.fetchio/media_store'),
        _android = android ?? Platform.isAndroid;

  final http.Client? _client;
  final Future<Directory> Function() _temporaryDirectory;
  final MethodChannel _channel;
  final bool _android;
  final Map<String, Future<SavedMedia>> _saving = {};
  bool get supportsLocalFiles => _android;

  Future<Box<String>> _box() => Hive.openBox<String>('device_media_files');

  Future<SavedMedia?> find(Uri source) async {
    if (!_android) return null;
    final box = await _box();
    final raw = box.get(source.toString());
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final media = SavedMedia(
        uri: data['uri'] as String,
        name: data['name'] as String,
        mimeType: data['mimeType'] as String);
    final exists =
        await _channel.invokeMethod<bool>('mediaExists', {'uri': media.uri}) ??
            false;
    if (!exists) {
      await box.delete(source.toString());
      return null;
    }
    return media;
  }

  Future<SavedMedia> save(DownloadItem item, Uri source,
      {void Function(double?)? onProgress}) {
    final key = source.toString();
    return _saving.putIfAbsent(key, () async {
      try {
        return await _save(item, source, onProgress);
      } finally {
        _saving.remove(key);
      }
    });
  }

  Future<SavedMedia> _save(
      DownloadItem item, Uri source, void Function(double?)? progress) async {
    if (!_android) {
      throw UnsupportedError('Saving to device is supported on Android.');
    }
    final existing = await find(source);
    if (existing != null) return existing;
    if (await _channel.invokeMethod<bool>('needsStoragePermission') == true &&
        !await Permission.storage.request().isGranted) {
      throw Exception('Storage permission is required to save in Downloads.');
    }
    final name = mediaFilename(item.filename, item.downloadId);
    final mime = mediaMimeType(name);
    final directory =
        await (await _temporaryDirectory()).createTemp('fetchio-transfer-');
    final file = File('${directory.path}/transfer.part');
    final client = _client ?? http.Client();
    try {
      final response = await client
          .send(http.Request('GET', source))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException(
            'File transfer failed (HTTP ${response.statusCode}). The server file may no longer exist.');
      }
      final sink = file.openWrite();
      var received = 0;
      final total = response.contentLength;
      try {
        await sink.addStream(
            response.stream.timeout(const Duration(seconds: 30)).map((chunk) {
          received += chunk.length;
          progress?.call(total == null || total <= 0
              ? null
              : (received / total).clamp(0.0, 1.0));
          return chunk;
        }));
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received == 0 || (total != null && total != received)) {
        throw Exception(
            'File transfer was incomplete. Please try saving again.');
      }
      final uri = await _channel.invokeMethod<String>('saveToDownloads', {
        'sourcePath': file.path,
        'displayName': name,
        'mimeType': mime,
      });
      if (uri == null || uri.isEmpty) {
        throw Exception('Android did not confirm the file was saved.');
      }
      final saved = SavedMedia(uri: uri, name: name, mimeType: mime);
      await (await _box()).put(source.toString(),
          jsonEncode({'uri': uri, 'name': name, 'mimeType': mime}));
      return saved;
    } finally {
      if (_client == null) client.close();
      await directory.delete(recursive: true);
    }
  }

  Future<void> open(SavedMedia media) async {
    await _channel.invokeMethod<void>(
        'openMedia', {'uri': media.uri, 'mimeType': media.mimeType});
  }
}
