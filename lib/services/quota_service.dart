import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/db/database_helper.dart';

enum StorageTier { free, basic, pro, unlimited }

class QuotaService {
  // Storage limits per tier (bytes)
  static const int _freeLimit = 100 * 1024 * 1024;       // 100MB
  static const int _basicLimit = 2 * 1024 * 1024 * 1024; // 2GB
  static const int _proLimit = 10 * 1024 * 1024 * 1024;  // 10GB

  // Scan limits per tier
  static const int _freeScans = 10000;

  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<bool> canScan() async {
    final total = await getTotalScanned();
    final tier = await getTier();
    if (tier.index >= StorageTier.pro.index) return true;
    if (tier == StorageTier.basic) return total < _freeScans * 2;
    return total < _freeScans;
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
    final tier = prefs.getString('storage_tier') ?? 'free';
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
    final orders = await _db.getAllOrders();
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
    return await _db.getTotalOrderCount();
  }

  Future<int> getRemainingFreeScans() async {
    final total = await getTotalScanned();
    final tier = await getTier();
    if (tier.index >= StorageTier.pro.index) return -1;
    if (tier == StorageTier.basic) return (_freeScans * 2 - total).clamp(0, _freeScans * 2);
    return (_freeScans - total).clamp(0, _freeScans);
  }

  Future<bool> isPro() async {
    final tier = await getTier();
    return tier.index >= StorageTier.basic.index;
  }

  Future<void> setTier(StorageTier tier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('storage_tier', tier.name);
  }

  Future<void> setPro(bool value) async {
    await setTier(value ? StorageTier.pro : StorageTier.free);
  }
}
