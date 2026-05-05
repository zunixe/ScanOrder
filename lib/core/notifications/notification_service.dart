import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../logging/logger.dart';

/// Local push notification service for quota warnings, sync errors, etc.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    final result = await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        AppLogger.info('Notification', 'Tapped notification: ${response.payload}');
      },
    );

    _initialized = result ?? false;
    AppLogger.info('Notification', 'Initialized: $_initialized');
  }

  Future<void> showQuotaWarning({int? remaining, int? limit}) async {
    if (!_initialized) return;
    const androidDetails = AndroidNotificationDetails(
      'quota',
      'Kuota Scan',
      channelDescription: 'Peringatan kuota scan harian',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      0,
      'Kuota Scan Menipis',
      remaining != null
          ? 'Sisa $remaining dari $limit scan hari ini. Upgrade untuk lebih banyak!'
          : 'Kuota scan hampir habis. Upgrade paket untuk lebih banyak scan.',
      details,
      payload: 'quota_warning',
    );
  }

  Future<void> showSyncError({String? error}) async {
    if (!_initialized) return;
    const androidDetails = AndroidNotificationDetails(
      'sync',
      'Sinkronisasi',
      channelDescription: 'Notifikasi sinkronisasi data',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      1,
      'Gagal Sinkronisasi',
      error ?? 'Data gagal dikirim ke cloud. Akan dicoba lagi otomatis.',
      details,
      payload: 'sync_error',
    );
  }

  Future<void> showSubscriptionUpdate({required String tierName}) async {
    if (!_initialized) return;
    const androidDetails = AndroidNotificationDetails(
      'subscription',
      'Langganan',
      channelDescription: 'Notifikasi perubahan langganan',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      2,
      'Langganan Diperbarui',
      'Paket Anda sekarang: $tierName',
      details,
      payload: 'subscription_update',
    );
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
