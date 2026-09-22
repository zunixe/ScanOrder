import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/l10n/app_localizations.dart';
import 'package:scanorder/core/state/async_state.dart';
import 'package:scanorder/core/widgets/async_state_builder.dart';

void main() {
  group('AsyncStateBuilder', () {
    testWidgets('idle state renders SizedBox.shrink by default', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AsyncStateBuilder<int>(
            state: const AsyncState.idle(),
            builder: (_, data) => Text('Data: $data'),
          ),
        ),
      ));
      expect(find.text('Data:'), findsNothing);
    });

    testWidgets('idle state renders custom idleWidget', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AsyncStateBuilder<int>(
            state: const AsyncState.idle(),
            builder: (_, data) => Text('Data: $data'),
            idleWidget: const Text('Idle'),
          ),
        ),
      ));
      expect(find.text('Idle'), findsOneWidget);
    });

    testWidgets('loading state renders CircularProgressIndicator by default', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AsyncStateBuilder<int>(
            state: const AsyncState.loading(),
            builder: (_, data) => Text('Data: $data'),
          ),
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('loading state with previous data shows data', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AsyncStateBuilder<int>(
            state: const AsyncState.loading(previousData: 42),
            builder: (_, data) => Text('Data: $data'),
          ),
        ),
      ));
      expect(find.text('Data: 42'), findsOneWidget);
    });

    testWidgets('data state renders builder', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AsyncStateBuilder<int>(
            state: const AsyncState.data(99),
            builder: (_, data) => Text('Data: $data'),
          ),
        ),
      ));
      expect(find.text('Data: 99'), findsOneWidget);
    });

    testWidgets('error state renders error message', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AsyncStateBuilder<int>(
            state: AsyncState.error('Something went wrong'),
            builder: (_, data) => Text('Data: $data'),
            errorBuilder: (msg, retry) => Text('Error: $msg'),
          ),
        ),
      ));
      expect(find.text('Error: Something went wrong'), findsOneWidget);
    });

    testWidgets('error state with custom errorBuilder', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AsyncStateBuilder<int>(
            state: AsyncState.error('fail'),
            builder: (_, data) => Text('Data: $data'),
            errorBuilder: (msg, retry) => Text('Custom: $msg'),
          ),
        ),
      ));
      expect(find.text('Custom: fail'), findsOneWidget);
    });
  });

  group('InlineLoadingIndicator', () {
    testWidgets('shows child when not loading', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InlineLoadingIndicator(
            isLoading: false,
            child: const Text('Content'),
          ),
        ),
      ));
      expect(find.text('Content'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows indicator when loading', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InlineLoadingIndicator(
            isLoading: true,
            child: const Text('Content'),
          ),
        ),
      ));
      expect(find.text('Content'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('AsyncStateBuilder custom widgets & retry', () {
    Widget host(Widget child) => MaterialApp(
          locale: const Locale('id'),
          localizationsDelegates: [
            AppLocalizationsDelegate(const Locale('id')),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: kSupportedLocales,
          home: Scaffold(body: child),
        );

    testWidgets('uses custom loadingWidget', (tester) async {
      await tester.pumpWidget(host(
        AsyncStateBuilder<int>(
          state: const AsyncState.loading(),
          builder: (_, data) => Text('Data: $data'),
          loadingWidget: const Text('Memuat...'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Memuat...'), findsOneWidget);
    });

    testWidgets('loading with previous data overlays loadingWidget', (tester) async {
      await tester.pumpWidget(host(
        AsyncStateBuilder<int>(
          state: const AsyncState.loading(previousData: 7),
          builder: (_, data) => Text('Data: $data'),
          loadingWidget: const Text('Refreshing'),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Data: 7'), findsOneWidget);
      expect(find.text('Refreshing'), findsOneWidget);
    });

    testWidgets('default error widget shows retry button from onRetry', (tester) async {
      var retried = false;
      await tester.pumpWidget(host(
        AsyncStateBuilder<int>(
          state: AsyncState.error('Gagal memuat'),
          builder: (_, data) => Text('Data: $data'),
          onRetry: () => retried = true,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Gagal memuat'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets('error state with retry embedded in state is used', (tester) async {
      var stateRetried = false;
      await tester.pumpWidget(host(
        AsyncStateBuilder<int>(
          state: AsyncState.error('X', retry: () => stateRetried = true),
          builder: (_, data) => Text('Data: $data'),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(stateRetried, isTrue);
    });
  });

  group('showErrorSnackBar', () {
    testWidgets('shows a snackbar with the message', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showErrorSnackBar(context, 'Ada error'),
              child: const Text('trigger'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('trigger'));
      await tester.pump();
      expect(find.text('Ada error'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });
  });
}
