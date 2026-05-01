import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import '../../core/db/database_helper.dart';
import '../../core/supabase/supabase_service.dart';
import '../../models/order.dart';
import '../../models/category.dart';
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
  int remainingScans = 0;
  int scanLimit = 0;
  StorageTier currentTier = StorageTier.free;
  bool _processing = false;
  bool _savePhoto = true;

  // Category support (Team tier only)
  List<ScanCategory> categories = [];
  int? activeCategoryId;

  bool get savePhoto => _savePhoto;
  String get quotaDisplay {
    if (scanLimit < 0) return '∞';
    return '$remainingScans/$scanLimit';
  }
  ScanCategory? get activeCategory {
    if (activeCategoryId == null) return null;
    return categories.where((c) => c.id == activeCategoryId).firstOrNull;
  }

  Future<void> loadCounts() async {
    final userId = SupabaseService().currentUser?.id;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    todayCount = await _db.getOrderCountByDate(today);
    totalCount = await _db.getTotalOrderCount(userId: userId);
    _savePhoto = await _quota.getSavePhoto();
    currentTier = await _quota.getTier();
    scanLimit = await _quota.getScanLimit();
    remainingScans = await _quota.getRemainingFreeScans();
    // Load categories for Team tier
    if (currentTier == StorageTier.unlimited) {
      categories = await _db.getAllCategories(userId: userId);
    }
    notifyListeners();
  }

  Future<void> loadCategories() async {
    final userId = SupabaseService().currentUser?.id;
    categories = await _db.getAllCategories(userId: userId);
    notifyListeners();
  }

  void setActiveCategory(int? id) {
    activeCategoryId = id;
    notifyListeners();
  }

  Future<void> addCategory(String name, String color) async {
    final userId = SupabaseService().currentUser?.id;
    final category = ScanCategory(name: name, color: color, userId: userId);
    final id = await _db.insertCategory(category);
    categories = await _db.getAllCategories(userId: userId);
    activeCategoryId = id;
    // Sync to Supabase
    Future.microtask(() => SupabaseService().upsertCategory(id, name, color));
    notifyListeners();
  }

  Future<void> deleteCategory(int id) async {
    await _db.deleteCategory(id);
    if (activeCategoryId == id) activeCategoryId = null;
    final userId = SupabaseService().currentUser?.id;
    categories = await _db.getAllCategories(userId: userId);
    // Sync delete to Supabase
    Future.microtask(() => SupabaseService().deleteCategory(id));
    notifyListeners();
  }

  Future<void> renameCategory(int id, String newName) async {
    final userId = SupabaseService().currentUser?.id;
    final cat = categories.where((c) => c.id == id).firstOrNull;
    if (cat == null) return;
    final updated = cat.copyWith(name: newName);
    await _db.updateCategory(updated);
    categories = await _db.getAllCategories(userId: userId);
    // Sync to Supabase
    Future.microtask(() => SupabaseService().upsertCategory(id, newName, cat.color));
    notifyListeners();
  }

  Future<void> setSavePhoto(bool value) async {
    _savePhoto = value;
    await _quota.setSavePhoto(value);
    notifyListeners();
  }

  Future<ScanResult?> processScan(String rawCode, String? photoPath, {String? teamId}) async {
    if (_processing) return null;
    _processing = true;

    try {
      final resi = rawCode.trim();
      if (resi.isEmpty) return null;

      // Filter: hanya terima nomor resi, tolak Order ID dll
      if (!MarketplaceDetector.isValidResi(resi)) return null;

      final marketplace = MarketplaceDetector.detect(resi);

      // Check duplicate (indexed query — fast)
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

      // Check quota (skip jika user adalah anggota tim — tim = unlimited)
      if (teamId == null && !await _quota.canScan()) {
        lastResult = ScanResult(
          status: ScanStatus.quotaExceeded,
          resi: resi,
          marketplace: marketplace,
        );
        notifyListeners();
        return lastResult;
      }

      // Insert new order with photo
      final now = DateTime.now();
      final order = ScannedOrder(
        resi: resi,
        marketplace: marketplace,
        scannedAt: now,
        date: DateFormat('yyyy-MM-dd').format(now),
        photoPath: photoPath,
      );

      final userId = SupabaseService().currentUser?.id;
      final orderId = await _db.insertOrder(order, userId: userId);
      // Assign category if active (Team tier)
      if (activeCategoryId != null) {
        final ocId = await _db.assignCategoryToOrder(orderId, activeCategoryId!);
        // Sync category assignment to Supabase
        Future.microtask(() => SupabaseService().assignOrderCategory(ocId, orderId, activeCategoryId!));
      }
      // Jangan kurangi quota pribadi jika user anggota tim (tim = unlimited)
      if (teamId == null) await _quota.consumeScan();
      remainingScans = await _quota.getRemainingFreeScans();

      // Sync ke Supabase backend (fire-and-forget, tidak blocking)
      Future.microtask(() => _syncToSupabase(order, teamId: teamId));

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
  void _syncToSupabase(ScannedOrder order, {String? teamId}) async {
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

      // Gunakan teamId dari parameter (sudah diketahui di processScan)
      final resolvedTeamId = teamId ?? (await supabase.getMyTeam())?.id;

      if (resolvedTeamId != null) {
        await supabase.insertOrderWithTeam(order, deviceId: deviceId, teamId: resolvedTeamId);
      } else {
        await supabase.insertOrder(order, deviceId: deviceId);
      }
    } catch (_) {
      // Silently fail, Supabase sync is best-effort
    }
  }
}
