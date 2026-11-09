import 'dart:io';

import 'package:fetchio/core/storage/device_media_native.dart';
import 'package:fetchio/core/storage/device_media_types.dart';
import 'package:fetchio/shared/models/download_item.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.hibir.fetchio/media_store');
  const item = DownloadItem(
      downloadId: 'done',
      status: DownloadStatus.completed,
      url: 'https://example.com/video',
      filename: '/app/downloads/Holiday.mp4');
  final uri = Uri.parse('https://example.com/api/v1/downloads/done/file');
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fetchio-device-test-');
    Hive.init(directory.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('streams file to public storage, remembers URI, opens with correct MIME',
      () async {
    var fetches = 0;
    var saves = 0;
    var opened = false;
    final client = MockClient((request) async {
      fetches++;
      return http.Response.bytes([1, 2, 3], 200);
    });
    addTearDown(client.close);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map?;
      if (call.method == 'needsStoragePermission') return false;
      if (call.method == 'mediaExists') return true;
      if (call.method == 'saveToDownloads') {
        saves++;
        expect(await File(args!['sourcePath']).readAsBytes(), [1, 2, 3]);
        expect(args['displayName'], 'Holiday.mp4');
        expect(args['mimeType'], 'video/mp4');
        return 'content://media/downloads/123';
      }
      if (call.method == 'openMedia') {
        opened = true;
        expect(args!['mimeType'], 'video/mp4');
      }
      return null;
    });
    final service = DeviceMedia(
        client: client,
        temporaryDirectory: () async => directory,
        android: true);
    final savesTogether =
        await Future.wait([service.save(item, uri), service.save(item, uri)]);
    expect(savesTogether.first.uri, 'content://media/downloads/123');
    await service.open(savesTogether.first);
    expect(opened, isTrue);
    final restarted = DeviceMedia(
        client: client,
        temporaryDirectory: () async => directory,
        android: true);
    expect((await restarted.find(uri))?.name, 'Holiday.mp4');
    await restarted.save(item, uri);
    expect(fetches, 1);
    expect(saves, 1);
    expect(
        directory
            .listSync()
            .whereType<Directory>()
            .where((d) => d.path.contains('fetchio-transfer')),
        isEmpty);
  });

  test('failed HTTP transfer is not marked saved and can be retried', () async {
    var fails = true;
    final client = MockClient((_) async =>
        fails ? http.Response('missing', 404) : http.Response.bytes([1], 200));
    addTearDown(client.close);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'needsStoragePermission') return false;
      if (call.method == 'saveToDownloads')
        return 'content://media/downloads/124';
      return false;
    });
    final service = DeviceMedia(
        client: client,
        temporaryDirectory: () async => directory,
        android: true);
    await expectLater(service.save(item, uri), throwsA(isA<HttpException>()));
    expect(await service.find(uri), isNull);
    fails = false;
    expect(
        (await service.save(item, uri)).uri, 'content://media/downloads/124');
  });

  test('deleted saved file is removed from local index and can be saved again',
      () async {
    var exists = true;
    var count = 0;
    final client = MockClient((_) async {
      count++;
      return http.Response.bytes([1], 200);
    });
    addTearDown(client.close);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'needsStoragePermission') return false;
      if (call.method == 'mediaExists') return exists;
      if (call.method == 'saveToDownloads')
        return 'content://media/downloads/125';
      return null;
    });
    final service = DeviceMedia(
        client: client,
        temporaryDirectory: () async => directory,
        android: true);
    await service.save(item, uri);
    exists = false;
    expect(await service.find(uri), isNull);
    await service.save(item, uri);
    expect(count, 2);
  });

  test('filenames and MIME use local player-compatible values', () {
    expect(mediaFilename('/server/path/a.mp4', 'id'), 'a.mp4');
    expect(mediaFilename('../', 'id'), 'fetchio-id.mp4');
    expect(mediaMimeType('music.mp3'), 'audio/mpeg');
    expect(mediaMimeType('music.m4a'), 'audio/mp4');
    expect(mediaMimeType('video.mkv'), 'video/x-matroska');
  });
}
