import 'dart:async';
import 'dart:math';


/// Exponential backoff calculator for retry mechanisms
class ExponentialBackoff {
  final Duration baseDelay;
  final Duration maxDelay;
  final double jitterFactor;
  final int maxRetries;

  const ExponentialBackoff({
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(minutes: 5),
    this.jitterFactor = 0.2,
    this.maxRetries = 5,
  });

  /// Calculate delay for a given retry attempt
  Duration getDelay(int retryCount) {
    if (retryCount >= maxRetries) {
      return maxDelay;
    }

    // Calculate exponential delay: baseDelay * 2^retryCount
    final exponentialDelay = Duration(
      milliseconds: baseDelay.inMilliseconds * pow(2, retryCount).toInt(),
    );

    // Cap at maxDelay
    final cappedDelay = exponentialDelay > maxDelay
        ? maxDelay
        : exponentialDelay;

    // Add jitter to prevent thundering herd
    final jitter = _calculateJitter(cappedDelay);

    return cappedDelay + jitter;
  }

  /// Calculate random jitter to add randomness to delay
  Duration _calculateJitter(Duration delay) {
    final jitterRange = delay.inMilliseconds * jitterFactor;
    final random = Random();
    final jitterMs = (random.nextDouble() * jitterRange * 2) - jitterRange;
    return Duration(milliseconds: jitterMs.round());
  }

  /// Check if we should retry based on retry count
  bool shouldRetry(int retryCount) {
    return retryCount < maxRetries;
  }

  /// Get retry info for a given attempt
  RetryInfo getRetryInfo(int retryCount) {
    final shouldRetryNow = shouldRetry(retryCount);
    final delay = shouldRetryNow ? getDelay(retryCount) : Duration.zero;
    
    return RetryInfo(
      shouldRetry: shouldRetryNow,
      delay: delay,
      retryCount: retryCount,
      maxRetries: maxRetries,
    );
  }
}

/// Information about a retry attempt
class RetryInfo {
  final bool shouldRetry;
  final Duration delay;
  final int retryCount;
  final int maxRetries;

  const RetryInfo({
    required this.shouldRetry,
    required this.delay,
    required this.retryCount,
    required this.maxRetries,
  });

  @override
  String toString() {
    if (!shouldRetry) {
      return 'RetryInfo: Max retries ($maxRetries) exceeded';
    }
    return 'RetryInfo: Attempt ${retryCount + 1}/$maxRetries, waiting ${delay.inSeconds}s';
  }
}

/// Retry policy configuration
enum RetryPolicyType {
  /// No retry
  none,
  
  /// Retry with exponential backoff
  exponentialBackoff,
  
  /// Retry with fixed delay
  fixedDelay,
  
  /// Linear backoff (delay increases linearly)
  linearBackoff,
}

class RetryPolicy {
  final RetryPolicyType type;
  final Duration baseDelay;
  final Duration maxDelay;
  final int maxRetries;
  final List<Type> retryableExceptions;
  final List<Type> nonRetryableExceptions;

  const RetryPolicy({
    this.type = RetryPolicyType.exponentialBackoff,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(minutes: 5),
    this.maxRetries = 5,
    this.retryableExceptions = const [],
    this.nonRetryableExceptions = const [],
  });

  /// Check if an exception is retryable
  bool isRetryable(Exception exception) {
    // If non-retryable exceptions are specified, check those first
    if (nonRetryableExceptions.isNotEmpty) {
      for (final type in nonRetryableExceptions) {
        if (exception.runtimeType == type) {
          return false;
        }
      }
    }

    // If retryable exceptions are specified, only retry those
    if (retryableExceptions.isNotEmpty) {
      for (final type in retryableExceptions) {
        if (exception.runtimeType == type) {
          return true;
        }
      }
      return false;
    }

    // Default: retry all exceptions
    return true;
  }

  /// Calculate delay based on policy type
  Duration calculateDelay(int retryCount) {
    switch (type) {
      case RetryPolicyType.none:
        return Duration.zero;
      
      case RetryPolicyType.exponentialBackoff:
        return _exponentialDelay(retryCount);
      
      case RetryPolicyType.fixedDelay:
        return retryCount < maxRetries ? baseDelay : Duration.zero;
      
      case RetryPolicyType.linearBackoff:
        return _linearDelay(retryCount);
    }
  }

  Duration _exponentialDelay(int retryCount) {
    if (retryCount >= maxRetries) {
      return maxDelay;
    }

    final delay = Duration(
      milliseconds: baseDelay.inMilliseconds * pow(2, retryCount).toInt(),
    );

    return delay > maxDelay ? maxDelay : delay;
  }

  Duration _linearDelay(int retryCount) {
    if (retryCount >= maxRetries) {
      return maxDelay;
    }

    final delay = Duration(
      milliseconds: baseDelay.inMilliseconds * (retryCount + 1),
    );

    return delay > maxDelay ? maxDelay : delay;
  }
}

/// Retry executor with support for different policies
class RetryExecutor {
  final RetryPolicy policy;
  final ExponentialBackoff _backoff;
  final void Function(RetryInfo)? onRetry;
  final void Function(Exception, int)? onError;

  RetryExecutor({
    this.policy = const RetryPolicy(),
    ExponentialBackoff? backoff,
    this.onRetry,
    this.onError,
  }) : _backoff = backoff ?? const ExponentialBackoff();

  /// Execute a function with retry logic
  Future<T> execute<T>(Future<T> Function() operation) async {
    int attempt = 0;
    Exception? lastException;

    while (true) {
      try {
        return await operation();
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        
        if (!policy.isRetryable(lastException)) {
          rethrow;
        }

        onError?.call(lastException, attempt);

        final shouldContinue = switch (policy.type) {
          RetryPolicyType.none => false,
          RetryPolicyType.exponentialBackoff => 
            _backoff.shouldRetry(attempt),
          _ => attempt < policy.maxRetries - 1,
        };

        if (!shouldContinue) {
          throw lastException;
        }

        final delay = switch (policy.type) {
          RetryPolicyType.exponentialBackoff => 
            _backoff.getDelay(attempt),
          _ => policy.calculateDelay(attempt),
        };

        onRetry?.call(RetryInfo(
          shouldRetry: true,
          delay: delay,
          retryCount: attempt + 1,
          maxRetries: policy.maxRetries,
        ));

        await Future.delayed(delay);
        attempt++;
      }
    }
  }

  /// Execute with callback for each attempt
  Future<T> executeWithAttempts<T>({
    required Future<T> Function(int attempt) operation,
    void Function(int attempt, T result)? onSuccess,
  }) async {
    int attempt = 0;

    return execute(() async {
      final result = await operation(attempt);
      onSuccess?.call(attempt, result);
      return result;
    });
  }
}

/// Network-aware retry policy that adjusts based on connection type
class NetworkAwareRetryPolicy extends RetryPolicy {
  final Duration mobileBaseDelay;
  final Duration wifiBaseDelay;

  const NetworkAwareRetryPolicy({
    this.mobileBaseDelay = const Duration(seconds: 3),
    this.wifiBaseDelay = const Duration(seconds: 1),
    super.baseDelay = const Duration(seconds: 1),
    super.maxDelay = const Duration(minutes: 5),
    super.maxRetries = 5,
    super.retryableExceptions,
    super.nonRetryableExceptions,
  });

  factory NetworkAwareRetryPolicy.fromConnectionType({
    required bool isMobileConnection,
    Duration? mobileBaseDelay,
    Duration? wifiBaseDelay,
  }) {
    return NetworkAwareRetryPolicy(
      mobileBaseDelay: mobileBaseDelay ?? const Duration(seconds: 3),
      wifiBaseDelay: wifiBaseDelay ?? const Duration(seconds: 1),
      baseDelay: isMobileConnection 
          ? (mobileBaseDelay ?? const Duration(seconds: 3))
          : (wifiBaseDelay ?? const Duration(seconds: 1)),
    );
  }
}

/// Sync-specific retry configuration
class SyncRetryConfig {
  final RetryPolicy syncPolicy;
  final RetryPolicy conflictPolicy;
  final RetryPolicy networkPolicy;

  const SyncRetryConfig({
    this.syncPolicy = const RetryPolicy(
      type: RetryPolicyType.exponentialBackoff,
      maxRetries: 5,
      baseDelay: Duration(seconds: 2),
      maxDelay: Duration(minutes: 10),
    ),
    this.conflictPolicy = const RetryPolicy(
      type: RetryPolicyType.none, // Don't auto-retry conflicts
      maxRetries: 0,
    ),
    this.networkPolicy = const RetryPolicy(
      type: RetryPolicyType.exponentialBackoff,
      maxRetries: 7,
      baseDelay: Duration(seconds: 1),
      maxDelay: Duration(minutes: 5),
      retryableExceptions: [
        // Add network-related exceptions here
      ],
    ),
  });
}
