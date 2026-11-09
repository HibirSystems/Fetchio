import 'dart:async';
import 'dart:convert';

import 'package:fetchio/core/network/backend_api_client.dart';
import 'package:fetchio/core/network/backend_download_manager.dart';
import 'package:fetchio/features/download_manager/download_manager_screen.dart';
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

void main() {
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
      if (request.method == 'POST')
        return http.Response(jsonEncode(completed.toJson()), 202);
      if (request.method == 'DELETE')
        return http.Response('{"cleared":2}', 200);
      return downloadList([completed, failed]);
    }));
    final container = ProviderContainer(overrides: [
      downloadProvider.overrideWith((ref) => DownloadNotifier(repo)),
    ]);
    addTearDown(() {
      container.dispose();
      repo.dispose();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DownloadManagerScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Save file'), findsOneWidget);
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
  });
}
