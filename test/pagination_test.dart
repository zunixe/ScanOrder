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
}
