import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/widgets/accessibility.dart';

void main() {
  group('AccessibleIconButton', () {
    testWidgets('renders with tooltip', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AccessibleIconButton(
            icon: Icons.delete,
            onPressed: () {},
            tooltip: 'Delete',
          ),
        ),
      ));
      expect(find.byType(IconButton), findsOneWidget);
      expect(find.byType(Semantics), findsWidgets);
    });

    testWidgets('disabled does not call onPressed', (tester) async {
      var pressed = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AccessibleIconButton(
            icon: Icons.delete,
            onPressed: () => pressed = true,
            tooltip: 'Delete',
            enabled: false,
          ),
        ),
      ));
      await tester.tap(find.byType(IconButton));
      expect(pressed, false);
    });
  });

  group('AccessibleListTile', () {
    testWidgets('renders with title', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AccessibleListTile(
            title: Text('Test Item'),
          ),
        ),
      ));
      expect(find.text('Test Item'), findsOneWidget);
    });

    testWidgets('onTap calls callback when enabled', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AccessibleListTile(
            title: Text('Tap me'),
            onTap: () => tapped = true,
          ),
        ),
      ));
      await tester.tap(find.byType(ListTile));
      expect(tapped, true);
    });

    testWidgets('onTap does not call when disabled', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AccessibleListTile(
            title: Text('Tap me'),
            onTap: () => tapped = true,
            enabled: false,
          ),
        ),
      ));
      await tester.tap(find.byType(ListTile));
      expect(tapped, false);
    });
  });

  group('HighContrastText', () {
    testWidgets('renders text', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HighContrastText(data: 'Hello'),
        ),
      ));
      expect(find.text('Hello'), findsOneWidget);
    });
  });

  group('LargeTouchTarget', () {
    testWidgets('renders with minimum size', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LargeTouchTarget(
            child: Text('Tap'),
            onTap: () {},
          ),
        ),
      ));
      expect(find.text('Tap'), findsOneWidget);
      expect(find.byType(InkWell), findsOneWidget);
    });

    testWidgets('onTap fires', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LargeTouchTarget(
            child: Text('Tap'),
            onTap: () => tapped = true,
          ),
        ),
      ));
      await tester.tap(find.byType(InkWell));
      expect(tapped, true);
    });
  });
}
