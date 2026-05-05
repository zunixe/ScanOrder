import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/offline/exponential_backoff.dart';

void main() {
  group('ExponentialBackoff', () {
    test('getDelay increases exponentially', () {
      const backoff = ExponentialBackoff(
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(minutes: 5),
        maxRetries: 5,
      );

      final d0 = backoff.getDelay(0);
      final d1 = backoff.getDelay(1);
      final d2 = backoff.getDelay(2);

      // Base delay is 1s, so: 1s, 2s, 4s (plus jitter)
      expect(d0.inSeconds, greaterThanOrEqualTo(0));
      expect(d1.inSeconds, greaterThanOrEqualTo(1));
      expect(d2.inSeconds, greaterThanOrEqualTo(2));
    });

    test('getDelay is capped at maxDelay', () {
      const backoff = ExponentialBackoff(
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 10),
        maxRetries: 10,
      );

      final d10 = backoff.getDelay(10);
      expect(d10.inSeconds, lessThanOrEqualTo(10));
    });

    test('shouldRetry returns true when below maxRetries', () {
      const backoff = ExponentialBackoff(maxRetries: 3);
      expect(backoff.shouldRetry(0), isTrue);
      expect(backoff.shouldRetry(1), isTrue);
      expect(backoff.shouldRetry(2), isTrue);
    });

    test('shouldRetry returns false when at maxRetries', () {
      const backoff = ExponentialBackoff(maxRetries: 3);
      expect(backoff.shouldRetry(3), isFalse);
      expect(backoff.shouldRetry(4), isFalse);
    });

    test('getRetryInfo returns correct info', () {
      const backoff = ExponentialBackoff(maxRetries: 5);
      final info = backoff.getRetryInfo(2);
      expect(info.shouldRetry, isTrue);
      expect(info.retryCount, 2);
      expect(info.maxRetries, 5);
      expect(info.delay.inSeconds, greaterThan(0));
    });

    test('getRetryInfo for exhausted retries', () {
      const backoff = ExponentialBackoff(maxRetries: 3);
      final info = backoff.getRetryInfo(3);
      expect(info.shouldRetry, isFalse);
      expect(info.delay, Duration.zero);
    });
  });

  group('RetryInfo', () {
    test('toString shows attempt info when shouldRetry is true', () {
      const info = RetryInfo(
        shouldRetry: true,
        delay: Duration(seconds: 5),
        retryCount: 2,
        maxRetries: 5,
      );
      expect(info.toString(), contains('3/5'));
      expect(info.toString(), contains('5s'));
    });

    test('toString shows exceeded when shouldRetry is false', () {
      const info = RetryInfo(
        shouldRetry: false,
        delay: Duration.zero,
        retryCount: 5,
        maxRetries: 5,
      );
      expect(info.toString(), contains('exceeded'));
    });
  });

  group('RetryPolicy', () {
    test('isRetryable returns true by default for all exceptions', () {
      const policy = RetryPolicy();
      expect(policy.isRetryable(Exception('test')), isTrue);
    });

    test('isRetryable returns false for non-retryable exceptions', () {
      const policy = RetryPolicy(
        nonRetryableExceptions: [FormatException],
      );
      expect(policy.isRetryable(FormatException('bad')), isFalse);
      expect(policy.isRetryable(Exception('other')), isTrue);
    });

    test('isRetryable returns true only for retryable exceptions when specified', () {
      const policy = RetryPolicy(
        retryableExceptions: [TimeoutException],
      );
      expect(policy.isRetryable(TimeoutException('timeout')), isTrue);
      expect(policy.isRetryable(Exception('other')), isFalse);
    });

    test('calculateDelay with none policy returns zero', () {
      const policy = RetryPolicy(type: RetryPolicyType.none);
      expect(policy.calculateDelay(0), Duration.zero);
      expect(policy.calculateDelay(5), Duration.zero);
    });

    test('calculateDelay with fixedDelay returns baseDelay', () {
      const policy = RetryPolicy(
        type: RetryPolicyType.fixedDelay,
        baseDelay: Duration(seconds: 2),
        maxRetries: 5,
      );
      expect(policy.calculateDelay(0), const Duration(seconds: 2));
      expect(policy.calculateDelay(3), const Duration(seconds: 2));
    });

    test('calculateDelay with exponentialBackoff increases', () {
      const policy = RetryPolicy(
        type: RetryPolicyType.exponentialBackoff,
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(minutes: 5),
        maxRetries: 10,
      );
      final d0 = policy.calculateDelay(0);
      final d1 = policy.calculateDelay(1);
      expect(d1.inSeconds, greaterThan(d0.inSeconds));
    });

    test('calculateDelay with linearBackoff increases linearly', () {
      const policy = RetryPolicy(
        type: RetryPolicyType.linearBackoff,
        baseDelay: Duration(seconds: 2),
        maxDelay: Duration(minutes: 5),
        maxRetries: 10,
      );
      final d0 = policy.calculateDelay(0);
      final d1 = policy.calculateDelay(1);
      final d2 = policy.calculateDelay(2);
      expect(d1.inSeconds - d0.inSeconds, 2);
      expect(d2.inSeconds - d1.inSeconds, 2);
    });
  });

  group('RetryExecutor', () {
    test('execute succeeds on first try', () async {
      final executor = RetryExecutor();
      final result = await executor.execute(() async => 42);
      expect(result, 42);
    });

    test('execute retries on failure then succeeds', () async {
      int attempt = 0;
      const policy = RetryPolicy(
        type: RetryPolicyType.fixedDelay,
        baseDelay: Duration(milliseconds: 10),
        maxRetries: 3,
      );
      final executor = RetryExecutor(policy: policy);

      final result = await executor.execute(() async {
        attempt++;
        if (attempt < 3) throw Exception('fail');
        return 'success';
      });
      expect(result, 'success');
      expect(attempt, 3);
    });

    test('execute throws after max retries', () async {
      const policy = RetryPolicy(
        type: RetryPolicyType.fixedDelay,
        baseDelay: Duration(milliseconds: 10),
        maxRetries: 2,
      );
      final executor = RetryExecutor(policy: policy);

      expect(
        () => executor.execute(() async => throw Exception('always fail')),
        throwsA(isException),
      );
    });

    test('execute with none policy does not retry', () async {
      int attempt = 0;
      const policy = RetryPolicy(type: RetryPolicyType.none);
      final executor = RetryExecutor(policy: policy);

      expect(
        () => executor.execute(() async {
          attempt++;
          throw Exception('fail');
        }),
        throwsA(isException),
      );
      // Give time for async to complete
      await Future.delayed(const Duration(milliseconds: 50));
      expect(attempt, 1);
    });
  });

  group('NetworkAwareRetryPolicy', () {
    test('fromConnectionType uses mobile delay for mobile', () {
      final policy = NetworkAwareRetryPolicy.fromConnectionType(isMobileConnection: true);
      expect(policy.baseDelay, const Duration(seconds: 3));
    });

    test('fromConnectionType uses wifi delay for wifi', () {
      final policy = NetworkAwareRetryPolicy.fromConnectionType(isMobileConnection: false);
      expect(policy.baseDelay, const Duration(seconds: 1));
    });
  });

  group('SyncRetryConfig', () {
    test('default config has correct policies', () {
      const config = SyncRetryConfig();
      expect(config.syncPolicy.type, RetryPolicyType.exponentialBackoff);
      expect(config.conflictPolicy.type, RetryPolicyType.none);
      expect(config.networkPolicy.type, RetryPolicyType.exponentialBackoff);
    });
  });
}

// TimeoutException is in dart:async
