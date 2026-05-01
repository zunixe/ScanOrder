import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'quota_service.dart';

class IapService {
  static const String basicProductId = 'scanorder_basic_monthly';
  static const String proProductId = 'scanorder_pro_monthly';
  static const String teamProductId = 'scanorder_team_monthly';

  final InAppPurchase _iap = InAppPurchase.instance;
  final QuotaService _quota = QuotaService();
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _isAvailable = false;
  List<ProductDetails> _products = [];
  List<String> _notFoundIds = [];

  // Track active purchases for subscription upgrade support
  final Map<String, PurchaseDetails> _activePurchases = {};

  bool get isAvailable => _isAvailable;
  List<ProductDetails> get products => List.unmodifiable(_products);
  List<String> get notFoundProductIds => List.unmodifiable(_notFoundIds);

  Future<void> initialize({Future<void> Function(StorageTier tier)? onPurchaseApplied}) async {
    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) return;

    _subscription ??= _iap.purchaseStream.listen(
      (purchases) => _handlePurchaseUpdates(purchases, onPurchaseApplied: onPurchaseApplied),
      onError: (Object error) => debugPrint('[IAP] purchase stream error: $error'),
    );

    await loadProducts();
  }

  Future<void> loadProducts() async {
    if (!_isAvailable) return;
    final response = await _iap.queryProductDetails({
      basicProductId,
      proProductId,
      teamProductId,
    });

    if (response.error != null) {
      debugPrint('[IAP] query products error: ${response.error}');
    }
    _notFoundIds = response.notFoundIDs;
    if (_notFoundIds.isNotEmpty) {
      debugPrint('[IAP] products not found: ${_notFoundIds.join(', ')}');
    }
    _products = response.productDetails;
  }

  Future<bool> buyTier(StorageTier tier) async {
    if (!_isAvailable) {
      await initialize();
    }
    if (!_isAvailable) return false;
    if (_products.isEmpty) {
      await loadProducts();
    }

    final productId = productIdForTier(tier);
    final product = _products.where((p) => p.id == productId).firstOrNull;
    if (product == null) {
      debugPrint('[IAP] product not found for tier $tier ($productId)');
      return false;
    }

    // On Android, if upgrading from an existing subscription, use ChangeSubscriptionParam
    PurchaseParam purchaseParam;
    if (Platform.isAndroid) {
      final existingPurchase = _findExistingSubscriptionPurchase(tier);
      if (existingPurchase != null) {
        debugPrint('[IAP] Upgrading from ${existingPurchase.productID} to $productId');
        purchaseParam = GooglePlayPurchaseParam(
          productDetails: product,
          changeSubscriptionParam: ChangeSubscriptionParam(
            oldPurchaseDetails: existingPurchase as GooglePlayPurchaseDetails,
            replacementMode: ReplacementMode.withTimeProration,
          ),
        );
      } else {
        purchaseParam = PurchaseParam(productDetails: product);
      }
    } else {
      purchaseParam = PurchaseParam(productDetails: product);
    }

    return _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    if (!_isAvailable) {
      await initialize();
    }
    if (!_isAvailable) return;
    await _iap.restorePurchases();
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases, {
    Future<void> Function(StorageTier tier)? onPurchaseApplied,
  }) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        debugPrint('[IAP] purchase error: ${purchase.error}');
      }

      if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
        _activePurchases[purchase.productID] = purchase;
        final tier = tierForProductId(purchase.productID);
        if (tier != null) {
          await _quota.purchaseOrChangeTier(tier);
          await onPurchaseApplied?.call(tier);
        }
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  String productIdForTier(StorageTier tier) {
    switch (tier) {
      case StorageTier.basic:
        return basicProductId;
      case StorageTier.pro:
        return proProductId;
      case StorageTier.unlimited:
        return teamProductId;
      case StorageTier.free:
        return '';
    }
  }

  /// Find an existing active subscription purchase for a lower tier
  PurchaseDetails? _findExistingSubscriptionPurchase(StorageTier newTier) {
    for (final entry in _activePurchases.entries) {
      final existingTier = tierForProductId(entry.key);
      if (existingTier != null && existingTier.index < newTier.index) {
        return entry.value;
      }
    }
    return null;
  }

  StorageTier? tierForProductId(String productId) {
    switch (productId) {
      case basicProductId:
        return StorageTier.basic;
      case proProductId:
        return StorageTier.pro;
      case teamProductId:
        return StorageTier.unlimited;
      default:
        return null;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
