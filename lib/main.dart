import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';
import 'core/admin_gate.dart';
import 'core/supabase/supabase_service.dart';
import 'core/monitoring/monitoring_service.dart';
import 'core/monitoring/analytics_service.dart';
import 'core/notifications/notification_service.dart';
import 'services/sync_queue.dart';

/// Entry BUILD USER (flavor `play`) — satu-satunya yang boleh diupload
/// ke Google Play.
///
/// Build:
///   flutter build appbundle --release --flavor play --dart-define-from-file=.env
///
/// Build admin memakai entry [main_admin_path] (lib/main_admin.dart) dan
/// JANGAN PERNAH diupload ke store.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize crash reporting & performance monitoring (no-op if SENTRY_DSN not set)
  await MonitoringService.init();

  await initializeDateFormatting('id_ID', null);
  await SupabaseService().initialize();

  // Hook admin SETELAH Supabase siap — hanya terisi pada build admin
  // (lib/main_admin.dart); build user tidak pernah mengisi field ini.
  final adminPostInit = AdminGate.postInit;
  if (adminPostInit != null) {
    await adminPostInit();
  }

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

void main() => bootstrap();
