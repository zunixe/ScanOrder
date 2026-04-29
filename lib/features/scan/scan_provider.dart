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

  Future<void> loadCounts() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    todayCount = await _db.getOrderCountByDate(today);
    totalCount = await _db.getTotalOrderCount();
    notifyListeners();
  }

  Future<ScanResult?> processScan(String rawCode, String? photoPath) async {
    if (_processing) return null;
    _processing = true;

    try {
      final resi = rawCode.trim();
      if (resi.isEmpty) return null;

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

      // Insert new
      final now = DateTime.now();
      final order = ScannedOrder(
        resi: resi,
        marketplace: marketplace,
        scannedAt: now,
        date: DateFormat('yyyy-MM-dd').format(now),
        photoPath: photoPath,
      );

      await _db.insertOrder(order);

      // Sync ke Supabase backend (async, tidak blocking)
      SupabaseService().insertOrder(order);

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
}
