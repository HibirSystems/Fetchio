import 'dart:async';
import 'dart:convert';

import 'package:fetchio/core/network/backend_download_manager.dart';
import 'package:fetchio/core/storage/device_media.dart';
import 'package:fetchio/providers/download_provider.dart';
import 'package:fetchio/shared/models/download_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const completedItem = DownloadItem(
  downloadId: 'job-1',
  status: DownloadStatus.completed,
  url: 'https://example.test/video',
  title: 'Video',
  filename: 'video.mp4',
);

http.Response downloadsResponse(List<DownloadItem> items) => http.Response(
      jsonEncode({
        'downloads': items.map((item) => item.toJson()).toList(),
        'total': items.length,
        'active': 0,
        'completed': items.length,
        'failed': 0,
      }),
      200,
    );

class FakeDeviceMedia extends DeviceMedia {
  FakeDeviceMedia({List<Uri> pending = const []}) : pending = [...pending];

  final List<Uri> pending;
  final List<String> events = [];
  SavedMedia? saved;
  bool failSaves = false;
  int saveCount = 0;
  int openCount = 0;

  @override
  bool get supportsLocalFiles => true;

  @override
  Future<void> track(Uri source) async {
    events.add('track');
    if (!pending.contains(source)) pending.add(source);
  }

  @override
  Future<List<Uri>> pendingDownloads() async => [...pending];

  @override
  Future<SavedMedia?> find(Uri source) async => saved;

  @override
  Future<SavedMedia> save(DownloadItem item, Uri source,
      {void Function(double?)? onProgress}) async {
    events.add('save');
    saveCount++;
    onProgress?.call(0.5);
    if (failSaves) throw StateError('device transfer failed');
    return saved ??= const SavedMedia(
      uri: 'content://downloads/video',
      name: 'video.mp4',
      mimeType: 'video/mp4',
    );
  }

  @override
  Future<void> open(SavedMedia media) async {
    openCount++;
  }
}

void main() {
  late List<http.Request> requests;
  late BackendDownloadManager repository;

  setUp(() {
    requests = [];
    repository = BackendDownloadManager(
      'https://example.test/api/v1',
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST' &&
            request.url.path.endsWith('/downloads')) {
          return http.Response(jsonEncode(completedItem.toJson()), 202);
        }
        return downloadsResponse([completedItem]);
      }),
    );
  });

  tearDown(() => repository.dispose());

  test('started jobs are tracked before refresh and auto-saved on completion',
      () async {
    final media = FakeDeviceMedia();
    final notifier = DownloadNotifier(repository, deviceMedia: media);
    addTearDown(notifier.dispose);

    await notifier.startDownload(url: completedItem.url);
    await Future<void>.delayed(Duration.zero);

    expect(media.events, ['track', 'save']);
    expect(notifier.state.single.downloadId, completedItem.downloadId);
  });

  test('immediate completion is saved even when refresh misses the new job',
      () async {
    repository.dispose();
    repository = BackendDownloadManager(
      'https://example.test/api/v1',
      client: MockClient((request) async {
        requests.add(request);
        return request.method == 'POST'
            ? http.Response(jsonEncode(completedItem.toJson()), 202)
            : downloadsResponse([]);
      }),
    );
    final media = FakeDeviceMedia();
    final notifier = DownloadNotifier(repository, deviceMedia: media);
    addTearDown(notifier.dispose);

    await notifier.startDownload(url: completedItem.url);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.single.status, DownloadStatus.completed);
    expect(media.events, ['track', 'save']);
  });

  test('restores queued jobs but ignores unrelated server history', () async {
    const unrelated = DownloadItem(
      downloadId: 'other',
      status: DownloadStatus.completed,
      url: 'https://example.test/other',
    );
    repository.dispose();
    repository = BackendDownloadManager(
      'https://example.test/api/v1',
      client: MockClient((request) async {
        requests.add(request);
        return downloadsResponse([completedItem, unrelated]);
      }),
    );
    final media = FakeDeviceMedia(
        pending: [repository.downloadFileUri(completedItem.downloadId)]);
    final notifier = DownloadNotifier(repository, deviceMedia: media);
    addTearDown(notifier.dispose);

    await notifier.loadAll();
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.map((item) => item.downloadId), ['job-1', 'other']);
    expect(media.saveCount, 1);
  });

  test(
      'a failed automatic save is attempted once; device retry does not retry job',
      () async {
    final media = FakeDeviceMedia(
      pending: [repository.downloadFileUri(completedItem.downloadId)],
    )..failSaves = true;
    final notifier = DownloadNotifier(repository, deviceMedia: media);
    addTearDown(notifier.dispose);

    await notifier.loadAll();
    await Future<void>.delayed(Duration.zero);
    await notifier.loadAll();
    expect(media.saveCount, 1);

    media.failSaves = false;
    await notifier.retryDevice(completedItem.downloadId);

    expect(media.saveCount, 2);
    expect(requests.every((request) => request.method == 'GET'), isTrue);
  });

  test('play reuses a saved file and opens it', () async {
    final media = FakeDeviceMedia()
      ..saved = const SavedMedia(
        uri: 'content://downloads/already-saved',
        name: 'video.mp4',
        mimeType: 'video/mp4',
      );
    final notifier = DownloadNotifier(repository, deviceMedia: media);
    addTearDown(notifier.dispose);
    await notifier.loadAll();

    final result =
        await notifier.saveToDevice(completedItem.downloadId, play: true);

    expect(result, media.saved);
    expect(media.events, ['track']);
    expect(media.saveCount, 0);
    expect(media.openCount, 1);
  });

  test('player failure leaves the saved file state intact', () async {
    final media = _ThrowingOpenDeviceMedia();
    final published = <DeviceDownloadState>[];
    final notifier = DownloadNotifier(repository,
        deviceMedia: media, onDeviceState: (_, value) => published.add(value));
    addTearDown(notifier.dispose);
    await notifier.loadAll();

    await expectLater(
      notifier.saveToDevice(completedItem.downloadId, play: true),
      throwsStateError,
    );

    expect(published.last.saved, isNotNull);
    expect(published.last.error, isNull);
  });

  test('active download count includes local device saves', () async {
    final container = ProviderContainer(overrides: [
      downloadProvider.overrideWith((ref) => DownloadNotifier(repository)),
    ]);
    addTearDown(container.dispose);
    await container.read(downloadProvider.notifier).loadAll();
    container.read(deviceDownloadProvider.notifier).state = {
      completedItem.downloadId: const DeviceDownloadState(saving: true),
    };

    expect(container.read(activeDownloadCountProvider), 1);
  });

  test('in-flight device save does not publish state after disposal', () async {
    final media = _DelayedDeviceMedia();
    final published = <DeviceDownloadState>[];
    final notifier = DownloadNotifier(repository,
        deviceMedia: media, onDeviceState: (_, value) => published.add(value));
    await notifier.loadAll();
    final saving = notifier.saveToDevice(completedItem.downloadId);
    notifier.dispose();
    media.completeSave();
    await saving;

    expect(published.where((value) => value.saved != null), isEmpty);
  });
}

class _DelayedDeviceMedia extends FakeDeviceMedia {
  final result = Completer<SavedMedia>();

  @override
  Future<SavedMedia> save(DownloadItem item, Uri source,
          {void Function(double?)? onProgress}) =>
      result.future;

  void completeSave() => result.complete(const SavedMedia(
      uri: 'content://downloads/video',
      name: 'video.mp4',
      mimeType: 'video/mp4'));
}

class _ThrowingOpenDeviceMedia extends FakeDeviceMedia {
  @override
  Future<void> open(SavedMedia media) async => throw StateError('no player');
}
