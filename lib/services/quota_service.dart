import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/db/database_helper.dart';
import '../core/supabase/supabase_service.dart';

enum StorageTier { free, basic, pro, unlimited }

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


  final DatabaseHelper _db = DatabaseHelper.instance;
  final SupabaseService _supabase = SupabaseService();
  static const String _tierKey = 'storage_tier';
  static const String _cycleStartKey = 'subscription_cycle_start_ms';
  static const String _cycleEndKey = 'subscription_cycle_end_ms';
  static const String _cycleAllowanceKey = 'subscription_cycle_allowance';
  static const String _cycleUsedKey = 'subscription_cycle_used';
  static const int _cycleDays = 30;

  int _defaultAllowanceForTier(StorageTier tier) {
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

  Future<void> _ensureCycleInitialized() async {
    final prefs = await SharedPreferences.getInstance();
    final startMs = prefs.getInt(_cycleStartKey);
    final endMs = prefs.getInt(_cycleEndKey);
    final allowance = prefs.getInt(_cycleAllowanceKey);
    if (startMs != null && endMs != null && allowance != null) return;

    final now = DateTime.now();
    final tier = await getTier();
    await prefs.setInt(_cycleStartKey, now.millisecondsSinceEpoch);
    await prefs.setInt(_cycleEndKey, now.add(const Duration(days: _cycleDays)).millisecondsSinceEpoch);
    await prefs.setInt(_cycleAllowanceKey, _defaultAllowanceForTier(tier));
    await prefs.setInt(_cycleUsedKey, 0);
  }

  Future<void> _autoRollFreeCycleIfNeeded() async {
    await _ensureCycleInitialized();
    final tier = await getTier();
    if (tier != StorageTier.free) return;

    final prefs = await SharedPreferences.getInstance();
    final endMs = prefs.getInt(_cycleEndKey) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch <= endMs) return;

    final now = DateTime.now();
    await prefs.setInt(_cycleStartKey, now.millisecondsSinceEpoch);
    await prefs.setInt(_cycleEndKey, now.add(const Duration(days: _cycleDays)).millisecondsSinceEpoch);
    await prefs.setInt(_cycleAllowanceKey, _freeScans);
    await prefs.setInt(_cycleUsedKey, 0);
  }

  Future<bool> canScan() async {
    await _autoRollFreeCycleIfNeeded();
    final tier = await getTier();
    final active = await isSubscriptionActive();
    if (tier != StorageTier.free && !active) return false;

    final allowance = await getCycleAllowance();
    final used = await getUsedInCurrentCycle();
    if (allowance < 0) return true;
    return used < allowance;
  }

  Future<void> consumeScan() async {
    await _ensureCycleInitialized();
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt(_cycleUsedKey) ?? 0;
    await prefs.setInt(_cycleUsedKey, used + 1);
    await syncToCloud();
  }

  Future<bool> isSubscriptionActive() async {
    await _autoRollFreeCycleIfNeeded();
    final tier = await getTier();
    if (tier == StorageTier.free) return true;
    final end = await getActiveUntil();
    if (end == null) return false;
    return DateTime.now().isBefore(end);
  }

  Future<DateTime?> getActiveFrom() async {
    await _ensureCycleInitialized();
    final prefs = await SharedPreferences.getInstance();
    final startMs = prefs.getInt(_cycleStartKey);
    if (startMs == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(startMs);
  }

  Future<DateTime?> getActiveUntil() async {
    await _ensureCycleInitialized();
    final prefs = await SharedPreferences.getInstance();
    final endMs = prefs.getInt(_cycleEndKey);
    if (endMs == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(endMs);
  }

  Future<int> getCycleAllowance() async {
    await _ensureCycleInitialized();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_cycleAllowanceKey) ?? _freeScans;
  }

  Future<int> getUsedInCurrentCycle() async {
    await _ensureCycleInitialized();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_cycleUsedKey) ?? 0;
  }

  Future<bool> canStorePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('save_photo') ?? true;
  }

  Future<bool> getSavePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('save_photo') ?? true;
  }

  Future<void> setSavePhoto(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('save_photo', value);
  }

  Future<StorageTier> getTier() async {
    final prefs = await SharedPreferences.getInstance();
    final tier = prefs.getString(_tierKey) ?? 'free';
    switch (tier) {
      case 'basic': return StorageTier.basic;
      case 'pro': return StorageTier.pro;
      case 'unlimited': return StorageTier.unlimited;
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
    final orders = await _db.getAllOrders(userId: userId);
    int total = 0;
    for (final order in orders) {
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
    final allowance = await getCycleAllowance();
    final used = await getUsedInCurrentCycle();
    if (allowance < 0) return -1;
    return (allowance - used).clamp(0, allowance);
  }

  Future<int> getScanLimit() async {
    return getCycleAllowance();
  }

  String getScanLimitDisplay(StorageTier tier) {
    switch (tier) {
      case StorageTier.free: return '$_freeScans';
      case StorageTier.basic: return '$_basicScans';
      case StorageTier.pro: return '${_proScans ~/ 1000}rb';
      case StorageTier.unlimited: return '∞';
    }
  }

  String getTierName(StorageTier tier) {
    switch (tier) {
      case StorageTier.free: return 'Gratis';
      case StorageTier.basic: return 'Basic';
      case StorageTier.pro: return 'Pro';
      case StorageTier.unlimited: return 'Team';
    }
  }

  int getPriceForTier(StorageTier tier) {
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
    await prefs.setString(_tierKey, tier.name);
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
    final oldEndMs = prefs.getInt(_cycleEndKey) ?? 0;
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

    await prefs.setString(_tierKey, newTier.name);
    await prefs.setInt(_cycleStartKey, now.millisecondsSinceEpoch);
    await prefs.setInt(_cycleEndKey, now.add(Duration(days: _cycleDays + extraDays)).millisecondsSinceEpoch);
    await prefs.setInt(_cycleAllowanceKey, newAllowance);
    await prefs.setInt(_cycleUsedKey, 0);
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
      return;
    }
    if (cloud == null) return;

    final prefs = await SharedPreferences.getInstance();
    final cloudTierStr = (cloud['tier'] as String?) ?? 'free';
    final localTierStr = prefs.getString(_tierKey) ?? 'free';

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

    await prefs.setString(_tierKey, cloudTierStr);
    if (activeFrom != null) {
      await prefs.setInt(_cycleStartKey, DateTime.parse(activeFrom).millisecondsSinceEpoch);
    }
    if (activeUntil != null) {
      await prefs.setInt(_cycleEndKey, DateTime.parse(activeUntil).millisecondsSinceEpoch);
    }
    if (allowance != null) {
      await prefs.setInt(_cycleAllowanceKey, allowance);
    }
    if (used != null) {
      await prefs.setInt(_cycleUsedKey, used);
    }
  }

  Future<void> syncToCloud() async {
    if (_supabase.currentUser == null) return;
    await _ensureCycleInitialized();
    final prefs = await SharedPreferences.getInstance();

    final tier = prefs.getString(_tierKey) ?? 'free';
    final startMs = prefs.getInt(_cycleStartKey);
    final endMs = prefs.getInt(_cycleEndKey);
    final allowance = prefs.getInt(_cycleAllowanceKey) ?? _freeScans;
    final used = prefs.getInt(_cycleUsedKey) ?? 0;

    await _supabase.upsertMySubscription({
      'tier': tier,
      'active_from': startMs != null
          ? DateTime.fromMillisecondsSinceEpoch(startMs).toIso8601String()
          : null,
      'active_until': endMs != null
          ? DateTime.fromMillisecondsSinceEpoch(endMs).toIso8601String()
          : null,
      'cycle_allowance': allowance,
      'cycle_used': used,
    });
  }
}
