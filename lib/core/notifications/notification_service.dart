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

  /// (Build admin) Notifikasi saat ada user baru mendaftar.
  Future<void> showNewSignup({required String email}) async {
    if (!_initialized) return;
    const androidDetails = AndroidNotificationDetails(
      'admin_approvals',
      'Approval Pendaftaran',
      channelDescription: 'Notifikasi pendaftar baru yang menunggu persetujuan',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      10,
      'Pendaftar Baru',
      '$email menunggu persetujuan Anda.',
      details,
      payload: 'admin_new_signup',
    );
  }

  /// (Build user) Notifikasi saat akun disetujui admin.
  Future<void> showApproved() async {
    if (!_initialized) return;
    const androidDetails = AndroidNotificationDetails(
      'account',
      'Status Akun',
      channelDescription: 'Notifikasi status persetujuan akun',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      11,
      'Akun Disetujui',
      'Akun Anda telah disetujui admin. Selamat menggunakan ScanOrder!',
      details,
      payload: 'account_approved',
    );
  }

  /// Notifikasi generik dari server (mis. anggota tim baru bergabung).
  Future<void> showAppNotification({required String title, String? body}) async {
    if (!_initialized) return;
    const androidDetails = AndroidNotificationDetails(
      'app',
      'Notifikasi Aplikasi',
      channelDescription: 'Notifikasi aktivitas tim dan akun',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
      title,
      body,
      details,
      payload: 'app_notification',
    );
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
