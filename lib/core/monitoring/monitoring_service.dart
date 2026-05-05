import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Centralized crash reporting and performance monitoring via Sentry.
///
/// Sentry DSN is read from compile-time env: SENTRY_DSN
/// If not configured, all methods are no-ops.
class MonitoringService {
  static const String _sentryDsn = String.fromEnvironment('SENTRY_DSN');

  static bool get _isConfigured => _sentryDsn.isNotEmpty;

  /// Initialize Sentry. Call before runApp.
  static Future<void> init() async {
    if (!_isConfigured) {
      debugPrint('[Monitoring] SENTRY_DSN not set — monitoring disabled');
      return;
    }
    await SentryFlutter.init(
      (options) {
        options.dsn = _sentryDsn;
        options.tracesSampleRate = 1.0; // 100% for dev, reduce for prod
        options.profilesSampleRate = 1.0;
        options.environment = kDebugMode ? 'development' : 'production';
        options.attachStacktrace = true;
        options.sendDefaultPii = false; // don't send PII by default
      },
      appRunner: () {}, // we call runApp ourselves
    );
    debugPrint('[Monitoring] Sentry initialized');
  }

  // ─── Crash Reporting ────────────────────────────────────────────────

  /// Report a caught exception with optional stack trace and context.
  static Future<void> reportError(
    dynamic exception, {
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? extra,
  }) async {
    if (!_isConfigured) return;
    final event = SentryEvent(
      level: SentryLevel.error,
      message: context != null ? SentryMessage(context) : null,
      extra: extra,
    );
    await Sentry.captureException(exception, stackTrace: stackTrace, hint: Hint.withMap({'event': event}));
  }

  /// Add user context to crash reports (without PII).
  static Future<void> setUser({String? id, String? email, String? username}) async {
    if (!_isConfigured) return;
    await Sentry.configureScope((scope) {
      scope.setUser(SentryUser(
        id: id,
        email: email,
        username: username,
      ));
    });
  }

  /// Add a breadcrumb for crash context.
  static void addBreadcrumb(String message, {String? category, Map<String, dynamic>? data}) {
    if (!_isConfigured) return;
    Sentry.addBreadcrumb(Breadcrumb(
      message: message,
      category: category ?? 'app',
      data: data,
      level: SentryLevel.info,
    ));
  }

  // ─── Performance Monitoring ─────────────────────────────────────────

  /// Start a performance transaction. Returns null if not configured.
  static ISentrySpan? startTransaction(String name, String operation) {
    if (!_isConfigured) return null;
    return Sentry.startTransaction(name, operation, bindToScope: true);
  }

  /// Measure an async operation and report its duration.
  static Future<T> measure<T>(String name, String operation, Future<T> Function() fn) async {
    if (!_isConfigured) return await fn();
    final span = startTransaction(name, operation);
    try {
      final result = await fn();
      span?.status = const SpanStatus.ok();
      return result;
    } catch (e) {
      span?.status = const SpanStatus.internalError();
      span?.throwable = e;
      rethrow;
    } finally {
      await span?.finish();
    }
  }
}
