import 'dart:io';

import 'package:fetchio/providers/settings_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  group('API base URL', () {
    test('accepts HTTP(S) URLs with a hostname and path', () {
      expect(validateApiBaseUrl(' https://api.example.test/v1 '), isNull);
      expect(validateApiBaseUrl('http://localhost:8000/api/v1'), isNull);
    });

    test(
        'rejects invalid schemes, missing hosts, credentials, query and fragment',
        () {
      for (final value in [
        'ftp://api.example.test',
        '/api/v1',
        'https://',
        'https://user:password@api.example.test',
        'https://api.example.test?debug=1',
        'https://api.example.test#section',
        'https://bad host.example.test',
      ]) {
        expect(validateApiBaseUrl(value), isNotNull, reason: value);
      }
    });

    test('defaults web to same-origin and honors a valid override first', () {
      final origin = Uri.parse('https://fetchio.example.test/app/');
      expect(
        defaultApiBaseUrl(isWeb: true, webBaseUri: origin, override: ''),
        'https://fetchio.example.test/api/v1',
      );
      expect(
        defaultApiBaseUrl(
          isWeb: true,
          webBaseUri: origin,
          override: 'https://api.example.test/custom',
        ),
        'https://api.example.test/custom',
      );
    });

    test('preserves native defaults', () {
      expect(
        defaultApiBaseUrl(
          isWeb: false,
          platform: TargetPlatform.android,
          override: '',
        ),
        'http://10.0.2.2:8000/api/v1',
      );
      expect(
        defaultApiBaseUrl(
          isWeb: false,
          platform: TargetPlatform.iOS,
          override: '',
        ),
        'http://localhost:8000/api/v1',
      );
    });
  });

  group('Hive persistence', () {
    late Directory hiveDirectory;

    setUpAll(() async {
      hiveDirectory =
          await Directory.systemTemp.createTemp('fetchio-settings-');
      Hive.init(hiveDirectory.path);
    });

    tearDown(() async {
      await Hive.close();
    });

    tearDownAll(() async {
      await hiveDirectory.delete(recursive: true);
    });

    test('settings mutation issued immediately is not overwritten by loading',
        () async {
      final box = await Hive.openBox<dynamic>('settings_box');
      await box.put('audioOnly', true);

      final notifier = SettingsNotifier();
      await notifier.setAudioOnly(false);

      expect(notifier.state.audioOnly, isFalse);
      expect(box.get('audioOnly'), isFalse);
      notifier.dispose();
    });

    test('history mutation issued immediately persists after initialization',
        () async {
      final box = await Hive.openBox<String>('search_history_box');
      await box.add('older query');

      final notifier = SearchHistoryNotifier();
      await notifier.add('new query');

      expect(notifier.state, ['new query', 'older query']);
      expect(box.values.toList(), ['older query', 'new query']);
      notifier.dispose();
    });

    test('settings notifier refuses invalid API URLs', () async {
      final notifier = SettingsNotifier();

      await expectLater(
        notifier.setApiBaseUrl('https://api.example.test?token=bad'),
        throwsArgumentError,
      );
      expect(
        notifier.state.apiBaseUrl,
        isNot('https://api.example.test?token=bad'),
      );
      notifier.dispose();
    });
  });
}
