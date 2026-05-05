import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'monitoring_service.dart';

/// Lightweight usage analytics — tracks key user actions locally
/// and reports them via [MonitoringService] breadcrumbs for crash context.
///
/// For production analytics, integrate with Supabase analytics or a
/// third-party service (Amplitude, Mixpanel, etc.) by implementing
/// [AnalyticsReporter].
class AnalyticsService {
  static const _prefix = 'analytics_';

  /// Track a named event with optional properties.
  static Future<void> track(String event, {Map<String, dynamic>? properties}) async {
    if (kDebugMode) {
      debugPrint('[Analytics] $event ${properties ?? ''}');
    }

    // Add breadcrumb for crash context
    MonitoringService.addBreadcrumb(event, category: 'analytics', data: properties);

    // Persist event count locally for stats
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt('$_prefix$event') ?? 0;
    await prefs.setInt('$_prefix$event', count + 1);

    // Track session events
    if (event == 'app_open') {
      final opens = prefs.getInt('${_prefix}total_opens') ?? 0;
      await prefs.setInt('${_prefix}total_opens', opens + 1);
    }
  }

  /// Get event count for a specific event.
  static Future<int> getEventCount(String event) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_prefix$event') ?? 0;
  }

  /// Get total app opens.
  static Future<int> getTotalOpens() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('${_prefix}total_opens') ?? 0;
  }

  /// Track screen view.
  static Future<void> screenView(String screenName) async {
    await track('screen_view', properties: {'screen': screenName});
  }

  // ─── Predefined Events ──────────────────────────────────────────────

  static Future<void> appOpen() => track('app_open');
  static Future<void> scanComplete(String marketplace, {bool hasPhoto = false}) =>
      track('scan_complete', properties: {'marketplace': marketplace, 'has_photo': hasPhoto});
  static Future<void> scanDuplicate(String resi) =>
      track('scan_duplicate', properties: {'resi_prefix': resi.length > 4 ? resi.substring(0, 4) : resi});
  static Future<void> login(String method) =>
      track('login', properties: {'method': method});
  static Future<void> logout() => track('logout');
  static Future<void> exportData(String format) =>
      track('export_data', properties: {'format': format});
  static Future<void> syncComplete({int? count}) =>
      track('sync_complete', properties: {if (count != null) 'count': count});
  static Future<void> syncError(String error) =>
      track('sync_error', properties: {'error': error});
  static Future<void> categoryCreated(String name) =>
      track('category_created', properties: {'name': name});
  static Future<void> subscriptionView() => track('subscription_view');
  static Future<void> subscriptionPurchase(String tier) =>
      track('subscription_purchase', properties: {'tier': tier});
  static Future<void> teamJoin() => track('team_join');
  static Future<void> teamCreate() => track('team_create');
}
