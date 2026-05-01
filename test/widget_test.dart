import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moondrive/main.dart';

void main() {
  testWidgets('renders cloud manager shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Cloud File Manager'), findsOneWidget);
    expect(find.text('My Files'), findsOneWidget);
    expect(find.text('Search files...'), findsOneWidget);
    expect(
      find.textContaining('Login required for Google Drive'),
      findsWidgets,
    );
  });

  testWidgets('opens add account dialog', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Account').first);
    await tester.pumpAndSettle();

    expect(find.text('Add Cloud Storage Account'), findsOneWidget);
    expect(find.text('Google Drive'), findsWidgets);
    expect(find.text('OneDrive'), findsWidgets);
    expect(find.text('Dropbox'), findsWidgets);
  });

  testWidgets('shows OAuth login hint for OneDrive', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Account').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect').at(1));
    await tester.pumpAndSettle();

    expect(find.text('Login to OneDrive'), findsOneWidget);
    expect(
      find.textContaining('Continue to secure OneDrive sign-in'),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      findsNothing,
    );
  });
}
