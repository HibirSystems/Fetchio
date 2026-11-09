import 'package:fetchio/shared/models/media_info.dart';
import 'package:fetchio/shared/widgets/download_options_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const streamUrl =
      'https://rr5.example.googlevideo.com/videoplayback?expire=123';
  const pageUrl = 'https://www.youtube.com/watch?v=p1cNW59M4Cs';
  for (final scenario in [
    (
      name: 'original page overrides legacy stream metadata',
      source: pageUrl,
      webpage: 'https://youtu.be/p1cNW59M4Cs',
      expected: pageUrl
    ),
    (
      name: 'canonical page overrides stream URL',
      source: null,
      webpage: pageUrl,
      expected: pageUrl
    ),
    (
      name: 'blank page falls back to direct media',
      source: ' ',
      webpage: '',
      expected: streamUrl
    ),
  ]) {
    testWidgets(scenario.name, (tester) async {
      Map<String, dynamic>? request;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
        child: DownloadOptionsModal(
          mediaInfo: MediaInfo(
              id: 'video',
              title: 'Video',
              url: streamUrl,
              webpageUrl: scenario.webpage),
          sourceUrl: scenario.source,
          onDownload: (value) => request = value,
        ),
      ))));
      await tester.ensureVisible(find.text('Start Download'));
      await tester.tap(find.text('Start Download'));
      expect(request?['url'], scenario.expected);
      expect(request?['audio_only'], isFalse);
      await tester.tap(find.text('Audio Only'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Start Download'));
      await tester.tap(find.text('Start Download'));
      expect(request?['url'], scenario.expected);
      expect(request?['audio_only'], isTrue);
    });
  }
}
