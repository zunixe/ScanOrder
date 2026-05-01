import 'package:flutter/foundation.dart';
import '../../core/db/database_helper.dart';
import '../../core/supabase/supabase_service.dart';
import '../../models/order.dart';
import '../../models/category.dart';
import '../../services/marketplace_detector.dart';
import '../../services/quota_service.dart';
import '../../services/sync_queue.dart';
import '../../services/sound_service.dart';
import 'package:intl/intl.dart';

enum ScanStatus { idle, success, duplicate, recentRepeat, quotaExceeded, noCategory }

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
  final Map<String, DateTime> _recentScans = {};
  static const Duration _recentRepeatWindow = Duration(seconds: 5);

  // Category support (Team tier only)
  List<ScanCategory> categories = [];
  int? activeCategoryId;
  Map<int, int> categoryCounts = {}; // categoryId -> order count

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
    // Migrate old non-user-scoped keys to user-scoped keys, then sync from cloud
    if (userId != null) {
      await _quota.migrateToUserScopedKeys();
      await _quota.syncFromCloud();
      // Sync local state back to cloud to fix any corrupted cloud data
      await _quota.syncToCloud();
    }
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    todayCount = await _db.getOrderCountByDate(today, userId: userId);
    totalCount = await _db.getTotalOrderCount(userId: userId);
    _savePhoto = await _quota.getSavePhoto();
    currentTier = await _quota.getTier();
    scanLimit = await _quota.getScanLimit();
    remainingScans = await _quota.getRemainingFreeScans();
    debugPrint('[ScanProvider] loadCounts: userId=$userId, tier=$currentTier, scanLimit=$scanLimit, remaining=$remainingScans, todayCount=$todayCount, totalCount=$totalCount');
    // Load categories for Team tier
    if (currentTier == StorageTier.unlimited) {
      categories = await _db.getAllCategories(userId: userId);
      categoryCounts = await _db.getCategoryCounts(userId: userId);
    }
    notifyListeners();
  }

  Future<void> loadCategories() async {
    final userId = SupabaseService().currentUser?.id;
    categories = await _db.getAllCategories(userId: userId);
    categoryCounts = await _db.getCategoryCounts(userId: userId);
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

      // Team tier: wajib pilih kategori dulu sebelum scan
      if (currentTier == StorageTier.unlimited && activeCategoryId == null) {
        lastResult = ScanResult(
          status: ScanStatus.noCategory,
          resi: resi,
          marketplace: '',
        );
        notifyListeners();
        return lastResult;
      }

      // Filter: hanya terima nomor resi, tolak Order ID dll
      if (!MarketplaceDetector.isValidResi(resi)) return null;

      final marketplace = MarketplaceDetector.detect(resi);

      final recentAt = _recentScans[resi];
      final now = DateTime.now();
      if (recentAt != null && now.difference(recentAt) < _recentRepeatWindow) {
        lastResult = ScanResult(
          status: ScanStatus.recentRepeat,
          resi: resi,
          marketplace: marketplace,
        );
        notifyListeners();
        return lastResult;
      }

      // Check duplicate: scoped per category if active, else per user
      final userId = SupabaseService().currentUser?.id;
      if (activeCategoryId != null) {
        // Dalam kategori: cek duplikat hanya di kategori itu
        final alreadyInCategory = await _db.isOrderInCategory(resi, activeCategoryId!, userId: userId);
        if (alreadyInCategory) {
          SoundService().playScanDuplicate();
          lastResult = ScanResult(
            status: ScanStatus.duplicate,
            resi: resi,
            marketplace: marketplace,
          );
          notifyListeners();
          return lastResult;
        }
      } else {
        // Tanpa kategori: cek duplikat global per user
        final existing = await _db.findByResi(resi, userId: userId);
        if (existing != null) {
          SoundService().playScanDuplicate();
          lastResult = ScanResult(
            status: ScanStatus.duplicate,
            resi: resi,
            marketplace: marketplace,
            existingOrder: existing,
          );
          notifyListeners();
          return lastResult;
        }
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
      final order = ScannedOrder(
        resi: resi,
        marketplace: marketplace,
        scannedAt: now,
        date: DateFormat('yyyy-MM-dd').format(now),
        photoPath: photoPath,
      );

      // Jika kategori aktif, cek apakah order sudah ada di tabel orders (boleh sama resi di kategori lain)
      // Jika belum ada di orders, insert dulu; jika sudah ada, reuse order_id-nya
      int orderId;
      if (activeCategoryId != null) {
        final existingOrder = await _db.findByResi(resi, userId: userId);
        if (existingOrder != null) {
          orderId = existingOrder.id!;
        } else {
          orderId = await _db.insertOrder(order, userId: userId);
        }
        // Assign ke kategori aktif (UNIQUE order_id, category_id mencegah duplikat dalam kategori)
        final ocId = await _db.assignCategoryToOrder(orderId, activeCategoryId!);
        // Sync category assignment to Supabase
        Future.microtask(() => SupabaseService().assignOrderCategory(ocId, orderId, activeCategoryId!));
      } else {
        orderId = await _db.insertOrder(order, userId: userId);
      }
      // Jangan kurangi quota pribadi jika user anggota tim (tim = unlimited)
      if (teamId == null) await _quota.consumeScan();
      remainingScans = await _quota.getRemainingFreeScans();

      // Sync ke Supabase via queue (reliable, retry, rate-limited)
      final queue = SyncQueue();
      final user = SupabaseService().currentUser;
      if (user != null) {
        // Enqueue photo upload if needed
        if (photoPath != null) {
          queue.enqueue(SyncTaskType.uploadPhoto, {
            'local_path': photoPath,
            'user_id': user.id,
            'resi': resi,
            'cloud_filename': '${user.id}/${DateTime.now().millisecondsSinceEpoch}.jpg',
          });
        }
        // Enqueue order insert (photo_url will be updated after upload)
        queue.enqueue(SyncTaskType.insertOrder, {
          'device_id': 'pending', // will be resolved by queue
          'user_id': user.id,
          'resi': resi,
          'marketplace': marketplace,
          'scanned_at': now.millisecondsSinceEpoch.toString(),
          'date': DateFormat('yyyy-MM-dd').format(now),
          'photo_url': photoPath, // local path, will be updated after upload
          'team_id': teamId,
        });
        // Note: subscription sync is handled by consumeScan() → syncToCloud()
        // Do NOT enqueue syncSubscription here with placeholder data,
        // it would overwrite the real tier in Supabase with 'pending'.
      }

      todayCount++;
      totalCount++;
      _recentScans[resi] = now;

      // Update category count jika kategori aktif
      if (activeCategoryId != null) {
        categoryCounts[activeCategoryId!] = (categoryCounts[activeCategoryId!] ?? 0) + 1;
      }

      SoundService().playScanSuccess();
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
