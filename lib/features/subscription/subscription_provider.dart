import 'package:flutter/foundation.dart';
import '../../services/iap_service.dart';
import '../../services/quota_service.dart';

class SubscriptionProvider extends ChangeNotifier {
  final QuotaService _quota = QuotaService();
  final IapService _iap = IapService();

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
  bool iapAvailable = false;
  bool isPurchasing = false;
  String? purchaseError;
  List<String> notFoundProductIds = [];

  Future<void> initializeIap() async {
    await _iap.initialize(onPurchaseApplied: (_) async {
      isPurchasing = false;
      await loadStatus();
    });
    iapAvailable = _iap.isAvailable;
    notFoundProductIds = _iap.notFoundProductIds;
    // Don't show product-not-found error on init — only when user tries to buy
    notifyListeners();
  }

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
    purchaseError = null;
    isPurchasing = true;
    notifyListeners();
    await initializeIap();
    if (!iapAvailable) {
      purchaseError = 'Google Play Billing belum tersedia di perangkat ini.';
      isPurchasing = false;
      notifyListeners();
      return;
    }
    await _iap.restorePurchases();
    isPurchasing = false;
    await loadStatus();
  }

  Future<void> purchaseTier(StorageTier tier) async {
    purchaseError = null;
    isPurchasing = true;
    notifyListeners();
    await initializeIap();
    if (!iapAvailable) {
      purchaseError = 'Google Play Billing belum tersedia. Pastikan app di-install dari Play Store/internal testing.';
      isPurchasing = false;
      notifyListeners();
      return;
    }
    final started = await _iap.buyTier(tier);
    if (!started) {
      final productId = _iap.productIdForTier(tier);
      if (notFoundProductIds.isNotEmpty) {
        purchaseError = 'Produk tidak ditemukan: ${notFoundProductIds.join(', ')}. '
            'Pastikan Product ID di Google Play Console sama dengan di app:\n'
            '• Basic: scanorder_basic_monthly\n'
            '• Pro: scanorder_pro_monthly\n'
            '• Team: scanorder_team_monthly';
      } else {
        purchaseError = 'Produk $productId belum tersedia. Cek Product ID di Google Play Console.';
      }
      isPurchasing = false;
      notifyListeners();
    }
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

  @override
  void dispose() {
    _iap.dispose();
    super.dispose();
  }
}
