import 'package:flutter/foundation.dart';
import '../../services/quota_service.dart';

class SubscriptionProvider extends ChangeNotifier {
  final QuotaService _quota = QuotaService();

  bool isPro = false;
  int totalScanned = 0;
  int remainingFree = 0;
  int usedBytes = 0;
  int totalBytes = 0;
  StorageTier currentTier = StorageTier.free;

  Future<void> loadStatus() async {
    isPro = await _quota.isPro();
    totalScanned = await _quota.getTotalScanned();
    remainingFree = await _quota.getRemainingFreeScans();
    usedBytes = await _quota.getUsedBytes();
    totalBytes = await _quota.getLimit();
    currentTier = await _quota.getTier();
    notifyListeners();
  }

  Future<void> restorePurchase() async {
    // TODO: Implement IAP restore logic
    await loadStatus();
  }

  Future<void> purchasePro() async {
    // TODO: Implement IAP purchase logic with in_app_purchase
    // For demo/testing, toggle pro status:
    await _quota.setPro(true);
    await loadStatus();
  }

  // For testing only — remove in production
  Future<void> toggleProDebug() async {
    await _quota.setPro(!isPro);
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
