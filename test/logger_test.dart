import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/logging/logger.dart';

void main() {
  group('AppLogger', () {
    test('info does not throw', () {
      expect(() => AppLogger.info('TestTag', 'Test message'), returnsNormally);
    });

    test('warn does not throw', () {
      expect(() => AppLogger.warn('TestTag', 'Warning message'), returnsNormally);
    });

    test('error does not throw without exception', () {
      expect(() => AppLogger.error('TestTag', 'Error message'), returnsNormally);
    });

    test('error does not throw with exception', () {
      expect(
        () => AppLogger.error('TestTag', 'Error with exception', exception: Exception('test')),
        returnsNormally,
      );
    });

    test('error does not throw with stack trace', () {
      expect(
        () => AppLogger.error('TestTag', 'Error with stack', stackTrace: StackTrace.current),
        returnsNormally,
      );
    });

    test('info with data does not throw', () {
      expect(
        () => AppLogger.info('TestTag', 'With data', data: {'key': 'value'}),
        returnsNormally,
      );
    });

    test('warn with data does not throw', () {
      expect(
        () => AppLogger.warn('TestTag', 'With data', data: {'count': 42}),
        returnsNormally,
      );
    });

    test('long message is truncated in breadcrumb', () {
      final longMessage = 'A' * 300;
      expect(
        () => AppLogger.info('TestTag', longMessage),
        returnsNormally,
      );
    });

    test('message at exactly 200 chars is not truncated', () {
      final msg = 'A' * 200;
      expect(() => AppLogger.info('Tag', msg), returnsNormally);
    });

    test('message at 201 chars is truncated', () {
      final msg = 'A' * 201;
      expect(() => AppLogger.info('Tag', msg), returnsNormally);
    });

    test('error with exception and stack trace and data', () {
      expect(
        () => AppLogger.error(
          'Tag', 'Full error',
          exception: Exception('ex'),
          stackTrace: StackTrace.current,
          data: {'key': 'val'},
        ),
        returnsNormally,
      );
    });

    test('empty tag and message', () {
      expect(() => AppLogger.info('', ''), returnsNormally);
    });

    test('warn with empty data map', () {
      expect(() => AppLogger.warn('Tag', 'msg', data: {}), returnsNormally);
    });
  });
}
