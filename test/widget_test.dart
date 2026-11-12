import 'package:activelook_flutter/ble/mock_glasses.dart';
import 'package:activelook_flutter/features/scan/scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('finds simulated glasses and displays Hi', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScanScreen(
          scanner: MockGlassesScanner(),
          transportFactory: MockGlassesTransport.new,
        ),
      ),
    );

    // Let the post-frame scan start and deliver results.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('A.Look DEMO01'), findsOneWidget);

    await tester.tap(find.text('A.Look DEMO01'));
    await tester.pump(); // stop scan, mark the tile as connecting
    await tester.pump(
      const Duration(milliseconds: 500),
    ); // simulated connection
    await tester.pump(const Duration(milliseconds: 500)); // route transition
    await tester.pump(const Duration(milliseconds: 500)); // post-frame send

    expect(find.text('Подключено'), findsOneWidget);
    expect(find.text('Цветной (81 RG)'), findsOneWidget);

    // The screen greets the glasses with the happy text field's content.
    // The list is scrollable, so bring the field into view first.
    await tester.scrollUntilVisible(find.byType(TextField), 200);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isNotEmpty);
    expect(find.text(field.controller!.text), findsWidgets);
  });
}
