import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  group('AccessibilityExtensions.withSemantics', () {
    testWidgets('wraps widget in a Semantics widget', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const Text('Isi').withSemantics(label: 'Label Uji'),
        ),
      ));
      final semanticsWidgets = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.label == 'Label Uji');
      expect(semanticsWidgets, isNotEmpty);
    });
  });

  group('HighContrastText extra props', () {
    testWidgets('applies custom style and overflow', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HighContrastText(
            data: 'Panjang sekali teks ini untuk menguji overflow',
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ));
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.textAlign, TextAlign.center);
    });

    testWidgets('preserves explicit style height', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: HighContrastText(
            data: 'X',
            style: const TextStyle(height: 2.0),
          ),
        ),
      ));
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.style!.height, 2.0);
    });
  });

  group('AccessibilityAnnouncement', () {
    testWidgets('announce does not throw', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            ctx = context;
            return const Text('x');
          }),
        ),
      ));
      expect(() => AccessibilityAnnouncement.announce(ctx, 'Halo'), returnsNormally);
      expect(() => AccessibilityAnnouncement.announceError(ctx, 'Error'), returnsNormally);
      expect(() => AccessibilityAnnouncement.announceSuccess(ctx, 'Sukses'), returnsNormally);
    });
  });

  group('FocusTrap', () {
    testWidgets('renders child', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FocusTrap(child: const Text('Focusable')),
        ),
      ));
      expect(find.text('Focusable'), findsOneWidget);
    });

    testWidgets('escape key triggers onEscape', (tester) async {
      var escaped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FocusTrap(
            onEscape: () => escaped = true,
            child: const TextField(),
          ),
        ),
      ));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(escaped, isTrue);
    });

    testWidgets('disposes without error', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FocusTrap(child: const Text('x'))),
      ));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(find.byType(FocusTrap), findsNothing);
    });
  });
}
