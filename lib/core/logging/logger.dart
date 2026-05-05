import 'package:flutter/foundation.dart';
import '../monitoring/monitoring_service.dart';

/// Safe logger that replaces debugPrint throughout the app.
///
/// - In debug mode: prints to console (like debugPrint)
/// - In release mode: silent (no console output)
/// - Always sends breadcrumbs to MonitoringService for crash context
/// - Supports log levels: info, warning, error
class AppLogger {
  static const _maxBreadcrumbMessage = 200;

  /// Info-level log. Use for routine flow tracking.
  static void info(String tag, String message, {Map<String, dynamic>? data}) {
    if (kDebugMode) debugPrint('[$tag] $message');
    _breadcrumb(tag, message, data, level: 'info');
  }

  /// Warning-level log. Use for recoverable issues.
  static void warn(String tag, String message, {Map<String, dynamic>? data}) {
    if (kDebugMode) debugPrint('[$tag] ⚠ $message');
    _breadcrumb(tag, message, data, level: 'warning');
  }

  /// Error-level log. Use for failures that should be reported.
  static void error(String tag, String message, {Object? exception, StackTrace? stackTrace, Map<String, dynamic>? data}) {
    if (kDebugMode) debugPrint('[$tag] ✗ $message${exception != null ? ' — $exception' : ''}');
    MonitoringService.reportError(exception ?? message, stackTrace: stackTrace, context: '[$tag] $message', extra: data);
  }

  static void _breadcrumb(String tag, String message, Map<String, dynamic>? data, {required String level}) {
    final msg = message.length > _maxBreadcrumbMessage
        ? '${message.substring(0, _maxBreadcrumbMessage)}...'
        : message;
    MonitoringService.addBreadcrumb(msg, category: tag, data: data);
  }
}
