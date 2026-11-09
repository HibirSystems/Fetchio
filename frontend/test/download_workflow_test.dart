import 'dart:async';
import 'dart:convert';

import 'package:fetchio/core/network/backend_api_client.dart';
import 'package:fetchio/core/storage/device_media.dart';
import 'package:fetchio/core/network/backend_download_manager.dart';
import 'package:fetchio/features/download_manager/download_manager_screen.dart';
import 'package:fetchio/features/home/home_screen.dart';
import 'package:fetchio/providers/download_provider.dart';
import 'package:fetchio/shared/models/download_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const completed = DownloadItem(
  downloadId: 'done',
  status: DownloadStatus.completed,
  url: 'https://example.com/video',
  title: 'Completed video',
);
const failed = DownloadItem(
  downloadId: 'failed',
  status: DownloadStatus.failed,
  url: 'https://example.com/video',
  title: 'Failed video',
  error: 'Network interrupted',
);

http.Response downloadList(List<DownloadItem> items) => http.Response(
    jsonEncode({
      'downloads': items.map((item) => item.toJson()).toList(),
      'total': items.length,
      'active': 0,
      'completed': 1,
      'failed': 1,
    }),
    200);

class TestDeviceMedia extends DeviceMedia {
  SavedMedia? saved;
  int saves = 0;
  int opens = 0;
  @override
  Future<void> track(Uri source) async {}
  @override
  Future<List<Uri>> pendingDownloads() async => const [];
  @override
  bool get supportsLocalFiles => true;
  @override
  Future<SavedMedia?> find(Uri source) async => saved;
  @override
  Future<SavedMedia> save(DownloadItem item, Uri source,
      {void Function(double?)? onProgress}) async {
    saves++;
    onProgress?.call(1);
    return saved ??= const SavedMedia(
        uri: 'content://media/downloads/123',
        name: 'Video.mp4',
        mimeType: 'video/mp4');
  }

  @override
  Future<void> open(SavedMedia media) async {
    opens++;
  }
}

void main() {
  testWidgets('completed card plays on tap without save or player buttons',
      (tester) async {
    final device = TestDeviceMedia();
    final repo = BackendDownloadManager('https://example.com/api/v1',
        client: MockClient((_) async => downloadList([completed])));
    final container = ProviderContainer(overrides: [
      downloadProvider.overrideWith((ref) => DownloadNotifier(
            repo,
            deviceMedia: device,
            onDeviceState: (id, value) =>
                ref.read(deviceDownloadProvider.notifier).state = {
              ...ref.read(deviceDownloadProvider),
              id: value,
            },
          )),
      deviceMediaProvider.overrideWithValue(device),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DownloadManagerScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Save to device'), findsNothing);
    expect(find.text('Save file'), findsNothing);
    expect(find.text('Open player'), findsNothing);
    await tester.tap(find.text('Completed video'));
    await tester.pumpAndSettle();
    expect(device.saves, 1);
    expect(device.opens, 1);
    expect(find.text('Downloads/Fetchio'), findsOneWidget);
    await tester.tap(find.text('Completed video'));
    await tester.pumpAndSettle();
    expect(device.saves, 1);
    expect(device.opens, 2);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    repo.dispose();
  });

  testWidgets(
      'device transfers stay active until saved and failures appear in history',
      (tester) async {
    final repo = BackendDownloadManager('https://example.com/api/v1',
        client: MockClient((_) async => downloadList([completed])));
    final container = ProviderContainer(overrides: [
      downloadProvider.overrideWith((ref) => DownloadNotifier(repo))
    ]);
    container.read(deviceDownloadProvider.notifier).state = {
      completed.downloadId:
          const DeviceDownloadState(saving: true, progress: 0.5),
    };
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DownloadManagerScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Active (1)'), findsOneWidget);
    expect(find.text('Completed (1)'), findsNothing);
    expect(find.text('Saving to Downloads/Fetchio: 50%'), findsOneWidget);
    container.read(deviceDownloadProvider.notifier).state = {
      completed.downloadId:
          const DeviceDownloadState(error: 'Device storage full'),
    };
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Device storage full'), findsOneWidget);
    expect(find.text('Retry download'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    repo.dispose();
  });

  testWidgets('recent completed download renders its status', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: DownloadTileCompact(item: completed))));
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('client preserves quality selector and builds retry and file routes',
      () async {
    final requests = <http.Request>[];
    final client = BackendApiClient(
        baseUrl: 'https://example.com/api/v1',
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(completed.toJson()), 202);
        }));
    addTearDown(client.dispose);
    await client.startDownload(
        url: completed.url, formatSelector: 'best[height<=720]/best');
    expect(jsonDecode(requests.first.body)['format_selector'],
        'best[height<=720]/best');
    await client.retryDownload('failed');
    expect(requests.last.url.path, '/api/v1/downloads/failed/retry');
    expect(requests.last.method, 'POST');
    expect(client.downloadFileUri('done').toString(),
        'https://example.com/api/v1/downloads/done/file');
  });

  test('refresh failure retains data and recovery clears the error', () async {
    var offline = false;
    final sync = <AsyncValue<void>>[];
    final repo = BackendDownloadManager('https://example.com/api/v1',
        client: MockClient((_) async {
      if (offline) throw http.ClientException('Offline');
      return downloadList([completed]);
    }));
    final notifier = DownloadNotifier(repo, onSync: sync.add);
    addTearDown(() {
      notifier.dispose();
      repo.dispose();
    });
    await notifier.loadAll();
    expect(notifier.state.single.downloadId, 'done');
    offline = true;
    await notifier.loadAll();
    expect(notifier.state.single.downloadId, 'done');
    expect(sync.last.hasError, isTrue);
    offline = false;
    await notifier.loadAll();
    expect(sync.last.hasError, isFalse);
  });

  test('in-flight refresh can finish safely after disposal', () async {
    final response = Completer<http.Response>();
    final repo = BackendDownloadManager('https://example.com/api/v1',
        client: MockClient((_) => response.future));
    final notifier = DownloadNotifier(repo);
    final loading = notifier.loadAll();
    notifier.dispose();
    response.complete(downloadList([]));
    await loading;
    repo.dispose();
  });

  testWidgets('completed files, retry and clear confirmation are actionable',
      (tester) async {
    final requests = <http.Request>[];
    final repo = BackendDownloadManager('https://example.com/api/v1',
        client: MockClient((request) async {
      requests.add(request);
      if (request.method == 'POST') {
        return http.Response(jsonEncode(completed.toJson()), 202);
      }
      if (request.method == 'DELETE') {
        return http.Response('{"cleared":2}', 200);
      }
      return downloadList([completed, failed]);
    }));
    final container = ProviderContainer(overrides: [
      downloadProvider.overrideWith((ref) => DownloadNotifier(repo)),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DownloadManagerScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Save file'), findsNothing);
    expect(find.text('Open player'), findsNothing);
    expect(find.text('Completed video'), findsOneWidget);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry download'));
    await tester.pumpAndSettle();
    expect(requests.any((r) => r.url.path.endsWith('/failed/retry')), isTrue);
    await tester.tap(find.byTooltip('Clear finished history'));
    await tester.pumpAndSettle();
    expect(find.text('Clear finished history?'), findsOneWidget);
    await tester.tap(find.text('Keep history'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'DELETE'), isEmpty);
    await tester.tap(find.byTooltip('Clear finished history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.method == 'DELETE'), hasLength(1));
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    repo.dispose();
  });
}
