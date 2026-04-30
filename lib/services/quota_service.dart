import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/db/database_helper.dart';

enum StorageTier { free, basic, pro, unlimited }

class QuotaService {
  // Scan limits per tier (per bulan)
  static const int _freeScans = 10;
  static const int _basicScans = 1000;
  static const int _proScans = 5000;
  static const int _unlimitedScans = -1; // unlimited

  // Harga per tier (IDR)
  static const int _basicPrice = 29000;
  static const int _proPrice = 99000;
  static const int _teamPrice = 399000;

  // Storage limits per tier (bytes) - untuk info foto saja
  static const int _freeLimit = 100 * 1024 * 1024;       // 100MB
  static const int _basicLimit = 2 * 1024 * 1024 * 1024; // 2GB
  static const int _proLimit = 10 * 1024 * 1024 * 1024;  // 10GB


  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<int> _getScanLimitForTier(StorageTier tier) async {
    switch (tier) {
      case StorageTier.free: return _freeScans;
      case StorageTier.basic: return _basicScans;
      case StorageTier.pro: return _proScans;
      case StorageTier.unlimited: return _unlimitedScans;
    }
  }

  Future<bool> canScan() async {
    final total = await getTotalScanned();
    final tier = await getTier();
    final limit = await _getScanLimitForTier(tier);
    if (limit < 0) return true; // unlimited
    return total < limit;
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
    final limit = await _getScanLimitForTier(tier);
    if (limit < 0) return -1; // unlimited
    return (limit - total).clamp(0, limit);
  }

  Future<int> getScanLimit() async {
    final tier = await getTier();
    return _getScanLimitForTier(tier);
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
