import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fetchio/main.dart';

void main() {
  testWidgets('App renders splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: FetchioApp(),
      ),
    );

    expect(find.text('Fetchio'), findsOneWidget);
    expect(find.text('Download anything, anywhere'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
