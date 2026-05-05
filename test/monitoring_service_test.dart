import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/monitoring/monitoring_service.dart';

void main() {
  group('MonitoringService', () {
    test('init does not throw when SENTRY_DSN is not set', () async {
      // SENTRY_DSN is empty in test environment
      expect(() => MonitoringService.init(), returnsNormally);
    });

    test('reportError does not throw when not configured', () async {
      expect(
        () => MonitoringService.reportError('test error'),
        returnsNormally,
      );
    });

    test('setUser does not throw when not configured', () async {
      expect(
        () => MonitoringService.setUser(id: 'test-user'),
        returnsNormally,
      );
    });

    test('addBreadcrumb does not throw when not configured', () {
      expect(
        () => MonitoringService.addBreadcrumb('test breadcrumb'),
        returnsNormally,
      );
    });

    test('addBreadcrumb with category and data does not throw', () {
      expect(
        () => MonitoringService.addBreadcrumb('test', category: 'test_cat', data: {'key': 'val'}),
        returnsNormally,
      );
    });

    test('startTransaction returns null when not configured', () {
      final span = MonitoringService.startTransaction('test', 'op');
      expect(span, isNull);
    });

    test('measure runs function when not configured', () async {
      final result = await MonitoringService.measure('test', 'op', () async => 42);
      expect(result, 42);
    });

    test('measure propagates exceptions', () async {
      expect(
        () => MonitoringService.measure('test', 'op', () async => throw Exception('boom')),
        throwsA(isA<Exception>()),
      );
    });
  });
}
