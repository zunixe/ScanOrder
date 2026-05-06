import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';
import 'core/supabase/supabase_service.dart';
import 'core/monitoring/monitoring_service.dart';
import 'core/monitoring/analytics_service.dart';
import 'core/notifications/notification_service.dart';
import 'services/sync_queue.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize crash reporting & performance monitoring (no-op if SENTRY_DSN not set)
  await MonitoringService.init();

  await initializeDateFormatting('id_ID', null);
  await SupabaseService().initialize();

  // Initialize local notifications
  await NotificationService().init();

  // Track app open
  await AnalyticsService.appOpen();

  // Process any pending sync tasks from previous sessions
  try {
    SyncQueue().processPending();
  } catch (e) {
    debugPrint('SyncQueue processPending error: $e');
  }

  runApp(const ScanOrderApp());
}
