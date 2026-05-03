import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/db/database_helper.dart';
import '../core/supabase/supabase_service.dart';
import 'sync_queue.dart';

enum StorageTier { free, basic, pro, unlimited }

class PackageInfo {
  final String id;
  final String name;
  final int price;
  final int scanLimit; // 0 = unlimited
  final int maxMembers;
  final List<String> features;
  final bool isPopular;

  const PackageInfo({
    required this.id,
    required this.name,
    required this.price,
    required this.scanLimit,
    required this.maxMembers,
    required this.features,
    required this.isPopular,
  });

  String get priceDisplay {
    if (price == 0) return 'Gratis';
    return 'Rp ${price.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')}';
  }

  String get scanLimitDisplay {
    if (scanLimit == 0) return '∞';
    if (scanLimit >= 1000) return '${scanLimit ~/ 1000}rb';
    return '$scanLimit';
  }
}

class QuotaService {
  // Scan limits per tier (per bulan)
  static const int _freeScans = 100;
  static const int _basicScans = 1000;
  static const int _proScans = 5000;

  // Harga per tier (IDR)
  static const int _basicPrice = 29000;
  static const int _proPrice = 99000;
  static const int _teamPrice = 399000;

  // Storage limits per tier (bytes) - untuk info foto saja
  static const int _freeLimit = 100 * 1024 * 1024;       // 100MB
  static const int _basicLimit = 2 * 1024 * 1024 * 1024; // 2GB
  static const int _proLimit = 10 * 1024 * 1024 * 1024;  // 10GB

  // Hardcoded fallback packages (dipakai jika DB tidak bisa diakses)
  static const List<PackageInfo> _fallbackPackages = [
    PackageInfo(id: 'free',      name: 'Free',  price: 0,      scanLimit: 100,  maxMembers: 1,  features: ['Scan resi barcode','100 scan/bulan','Copy resi cepat'], isPopular: false),
    PackageInfo(id: 'basic',     name: 'Basic', price: 29000,  scanLimit: 1000, maxMembers: 1,  features: ['1.000 scan/bulan','Gabung tim via kode invite','Backup & sync cloud','Export XLSX/CSV','Copy resi cepat','Foto bukti scan'], isPopular: false),
    PackageInfo(id: 'pro',       name: 'Pro',   price: 99000,  scanLimit: 5000, maxMembers: 1,  features: ['5.000 scan/bulan','Gabung tim via kode invite','Backup & sync cloud','Export XLSX/CSV','Foto bukti scan','Copy resi cepat','Statistik lengkap'], isPopular: true),
    PackageInfo(id: 'unlimited', name: 'Team',  price: 399000, scanLimit: 0,    maxMembers: 10, features: ['Unlimited scan/bulan','Buat & kelola tim','Hingga 10 anggota tim','Kategori wajib per scan','Backup & sync cloud','Export XLSX/CSV','Foto bukti scan','Statistik lengkap','Copy resi cepat','Dukungan prioritas'], isPopular: false),
  ];

  List<PackageInfo> _packages = [];
  List<PackageInfo> get packages => _packages.isEmpty ? _fallbackPackages : _packages;


  final DatabaseHelper _db = DatabaseHelper.instance;
  final SupabaseService _supabase = SupabaseService();
  static const String _tierKey = 'storage_tier';
  static const String _cycleStartKey = 'subscription_cycle_start_ms';
  static const String _cycleEndKey = 'subscription_cycle_end_ms';
  static const String _cycleAllowanceKey = 'subscription_cycle_allowance';
  static const String _cycleUsedKey = 'subscription_cycle_used';
  static const String _savePhotoKey = 'save_photo';
  static const int _cycleDays = 30;

  /// Prefix key dengan user_id agar data quota terpisah per user
  String _userKey(String baseKey) {
    final userId = _supabase.currentUser?.id ?? 'anon';
    return '${baseKey}_$userId';
  }

  /// Migrasi data dari key lama (tanpa user_id) ke key baru (dengan suffix user_id).
  /// Dipanggil sekali saat user login setelah upgrade ke user-scoped keys.
  Future<void> migrateToUserScopedKeys() async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    final migratedKey = '_migrated_$userId';
    if (prefs.getBool(migratedKey) == true) return; // sudah pernah migrasi

    // Copy semua key lama ke key baru (hanya jika key baru belum ada)
    final keysToMigrate = [
      _tierKey, _cycleStartKey, _cycleEndKey,
      _cycleAllowanceKey, _cycleUsedKey, _savePhotoKey,
    ];
    for (final key in keysToMigrate) {
      final newKey = _userKey(key);
      if (prefs.containsKey(newKey)) continue; // sudah ada, skip
      if (!prefs.containsKey(key)) continue;   // key lama tidak ada, skip

      final value = prefs.get(key);
      if (value is int) {
        await prefs.setInt(newKey, value);
      } else if (value is String) {
        await prefs.setString(newKey, value);
      } else if (value is bool) {
        await prefs.setBool(newKey, value);
      } else if (value is double) {
        await prefs.setDouble(newKey, value);
      }
    }

    await prefs.setBool(migratedKey, true);
  }

  int _defaultAllowanceForTier(StorageTier tier) {
    // Coba ambil dari packages dulu
    final pkg = packages.where((p) => p.id == tier.name).firstOrNull;
    if (pkg != null) {
      return pkg.scanLimit == 0 ? -1 : pkg.scanLimit;
    }
    // Fallback ke hardcoded
    switch (tier) {
      case StorageTier.free:
        return _freeScans;
      case StorageTier.basic:
        return _basicScans;
      case StorageTier.pro:
        return _proScans;
      case StorageTier.unlimited:
        return -1;
    }
  }

  /// Load packages dari Supabase. Dipanggil saat app start.
  /// Jika gagal, tetap pakai hardcoded fallback.
  Future<void> loadPackages() async {
    try {
      final rows = await _supabase.fetchPackages();
      if (rows.isNotEmpty) {
        _packages = rows.map((row) => PackageInfo(
          id: row['id'] as String? ?? '',
          name: row['name'] as String? ?? '',
          price: (row['price'] as num?)?.toInt() ?? 0,
          scanLimit: (row['scan_limit'] as num?)?.toInt() ?? 0,
          maxMembers: (row['max_members'] as num?)?.toInt() ?? 1,
          features: (row['features'] as List?)?.map((e) => e.toString()).toList() ?? [],
          isPopular: row['is_popular'] as bool? ?? false,
        )).toList();
        debugPrint('[QuotaService] Loaded ${_packages.length} packages from DB');
      }
    } catch (e) {
      debugPrint('[QuotaService] Failed to load packages from DB: $e');
    }
  }

  Future<void> _ensureCycleInitialized() async {
    final prefs = await SharedPreferences.getInstance();
    final startMs = prefs.getInt(_userKey(_cycleStartKey));
    final endMs = prefs.getInt(_userKey(_cycleEndKey));
    final allowance = prefs.getInt(_userKey(_cycleAllowanceKey));
    // Re-init jika data belum lengkap ATAU allowance=0 (korup dari sync pending)
    // allowance=-1 (unlimited) dan >0 (valid) dianggap sudah ter-init
    if (startMs != null && endMs != null && allowance != null && allowance != 0) return;

    final now = DateTime.now();
    final tier = await getTier();
    await prefs.setInt(_userKey(_cycleStartKey), now.millisecondsSinceEpoch);
    await prefs.setInt(_userKey(_cycleEndKey), now.add(const Duration(days: _cycleDays)).millisecondsSinceEpoch);
    await prefs.setInt(_userKey(_cycleAllowanceKey), _defaultAllowanceForTier(tier));
    await prefs.setInt(_userKey(_cycleUsedKey), 0);
  }

  Future<void> _autoRollFreeCycleIfNeeded() async {
    await _ensureCycleInitialized();
    final tier = await getTier();
    // Only roll for free-tier users or expired subscription users
    if (tier != StorageTier.free) {
      // Check expiry without calling isSubscriptionActive (avoids infinite recursion)
      final prefs = await SharedPreferences.getInstance();
      final endMs = prefs.getInt(_userKey(_cycleEndKey));
      if (endMs != null && DateTime.now().millisecondsSinceEpoch < endMs) return;
    }

    final prefs = await SharedPreferences.getInstance();
    final startMs = prefs.getInt(_userKey(_cycleStartKey)) ?? 0;
    final now = DateTime.now();

    // Free cycle refreshes on the 1st of each month
    final cycleStart = DateTime.fromMillisecondsSinceEpoch(startMs);
    final needsRoll = now.year > cycleStart.year ||
        (now.year == cycleStart.year && now.month > cycleStart.month);

    if (!needsRoll) return;

    // Reset on 1st of current month
    final newStart = DateTime(now.year, now.month, 1);
    final newEnd = DateTime(now.year, now.month + 1, 1);
    await prefs.setInt(_userKey(_cycleStartKey), newStart.millisecondsSinceEpoch);
    await prefs.setInt(_userKey(_cycleEndKey), newEnd.millisecondsSinceEpoch);
    await prefs.setInt(_userKey(_cycleAllowanceKey), _freeScans);
    await prefs.setInt(_userKey(_cycleUsedKey), 0);
  }

  Future<bool> canScan() async {
    await _autoRollFreeCycleIfNeeded();
    final tier = await getTier();
    final active = await isSubscriptionActive();

    // If subscription expired, fall back to free quota (100/month)
    if (tier != StorageTier.free && !active) {
      // Allow scanning with free-tier quota as fallback
      final freeAllowance = _freeScans;
      final used = await getUsedInCurrentCycle();
      return used < freeAllowance;
    }

    final allowance = await getCycleAllowance();
    final used = await getUsedInCurrentCycle();
    if (allowance < 0) return true;
    return used < allowance;
  }

  Future<void> consumeScan() async {
    await _ensureCycleInitialized();
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt(_userKey(_cycleUsedKey)) ?? 0;
    await prefs.setInt(_userKey(_cycleUsedKey), used + 1);
    await syncToCloud();
  }

  Future<bool> isSubscriptionActive() async {
    final tier = await getTier();
    if (tier == StorageTier.free) return true;
    final end = await getActiveUntil();
    if (end == null) return false;
    return DateTime.now().isBefore(end);
  }

  Future<DateTime?> getActiveFrom() async {
    await _ensureCycleInitialized();
    final prefs = await SharedPreferences.getInstance();
    final startMs = prefs.getInt(_userKey(_cycleStartKey));
    if (startMs == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(startMs);
  }

  Future<DateTime?> getActiveUntil() async {
    await _ensureCycleInitialized();
    final prefs = await SharedPreferences.getInstance();
    final endMs = prefs.getInt(_userKey(_cycleEndKey));
    if (endMs == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(endMs);
  }

  Future<int> getCycleAllowance() async {
    await _ensureCycleInitialized();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userKey(_cycleAllowanceKey)) ?? _freeScans;
  }

  Future<int> getUsedInCurrentCycle() async {
    await _ensureCycleInitialized();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userKey(_cycleUsedKey)) ?? 0;
  }

  Future<bool> canStorePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_userKey(_savePhotoKey)) ?? true;
  }

  Future<bool> getSavePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_userKey(_savePhotoKey)) ?? true;
  }

  Future<void> setSavePhoto(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_userKey(_savePhotoKey), value);
  }

  Future<StorageTier> getTier() async {
    final prefs = await SharedPreferences.getInstance();
    final tier = prefs.getString(_userKey(_tierKey)) ?? 'free';
    switch (tier) {
      case 'basic': return StorageTier.basic;
      case 'pro': return StorageTier.pro;
      case 'unlimited': return StorageTier.unlimited;
      case 'pending':
        // 'pending' bukan tier valid — bersihkan semua data cycle yang korup
        await prefs.remove(_userKey(_tierKey));
        await prefs.remove(_userKey(_cycleAllowanceKey));
        await prefs.remove(_userKey(_cycleUsedKey));
        await prefs.remove(_userKey(_cycleStartKey));
        await prefs.remove(_userKey(_cycleEndKey));
        return StorageTier.free;
      default: return StorageTier.free;
    }
  }

  Future<int> getLimit() async {
    final tier = await getTier();
    switch (tier) {
      case StorageTier.free: return _freeLimit;
      case StorageTier.basic: return _basicLimit;
      case StorageTier.pro: return _proLimit;
      case StorageTier.unlimited: return -1; // unlimited
    }
  }

  Future<int> getUsedBytes() async {
    final userId = _supabase.currentUser?.id;
    final scans = await _db.getAllScans(userId: userId);
    int total = 0;
    for (final order in scans) {
      final path = order.photoPath;
      if (path != null) {
        try {
          final file = File(path);
          if (file.existsSync()) total += file.lengthSync();
        } catch (_) {}
      }
    }
    return total;
  }

  Future<int> getRemainingBytes() async {
    final used = await getUsedBytes();
    final limit = await getLimit();
    if (limit < 0) return -1; // unlimited
    return limit - used;
  }

  Future<int> getTotalScanned() async {
    final userId = _supabase.currentUser?.id;
    return await _db.getTotalOrderCount(userId: userId);
  }

  Future<int> getRemainingFreeScans() async {
    final tier = await getTier();
    final active = await isSubscriptionActive();
    // If subscription expired, use free quota as limit
    if (tier != StorageTier.free && !active) {
      final used = await getUsedInCurrentCycle();
      return (_freeScans - used).clamp(0, _freeScans);
    }
    final allowance = await getCycleAllowance();
    final used = await getUsedInCurrentCycle();
    if (allowance < 0) return -1;
    return (allowance - used).clamp(0, allowance);
  }

  Future<int> getScanLimit() async {
    final tier = await getTier();
    final active = await isSubscriptionActive();
    if (tier != StorageTier.free && !active) return _freeScans;
    return getCycleAllowance();
  }

  String getScanLimitDisplay(StorageTier tier) {
    // Coba ambil dari packages dulu
    final pkg = packages.where((p) => p.id == tier.name).firstOrNull;
    if (pkg != null) return pkg.scanLimitDisplay;
    // Fallback
    switch (tier) {
      case StorageTier.free: return '$_freeScans';
      case StorageTier.basic: return '$_basicScans';
      case StorageTier.pro: return '${_proScans ~/ 1000}rb';
      case StorageTier.unlimited: return '∞';
    }
  }

  String getTierName(StorageTier tier) {
    // Coba ambil dari packages dulu
    final pkg = packages.where((p) => p.id == tier.name).firstOrNull;
    if (pkg != null) return pkg.name;
    // Fallback
    switch (tier) {
      case StorageTier.free: return 'Gratis';
      case StorageTier.basic: return 'Basic';
      case StorageTier.pro: return 'Pro';
      case StorageTier.unlimited: return 'Team';
    }
  }

  int getPriceForTier(StorageTier tier) {
    // Coba ambil dari packages dulu
    final pkg = packages.where((p) => p.id == tier.name).firstOrNull;
    if (pkg != null) return pkg.price;
    // Fallback ke hardcoded
    switch (tier) {
      case StorageTier.free: return 0;
      case StorageTier.basic: return _basicPrice;
      case StorageTier.pro: return _proPrice;
      case StorageTier.unlimited: return _teamPrice;
    }
  }

  String getPriceDisplay(StorageTier tier) {
    final price = getPriceForTier(tier);
    if (price == 0) return 'Gratis';
    return 'Rp ${price.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')}';
  }

  Future<bool> isPro() async {
    final tier = await getTier();
    if (tier.index < StorageTier.basic.index) return false;
    return isSubscriptionActive();
  }

  Future<void> setTier(StorageTier tier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey(_tierKey), tier.name);
    await _ensureCycleInitialized();
    await syncToCloud();
  }

  Future<void> purchaseOrChangeTier(StorageTier newTier, {bool carryOver = true}) async {
    await _ensureCycleInitialized();
    final prefs = await SharedPreferences.getInstance();
    final oldTier = await getTier();
    final wasActive = await isSubscriptionActive();
    final oldAllowance = await getCycleAllowance();
    final oldUsed = await getUsedInCurrentCycle();
    final oldRemaining = oldAllowance < 0 ? 0 : (oldAllowance - oldUsed).clamp(0, oldAllowance);
    final now = DateTime.now();
    final newBase = _defaultAllowanceForTier(newTier);
    int newAllowance;

    // Hitung sisa hari periode lama
    final oldEndMs = prefs.getInt(_userKey(_cycleEndKey)) ?? 0;
    final remainingDays = oldEndMs > now.millisecondsSinceEpoch
        ? ((oldEndMs - now.millisecondsSinceEpoch) / (1000 * 60 * 60 * 24)).ceil()
        : 0;

    if (newBase < 0) {
      newAllowance = -1; // Unlimited
    } else if (carryOver && wasActive && oldTier != StorageTier.free && newTier.index > oldTier.index && oldRemaining > 0) {
      // Upgrade: carry-over sisa quota lama
      newAllowance = newBase + oldRemaining;
    } else {
      newAllowance = newBase; // Reset ke batas tier
    }

    // Hitung periode baru: 30 hari + sisa hari dari periode lama (jika upgrade & carry-over)
    final extraDays = (carryOver && wasActive && oldTier != StorageTier.free && newTier.index > oldTier.index && remainingDays > 0)
        ? remainingDays
        : 0;

    await prefs.setString(_userKey(_tierKey), newTier.name);
    await prefs.setInt(_userKey(_cycleStartKey), now.millisecondsSinceEpoch);
    await prefs.setInt(_userKey(_cycleEndKey), now.add(Duration(days: _cycleDays + extraDays)).millisecondsSinceEpoch);
    await prefs.setInt(_userKey(_cycleAllowanceKey), newAllowance);
    await prefs.setInt(_userKey(_cycleUsedKey), 0);
    await syncToCloud();
  }

  Future<void> setPro(bool value) async {
    await purchaseOrChangeTier(value ? StorageTier.pro : StorageTier.free);
  }

  Future<void> syncFromCloud() async {
    if (_supabase.currentUser == null) return;
    final user = _supabase.currentUser;
    final cloud = await _supabase.fetchMySubscription();

    // Jika tidak ada subscription by user_id, coba fetch by email (untuk Google login link)
    if (cloud == null && user?.email != null) {
      debugPrint('[QuotaService] No subscription by user_id, trying email...');
      final cloudByEmail = await _supabase.fetchSubscriptionByEmail(user!.email!);
      if (cloudByEmail != null) {
        // Copy subscription ke user_id baru dan update email
        await _supabase.upsertMySubscription({
          'tier': cloudByEmail['tier'],
          'active_from': cloudByEmail['active_from'],
          'active_until': cloudByEmail['active_until'],
          'cycle_allowance': cloudByEmail['cycle_allowance'],
          'cycle_used': cloudByEmail['cycle_used'],
        });
        debugPrint('[QuotaService] Subscription copied from email to new user_id');
        // Fetch lagi sekarang sudah ada
        return syncFromCloud();
      }
      debugPrint('[QuotaService] No subscription found in cloud for user ${user.id}');
      // Cloud tidak punya data → pastikan cycle lokal ter-init dengan benar
      await _ensureCycleInitialized();
      return;
    }
    if (cloud == null) {
      debugPrint('[QuotaService] No subscription in cloud, initializing local cycle');
      await _ensureCycleInitialized();
      return;
    }

    debugPrint('[QuotaService] Cloud subscription: tier=${cloud['tier']}, allowance=${cloud['cycle_allowance']}, used=${cloud['cycle_used']}');

    final prefs = await SharedPreferences.getInstance();
    final cloudTierStr = (cloud['tier'] as String?) ?? 'free';

    // Abaikan tier 'pending' — subscription belum aktif, jangan timpa data lokal
    if (cloudTierStr == 'pending') {
      debugPrint('[QuotaService] Cloud tier is pending, skipping sync');
      await _ensureCycleInitialized();
      return;
    }

    final localTierStr = prefs.getString(_userKey(_tierKey)) ?? 'free';

    // Konversi ke enum untuk perbandingan
    StorageTier parse(String s) {
      return StorageTier.values.firstWhere((e) => e.name == s, orElse: () => StorageTier.free);
    }
    final cloudTier = parse(cloudTierStr);
    final localTier = parse(localTierStr);

    // Jangan downgrade tier lokal — hanya apply cloud jika tier cloud >= lokal
    if (cloudTier.index < localTier.index) return;

    final activeFrom = cloud['active_from'] as String?;
    final activeUntil = cloud['active_until'] as String?;
    final allowance = (cloud['cycle_allowance'] as num?)?.toInt();
    final used = (cloud['cycle_used'] as num?)?.toInt();

    await prefs.setString(_userKey(_tierKey), cloudTierStr);
    if (activeFrom != null) {
      await prefs.setInt(_userKey(_cycleStartKey), DateTime.parse(activeFrom).millisecondsSinceEpoch);
    }
    if (activeUntil != null) {
      await prefs.setInt(_userKey(_cycleEndKey), DateTime.parse(activeUntil).millisecondsSinceEpoch);
    }
    // Use correct allowance for tier if cloud value is incorrect
    final correctAllowance = _defaultAllowanceForTier(cloudTier);
    if (allowance != null && allowance != correctAllowance && allowance > 0) {
      await prefs.setInt(_userKey(_cycleAllowanceKey), correctAllowance);
      // Also fix cloud
      _supabase.client?.from('user_subscriptions').update({'cycle_allowance': correctAllowance}).eq('user_id', _supabase.currentUser!.id);
    } else if (allowance != null) {
      await prefs.setInt(_userKey(_cycleAllowanceKey), allowance);
    }
    if (used != null) {
      await prefs.setInt(_userKey(_cycleUsedKey), used);
    }
  }

  Future<void> syncToCloud() async {
    if (_supabase.currentUser == null) return;
    await _ensureCycleInitialized();
    final prefs = await SharedPreferences.getInstance();

    final tier = prefs.getString(_userKey(_tierKey)) ?? 'free';
    final startMs = prefs.getInt(_userKey(_cycleStartKey));
    final endMs = prefs.getInt(_userKey(_cycleEndKey));
    final allowance = prefs.getInt(_userKey(_cycleAllowanceKey)) ?? _freeScans;
    final used = prefs.getInt(_userKey(_cycleUsedKey)) ?? 0;
    final storageUsed = await getUsedBytes();

    // Enqueue via SyncQueue for reliable delivery with retry
    final queue = SyncQueue();
    queue.enqueue(SyncTaskType.syncSubscription, {
      'user_id': _supabase.currentUser!.id,
      'email': _supabase.currentUser!.email ?? '',
      'tier': tier,
      'active_from': startMs != null
          ? DateTime.fromMillisecondsSinceEpoch(startMs).toIso8601String()
          : '',
      'active_until': endMs != null
          ? DateTime.fromMillisecondsSinceEpoch(endMs).toIso8601String()
          : '',
      'cycle_allowance': allowance.toString(),
      'cycle_used': used.toString(),
      'storage_used': storageUsed.toString(),
    });
  }
}
