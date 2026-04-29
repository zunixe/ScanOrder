import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import '../../core/db/database_helper.dart';
import '../../core/supabase/supabase_service.dart';
import '../../models/order.dart';
import '../../services/marketplace_detector.dart';
import '../../services/quota_service.dart';
import 'package:intl/intl.dart';

enum ScanStatus { idle, success, duplicate, quotaExceeded }

class ScanResult {
  final ScanStatus status;
  final String resi;
  final String marketplace;
  final ScannedOrder? existingOrder;

  ScanResult({
    required this.status,
    required this.resi,
    required this.marketplace,
    this.existingOrder,
  });
}

class ScanProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final QuotaService _quota = QuotaService();

  ScanResult? lastResult;
  int todayCount = 0;
  int totalCount = 0;
  bool _processing = false;
  bool _savePhoto = true;

  bool get savePhoto => _savePhoto;

  Future<void> loadCounts() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    todayCount = await _db.getOrderCountByDate(today);
    totalCount = await _db.getTotalOrderCount();
    _savePhoto = await _quota.getSavePhoto();
    notifyListeners();
  }

  Future<void> setSavePhoto(bool value) async {
    _savePhoto = value;
    await _quota.setSavePhoto(value);
    notifyListeners();
  }

  Future<ScanResult?> processScan(String rawCode, String? photoPath) async {
    if (_processing) return null;
    _processing = true;

    try {
      final resi = rawCode.trim();
      if (resi.isEmpty) return null;

      // Filter: hanya terima nomor resi, tolak Order ID dll
      if (!MarketplaceDetector.isValidResi(resi)) return null;

      final marketplace = MarketplaceDetector.detect(resi);

      // Check duplicate
      final existing = await _db.findByResi(resi);
      if (existing != null) {
        lastResult = ScanResult(
          status: ScanStatus.duplicate,
          resi: resi,
          marketplace: marketplace,
          existingOrder: existing,
        );
        notifyListeners();
        return lastResult;
      }

      // Check quota
      if (!await _quota.canScan()) {
        lastResult = ScanResult(
          status: ScanStatus.quotaExceeded,
          resi: resi,
          marketplace: marketplace,
        );
        notifyListeners();
        return lastResult;
      }

      // Check if photo should be saved
      final effectivePhotoPath = _savePhoto ? photoPath : null;
      if (_savePhoto && photoPath != null) {
        // Check storage limit before saving photo
        final remaining = await _quota.getRemainingBytes();
        if (remaining >= 0) {
          try {
            final file = File(photoPath);
            final size = file.lengthSync();
            if (size > remaining) {
              debugPrint('[ScanProvider] Storage full, skipping photo');
              photoPath = null;
            }
          } catch (_) {}
        }
      }

      // Insert new
      final now = DateTime.now();
      final order = ScannedOrder(
        resi: resi,
        marketplace: marketplace,
        scannedAt: now,
        date: DateFormat('yyyy-MM-dd').format(now),
        photoPath: effectivePhotoPath,
      );

      await _db.insertOrder(order);

      // Sync ke Supabase backend (async, tidak blocking)
      _syncToSupabase(order);

      todayCount++;
      totalCount++;

      lastResult = ScanResult(
        status: ScanStatus.success,
        resi: resi,
        marketplace: marketplace,
      );
      notifyListeners();
      return lastResult;
    } catch (e) {
      debugPrint('ScanProvider error: $e');
      return null;
    } finally {
      _processing = false;
    }
  }

  void clearResult() {
    lastResult = null;
    notifyListeners();
  }

  /// Ambil device ID dan kirim ke Supabase (async, tidak blocking)
  void _syncToSupabase(ScannedOrder order) async {
    try {
      final supabase = SupabaseService();
      final user = supabase.currentUser;
      if (user == null) return;

      final deviceInfo = DeviceInfoPlugin();
      String deviceId = 'unknown';
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'unknown';
      }

      // Try to get team_id
      final team = await supabase.getMyTeam();
      final teamId = team?.id;

      if (teamId != null) {
        await supabase.insertOrderWithTeam(order, deviceId: deviceId, teamId: teamId);
      } else {
        await supabase.insertOrder(order, deviceId: deviceId);
      }
    } catch (_) {
      // Silently fail, Supabase sync is best-effort
    }
  }
}
