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

  // Team context (set by AuthProvider, avoids repeated network calls)
  String? _teamId;
  String? _adminUserId;

  void setTeamContext(String? teamId, String? adminUserId) {
    _teamId = teamId;
    _adminUserId = adminUserId;
  }

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
    }
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_teamId != null) {
      // Team mode: query Supabase for real-time cross-device counts
      todayCount = await SupabaseService().getTeamTodayScans(_teamId!);
      totalCount = await SupabaseService().getTeamTotalScans(_teamId!);
      // Team members have unlimited quota
      scanLimit = -1;
      remainingScans = -1;
    } else {
      // Personal mode: query local DB
      todayCount = await _db.getOrderCountByDate(today, userId: userId);
      totalCount = await _db.getTotalOrderCount(userId: userId);
    }
    _savePhoto = await _quota.getSavePhoto();
    currentTier = await _quota.getTier();
    if (_teamId == null) {
      scanLimit = await _quota.getScanLimit();
      remainingScans = await _quota.getRemainingFreeScans();
    }
    debugPrint('[ScanProvider] loadCounts: userId=$userId, tier=$currentTier, scanLimit=$scanLimit, remaining=$remainingScans, todayCount=$todayCount, totalCount=$totalCount, teamId=$_teamId');
    // Load categories for Team tier or team member
    if (currentTier == StorageTier.unlimited || _teamId != null) {
      await loadCategories();
    }
    notifyListeners();
  }

  Future<void> loadCategories() async {
    final userId = SupabaseService().currentUser?.id;
    // Team mode: sync categories from Supabase first, then load from local
    if (_teamId != null) {
      await _syncTeamCategoriesFromSupabase();
      categories = await _db.getAllCategories(userId: userId, adminUserId: _adminUserId);
      // Use local DB counts (always accurate) + Supabase counts (cross-device) — take the max
      final localCounts = await _db.getCategoryCounts(userId: userId);
      final supStats = await SupabaseService().getTeamCategoryStats(_teamId!);
      categoryCounts = {};
      for (final cat in categories) {
        final local = localCounts[cat.id] ?? 0;
        final remote = supStats[cat.name] ?? 0;
        categoryCounts[cat.id!] = local > remote ? local : remote;
      }
    } else {
      categories = await _db.getAllCategories(userId: userId, adminUserId: _adminUserId);
      categoryCounts = await _db.getCategoryCounts(userId: userId);
    }
    debugPrint('[ScanProvider] loadCategories: ${categories.length} cats, teamId=$_teamId, adminUserId=$_adminUserId');
    notifyListeners();
  }

  /// Sync team categories from Supabase to local DB so they persist
  Future<void> _syncTeamCategoriesFromSupabase() async {
    final userId = SupabaseService().currentUser?.id;
    // Only pass adminUserId for team members (not admin themselves)
    final effectiveAdminId = (_adminUserId != null && _adminUserId != userId) ? _adminUserId : null;
    await SupabaseService().syncTeamCategoriesToLocal(adminUserId: effectiveAdminId);
    debugPrint('[ScanProvider] _syncTeamCategoriesFromSupabase: synced own + admin cats');
  }

  void setActiveCategory(int? id) {
    activeCategoryId = id;
    notifyListeners();
  }

  Future<void> addCategory(String name, String color) async {
    final userId = SupabaseService().currentUser?.id;
    final category = ScanCategory(name: name, color: color, userId: userId);
    final localId = await _db.insertCategory(category);
    categories = await _db.getAllCategories(userId: userId, adminUserId: _adminUserId);
    activeCategoryId = localId;
    // Sync to Supabase: query existing category by name+user_id first to get UUID
    Future.microtask(() async {
      final sup = SupabaseService();
      final client = sup.client;
      if (client != null && userId != null) {
        try {
          // Check if category already exists in Supabase
          final existing = await client
              .from('categories')
              .select('id')
              .eq('user_id', userId)
              .eq('name', name)
              .maybeSingle() as Map<String, dynamic>?;
          final uuid = existing?['id'];
          if (uuid != null) {
            // Update existing
            await client.from('categories').update({
              'name': name,
              'color': color,
            }).eq('id', uuid);
          } else {
            // Insert new (let Supabase generate UUID)
            await client.from('categories').insert({
              'user_id': userId,
              'name': name,
              'color': color,
            });
          }
          debugPrint('[ScanProvider] addCategory synced to Supabase: name=$name, uuid=$uuid');
        } catch (e) {
          debugPrint('[ScanProvider] addCategory sync error: $e');
        }
      }
    });
    notifyListeners();
  }

  Future<void> deleteCategory(int id) async {
    await _db.deleteCategory(id);
    if (activeCategoryId == id) activeCategoryId = null;
    final userId = SupabaseService().currentUser?.id;
    categories = await _db.getAllCategories(userId: userId, adminUserId: _adminUserId);
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
    categories = await _db.getAllCategories(userId: userId, adminUserId: _adminUserId);
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

      debugPrint('[ScanProvider] processScan start: resi=$resi, teamId(arg)=$teamId, _teamId=$_teamId, tier=$currentTier, activeCategoryId=$activeCategoryId, localCategories=${categories.length}');

      // Team mode: wajib pilih kategori sebelum scan (selalu, agar tidak ada scan tanpa kategori)
      if ((_teamId != null || currentTier == StorageTier.unlimited) && activeCategoryId == null) {
        debugPrint('[ScanProvider] blocked: no active category selected in team mode');
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
      // In team mode, scans belong to admin — use admin's user_id for ownership
      final scanOwnerId = _teamId != null && _adminUserId != null ? _adminUserId! : userId!;
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
        // Team mode: also check Supabase for duplicates in same category
        if (teamId != null) {
          final teamDuplicate = await _checkTeamDuplicate(resi, activeCategoryId);
          if (teamDuplicate) {
            SoundService().playScanDuplicate();
            lastResult = ScanResult(
              status: ScanStatus.duplicate,
              resi: resi,
              marketplace: marketplace,
            );
            notifyListeners();
            return lastResult;
          }
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
        // Team mode: also check Supabase for global duplicates
        if (teamId != null) {
          final teamDuplicate = await _checkTeamDuplicate(resi, null);
          if (teamDuplicate) {
            SoundService().playScanDuplicate();
            lastResult = ScanResult(
              status: ScanStatus.duplicate,
              resi: resi,
              marketplace: marketplace,
            );
            notifyListeners();
            return lastResult;
          }
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
        final existingOrder = await _db.findByResi(resi, userId: scanOwnerId);
        if (existingOrder != null) {
          orderId = existingOrder.id!;
        } else {
          orderId = await _db.insertOrder(order, userId: scanOwnerId, teamId: teamId);
        }
        // Assign ke kategori aktif (UNIQUE order_id, category_id mencegah duplikat dalam kategori)
        final ocId = await _db.assignCategoryToOrder(orderId, activeCategoryId!);
        debugPrint('[ScanProvider] assigned local category: ocId=$ocId, orderId=$orderId, categoryId=$activeCategoryId');
        // Sync category assignment to Supabase via queue (reliable, with retry)
        // Don't use Future.microtask — race condition with insertOrder
      } else {
        orderId = await _db.insertOrder(order, userId: scanOwnerId, teamId: teamId);
      }
      // Jangan kurangi quota pribadi jika user anggota tim (tim = unlimited)
      if (teamId == null) await _quota.consumeScan();

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
      // Reset processing early so next scan isn't blocked
      _processing = false;
      notifyListeners();

      // Non-critical background: sync counts & quota
      if (_teamId != null) {
        todayCount = await SupabaseService().getTeamTodayScans(_teamId!);
        totalCount = await SupabaseService().getTeamTotalScans(_teamId!);
      } else {
        remainingScans = await _quota.getRemainingFreeScans();
      }
      notifyListeners();

      // Sync ke Supabase via queue (background)
      final queue = SyncQueue();
      final user = SupabaseService().currentUser;
      if (user != null) {
        // Enqueue photo upload if needed
        if (photoPath != null) {
          queue.enqueue(SyncTaskType.uploadPhoto, {
            'local_path': photoPath,
            'user_id': scanOwnerId,
            'resi': resi,
            'cloud_filename': '$scanOwnerId/${DateTime.now().millisecondsSinceEpoch}.jpg',
          });
        }
        // Enqueue order insert (photo_url will be updated after upload)
        queue.enqueue(SyncTaskType.insertOrder, {
          'device_id': 'pending', // will be resolved by queue
          'user_id': scanOwnerId,
          'resi': resi,
          'marketplace': marketplace,
          'scanned_at': now.millisecondsSinceEpoch.toString(),
          'date': DateFormat('yyyy-MM-dd').format(now),
          'photo_url': photoPath, // local path, will be updated after upload
          'team_id': teamId,
          'category_id': activeCategoryId,
        });
        debugPrint('[ScanProvider] enqueued insertOrder for resi=$resi, teamId=$teamId');
        // Enqueue order-category relation after insertOrder; processor will retry until scan exists
        if (activeCategoryId != null) {
          queue.enqueue(SyncTaskType.insertOrderCategory, {
            'resi': resi,
            'category_id': activeCategoryId,
          });
          debugPrint('[ScanProvider] enqueued insertOrderCategory for resi=$resi, categoryId=$activeCategoryId');
        }
        // Note: subscription sync is handled by consumeScan() → syncToCloud()
        // Do NOT enqueue syncSubscription here with placeholder data,
        // it would overwrite the real tier in Supabase with 'pending'.
      }

      return lastResult;
    } catch (e) {
      debugPrint('[ScanProvider] error: $e');
      return null;
    } finally {
      _processing = false;
    }
  }

  void clearResult() {
    lastResult = null;
    notifyListeners();
  }

  /// Check if resi already exists in team scans on Supabase
  /// If categoryId is provided, only check within that category
  Future<bool> _checkTeamDuplicate(String resi, int? categoryId) async {
    try {
      final client = SupabaseService().client;
      if (client == null || _teamId == null) return false;

      // Check if resi exists in team scans
      final scans = await client
          .from('scans')
          .select('id')
          .eq('team_id', _teamId!)
          .eq('resi', resi)
          .limit(1);

      if (scans.isEmpty) return false;

      // If no category filter, any match is a duplicate
      if (categoryId == null) return true;

      // If category filter, check if this scan is in the same category
      // Resolve local category to Supabase UUID by name + userId
      final cat = await _db.getCategoryById(categoryId);
      if (cat == null) return false;

      final catRows = await client
          .from('categories')
          .select('id')
          .eq('name', cat.name)
          .eq('user_id', cat.userId ?? '')
          .limit(1);
      if (catRows.isEmpty) return false;

      final catUuid = catRows.first['id'];
      final scanId = scans.first['id'];
      final scRows = await client
          .from('scan_categories')
          .select('id')
          .eq('scan_id', scanId)
          .eq('category_id', catUuid)
          .limit(1);

      return scRows.isNotEmpty;
    } catch (e) {
      debugPrint('[ScanProvider] _checkTeamDuplicate error: $e');
      return false;
    }
  }
}
