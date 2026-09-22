import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/widgets/pagination.dart';

void main() {
  group('PaginationController', () {
    late PaginationController controller;

    setUp(() {
      controller = PaginationController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('initial values', () {
      expect(controller.currentPage, 0);
      expect(controller.pageSize, 20);
      expect(controller.isLoading, false);
      expect(controller.hasMore, true);
      expect(controller.items, isEmpty);
    });

    test('setPageSize updates and notifies', () {
      var notified = false;
      controller.addListener(() => notified = true);
      controller.setPageSize(50);
      expect(controller.pageSize, 50);
      expect(notified, true);
    });

    test('setLoading updates and notifies', () {
      controller.setLoading(true);
      expect(controller.isLoading, true);
    });

    test('setHasMore updates and notifies', () {
      controller.setHasMore(false);
      expect(controller.hasMore, false);
    });

    test('addItems on first page replaces items', () {
      controller.addItems(['a', 'b']);
      expect(controller.items, ['a', 'b']);
    });

    test('addItems on subsequent pages appends', () {
      controller.addItems(['a']);
      controller.nextPage();
      controller.addItems(['b', 'c']);
      expect(controller.items, ['a', 'b', 'c']);
    });

    test('nextPage increments page', () {
      controller.nextPage();
      expect(controller.currentPage, 1);
      controller.nextPage();
      expect(controller.currentPage, 2);
    });

    test('clear resets items and page', () {
      controller.addItems(['a', 'b']);
      controller.nextPage();
      controller.clear();
      expect(controller.items, isEmpty);
      expect(controller.currentPage, 0);
      expect(controller.hasMore, true);
    });

    test('reset clears everything', () {
      controller.addItems(['x']);
      controller.nextPage();
      controller.setHasMore(false);
      controller.reset();
      expect(controller.items, isEmpty);
      expect(controller.currentPage, 0);
      expect(controller.hasMore, true);
    });

    test('dispose does not throw on first call', () {
      final c = PaginationController();
      expect(() => c.dispose(), returnsNormally);
    });
  });

  group('PaginatedListView', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('shows empty state when no items', (tester) async {
      await tester.pumpWidget(host(
        PaginatedListView<String>(
          fetchItems: (page, pageSize) async => <String>[],
          itemBuilder: (_, item, _) => Text(item),
          emptyMessage: 'Kosong',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Kosong'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    });

    testWidgets('uses default empty message', (tester) async {
      await tester.pumpWidget(host(
        PaginatedListView<String>(
          fetchItems: (page, pageSize) async => <String>[],
          itemBuilder: (_, item, _) => Text(item),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('No items found'), findsOneWidget);
    });

    testWidgets('renders fetched items', (tester) async {
      await tester.pumpWidget(host(
        PaginatedListView<String>(
          fetchItems: (page, pageSize) async => ['satu', 'dua'],
          itemBuilder: (_, item, _) => Text(item),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('satu'), findsOneWidget);
      expect(find.text('dua'), findsOneWidget);
    });

    testWidgets('shows loading indicator for a full page', (tester) async {
      await tester.pumpWidget(host(
        PaginatedListView<int>(
          initialPageSize: 2,
          fetchItems: (page, pageSize) async => page == 0 ? [1, 2] : <int>[],
          itemBuilder: (_, item, _) => Text('$item'),
          showLoadingIndicator: true,
        ),
      ));
      await tester.pump(); // initial setState(loading)
      await tester.pump(); // fetch completes
      // A full page keeps _hasMore true → trailing loader present.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('hides loader when showLoadingIndicator is false', (tester) async {
      await tester.pumpWidget(host(
        PaginatedListView<int>(
          initialPageSize: 2,
          fetchItems: (page, pageSize) async => page == 0 ? [1, 2] : <int>[],
          itemBuilder: (_, item, _) => Text('$item'),
          showLoadingIndicator: false,
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('keeps last state on fetch error', (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(
        PaginatedListView<String>(
          fetchItems: (page, pageSize) async {
            calls++;
            if (calls > 1) throw Exception('boom');
            return ['ok'];
          },
          itemBuilder: (_, item, _) => Text(item),
          initialPageSize: 10,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('ok'), findsOneWidget);
    });
  });
}
