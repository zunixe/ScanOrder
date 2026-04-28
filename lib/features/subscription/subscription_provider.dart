import 'package:flutter/foundation.dart';
import '../../services/quota_service.dart';

class SubscriptionProvider extends ChangeNotifier {
  final QuotaService _quota = QuotaService();

  bool isPro = false;
  int totalScanned = 0;
  int remainingFree = 0;

  Future<void> loadStatus() async {
    isPro = await _quota.isPro();
    totalScanned = await _quota.getTotalScanned();
    remainingFree = await _quota.getRemainingFreeScans();
    notifyListeners();
  }

  Future<void> restorePurchase() async {
    // TODO: Implement IAP restore logic
    // For now, just reload status
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
}
