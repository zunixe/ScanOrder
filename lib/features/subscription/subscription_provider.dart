import 'package:flutter/foundation.dart';
import '../../services/quota_service.dart';

class SubscriptionProvider extends ChangeNotifier {
  final QuotaService _quota = QuotaService();

  bool isPro = false;
  int totalScanned = 0;
  int remainingFree = 0;
  int scanLimit = 0;
  String scanLimitDisplay = '';
  String tierName = 'Gratis';
  String tierPrice = 'Gratis';
  int usedBytes = 0;
  int totalBytes = 0;
  StorageTier currentTier = StorageTier.free;
  DateTime? activeFrom;
  DateTime? activeUntil;
  bool subscriptionActive = true;
  int cycleAllowance = 0;
  int cycleUsed = 0;

  Future<void> loadStatus() async {
    await _quota.syncFromCloud();
    isPro = await _quota.isPro();
    totalScanned = await _quota.getTotalScanned();
    remainingFree = await _quota.getRemainingFreeScans();
    scanLimit = await _quota.getScanLimit();
    currentTier = await _quota.getTier();
    scanLimitDisplay = _quota.getScanLimitDisplay(currentTier);
    tierName = _quota.getTierName(currentTier);
    tierPrice = _quota.getPriceDisplay(currentTier);
    usedBytes = await _quota.getUsedBytes();
    totalBytes = await _quota.getLimit();
    activeFrom = await _quota.getActiveFrom();
    activeUntil = await _quota.getActiveUntil();
    subscriptionActive = await _quota.isSubscriptionActive();
    cycleAllowance = await _quota.getCycleAllowance();
    cycleUsed = await _quota.getUsedInCurrentCycle();
    notifyListeners();
  }

  Future<void> restorePurchase() async {
    // TODO: Implement IAP restore logic
    await loadStatus();
  }

  Future<void> purchaseTier(StorageTier tier) async {
    // TODO: Implement IAP purchase logic with in_app_purchase
    // For demo/testing, set tier directly:
    await _quota.purchaseOrChangeTier(tier);
    await loadStatus();
  }

  // For testing only — cycle through tiers
  Future<void> toggleTierDebug() async {
    final nextIndex = (currentTier.index + 1) % 4;
    await _quota.setTier(StorageTier.values[nextIndex]);
    await loadStatus();
  }

  String get storageUsed {
    if (usedBytes >= 1024 * 1024 * 1024) {
      return '${(usedBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (usedBytes >= 1024 * 1024) {
      return '${(usedBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    } else if (usedBytes >= 1024) {
      return '${(usedBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$usedBytes B';
  }

  String get storageTotal {
    if (totalBytes < 0) return '∞';
    if (totalBytes >= 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
    } else if (totalBytes >= 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(totalBytes / 1024).toStringAsFixed(0)} KB';
  }

  double get storageFraction {
    if (totalBytes <= 0) return 0;
    return (usedBytes / totalBytes).clamp(0.0, 1.0);
  }
}
