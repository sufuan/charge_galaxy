// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:charged_galaxy/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ChargedGalaxyApp());

    // Verify that the home screen title and empty state text are present.
    expect(find.text('Charged Galaxy'), findsOneWidget);
    expect(find.text('No videos found'), findsOneWidget);
    expect(find.byIcon(Icons.video_library), findsOneWidget);
  });
}
