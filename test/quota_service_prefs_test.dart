import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scanorder/services/quota_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QuotaService SharedPreferences logic', () {
    late QuotaService quota;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      quota = QuotaService();
    });

    group('getTier', () {
      test('returns free by default', () async {
        final tier = await quota.getTier();
        expect(tier, StorageTier.free);
      });

      test('returns basic when set', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('storage_tier_anon', 'basic');
        final tier = await quota.getTier();
        expect(tier, StorageTier.basic);
      });

      test('returns pro when set', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('storage_tier_anon', 'pro');
        final tier = await quota.getTier();
        expect(tier, StorageTier.pro);
      });

      test('returns unlimited when set', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('storage_tier_anon', 'unlimited');
        final tier = await quota.getTier();
        expect(tier, StorageTier.unlimited);
      });

      test('pending tier cleans up and returns free', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('storage_tier_anon', 'pending');
        await prefs.setInt('subscription_cycle_allowance_anon', 100);
        await prefs.setInt('subscription_cycle_used_anon', 50);
        final tier = await quota.getTier();
        expect(tier, StorageTier.free);
        // Verify cleanup
        expect(prefs.getString('storage_tier_anon'), isNull);
        expect(prefs.getInt('subscription_cycle_allowance_anon'), isNull);
      });
    });

    group('isSubscriptionActive', () {
      test('free tier is always active', () async {
        final active = await quota.isSubscriptionActive();
        expect(active, true);
      });

      test('pro tier with future end date is active', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('storage_tier_anon', 'pro');
        await prefs.setInt('subscription_cycle_end_ms_anon',
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_start_ms_anon',
            DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_allowance_anon', 5000);
        final active = await quota.isSubscriptionActive();
        expect(active, true);
      });

      test('pro tier with past end date is inactive', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('storage_tier_anon', 'pro');
        await prefs.setInt('subscription_cycle_end_ms_anon',
            DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_start_ms_anon',
            DateTime.now().subtract(const Duration(days: 31)).millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_allowance_anon', 5000);
        final active = await quota.isSubscriptionActive();
        expect(active, false);
      });
    });

    group('isPro', () {
      test('free tier is not pro', () async {
        final isPro = await quota.isPro();
        expect(isPro, false);
      });

      test('basic tier with active subscription is pro', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('storage_tier_anon', 'basic');
        await prefs.setInt('subscription_cycle_end_ms_anon',
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_start_ms_anon',
            DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_allowance_anon', 1000);
        final isPro = await quota.isPro();
        expect(isPro, true);
      });
    });

    group('canScan', () {
      test('free tier with 0 used can scan', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('subscription_cycle_used_anon', 0);
        await prefs.setInt('subscription_cycle_allowance_anon', 100);
        await prefs.setInt('subscription_cycle_start_ms_anon',
            DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_end_ms_anon',
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);
        final canScan = await quota.canScan();
        expect(canScan, true);
      });

      test('unlimited tier can always scan', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('storage_tier_anon', 'unlimited');
        await prefs.setInt('subscription_cycle_allowance_anon', -1);
        await prefs.setInt('subscription_cycle_used_anon', 9999);
        await prefs.setInt('subscription_cycle_start_ms_anon',
            DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_end_ms_anon',
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);
        final canScan = await quota.canScan();
        expect(canScan, true);
      });
    });

    group('consumeScan', () {
      test('increments used count', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('subscription_cycle_used_anon', 5);
        await prefs.setInt('subscription_cycle_allowance_anon', 100);
        await prefs.setInt('subscription_cycle_start_ms_anon',
            DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_end_ms_anon',
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);
        await quota.consumeScan();
        expect(prefs.getInt('subscription_cycle_used_anon'), 6);
      });
    });

    group('getSavePhoto / setSavePhoto', () {
      test('defaults to true', () async {
        final val = await quota.getSavePhoto();
        expect(val, true);
      });

      test('setSavePhoto persists', () async {
        await quota.setSavePhoto(false);
        final val = await quota.getSavePhoto();
        expect(val, false);
      });
    });

    group('getLimit', () {
      test('free tier limit', () async {
        final limit = await quota.getLimit();
        expect(limit, 100 * 1024 * 1024);
      });

      test('pro tier limit', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('storage_tier_anon', 'pro');
        await prefs.setInt('subscription_cycle_start_ms_anon',
            DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_end_ms_anon',
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_allowance_anon', 5000);
        final limit = await quota.getLimit();
        expect(limit, 10 * 1024 * 1024 * 1024);
      });

      test('unlimited tier returns -1', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('storage_tier_anon', 'unlimited');
        await prefs.setInt('subscription_cycle_start_ms_anon',
            DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_end_ms_anon',
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_allowance_anon', -1);
        final limit = await quota.getLimit();
        expect(limit, -1);
      });
    });

    group('getCycleAllowance', () {
      test('defaults to free allowance', () async {
        final allowance = await quota.getCycleAllowance();
        expect(allowance, 100);
      });
    });

    group('getUsedInCurrentCycle', () {
      test('defaults to 0', () async {
        final used = await quota.getUsedInCurrentCycle();
        expect(used, 0);
      });
    });

    group('setTier', () {
      test('sets tier to pro', () async {
        await quota.setTier(StorageTier.pro);
        final tier = await quota.getTier();
        expect(tier, StorageTier.pro);
      });
    });

    group('display helpers', () {
      test('getScanLimitDisplay for all tiers', () {
        expect(quota.getScanLimitDisplay(StorageTier.free), '100');
        expect(quota.getScanLimitDisplay(StorageTier.basic), '1rb');
        expect(quota.getScanLimitDisplay(StorageTier.pro), '5rb');
        expect(quota.getScanLimitDisplay(StorageTier.unlimited), '∞');
      });

      test('getTierName for all tiers', () {
        expect(quota.getTierName(StorageTier.free), 'Gratis');
        expect(quota.getTierName(StorageTier.basic), 'Basic');
        expect(quota.getTierName(StorageTier.pro), 'Pro');
        expect(quota.getTierName(StorageTier.unlimited), 'Tim');
      });

      test('getPriceDisplay for all tiers', () {
        expect(quota.getPriceDisplay(StorageTier.free), 'Gratis');
        expect(quota.getPriceDisplay(StorageTier.basic), 'Rp 29.000');
        expect(quota.getPriceDisplay(StorageTier.pro), 'Rp 99.000');
        expect(quota.getPriceDisplay(StorageTier.unlimited), 'Rp 399.000');
      });

      test('getPriceForTier returns correct values', () {
        expect(quota.getPriceForTier(StorageTier.free), 0);
        expect(quota.getPriceForTier(StorageTier.basic), 29000);
        expect(quota.getPriceForTier(StorageTier.pro), 99000);
        expect(quota.getPriceForTier(StorageTier.unlimited), 399000);
      });
    });

    group('purchaseOrChangeTier', () {
      test('upgrade from free to basic sets correct tier', () async {
        await quota.purchaseOrChangeTier(StorageTier.basic, carryOver: false);
        final tier = await quota.getTier();
        expect(tier, StorageTier.basic);
      });

      test('upgrade from free to pro sets correct tier', () async {
        await quota.purchaseOrChangeTier(StorageTier.pro, carryOver: false);
        final tier = await quota.getTier();
        expect(tier, StorageTier.pro);
      });

      test('upgrade to unlimited sets allowance to -1', () async {
        await quota.purchaseOrChangeTier(StorageTier.unlimited, carryOver: false);
        final allowance = await quota.getCycleAllowance();
        expect(allowance, -1);
      });

      test('upgrade sets cycle start and end', () async {
        await quota.purchaseOrChangeTier(StorageTier.pro, carryOver: false);
        final from = await quota.getActiveFrom();
        final until = await quota.getActiveUntil();
        expect(from, isNotNull);
        expect(until, isNotNull);
        expect(until!.isAfter(from!), true);
      });
    });

    group('getRemainingFreeScans', () {
      test('free tier with 0 used returns 100', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('subscription_cycle_used_anon', 0);
        await prefs.setInt('subscription_cycle_allowance_anon', 100);
        await prefs.setInt('subscription_cycle_start_ms_anon',
            DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_end_ms_anon',
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);
        final remaining = await quota.getRemainingFreeScans();
        expect(remaining, 100);
      });

      test('unlimited tier returns -1', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('storage_tier_anon', 'unlimited');
        await prefs.setInt('subscription_cycle_allowance_anon', -1);
        await prefs.setInt('subscription_cycle_used_anon', 0);
        await prefs.setInt('subscription_cycle_start_ms_anon',
            DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt('subscription_cycle_end_ms_anon',
            DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);
        final remaining = await quota.getRemainingFreeScans();
        expect(remaining, -1);
      });
    });

    group('getScanLimit', () {
      test('free tier returns 100', () async {
        final limit = await quota.getScanLimit();
        expect(limit, 100);
      });
    });

    group('getActiveFrom / getActiveUntil', () {
      test('returns not null after initialization', () async {
        SharedPreferences.setMockInitialValues({});
        final from = await quota.getActiveFrom();
        // After _ensureCycleInitialized, it should be set
        expect(from, isNotNull);
      });
    });

    group('migrateToUserScopedKeys', () {
      test('does not throw when no user logged in', () async {
        expect(() => quota.migrateToUserScopedKeys(), returnsNormally);
      });
    });

    group('setPro', () {
      test('setPro true upgrades to pro', () async {
        await quota.setPro(true);
        final tier = await quota.getTier();
        expect(tier, StorageTier.pro);
      });

      test('setPro false downgrades to free', () async {
        await quota.setPro(true);
        await quota.setPro(false);
        final tier = await quota.getTier();
        expect(tier, StorageTier.free);
      });
    });

    group('canStorePhoto', () {
      test('defaults to true', () async {
        final canStore = await quota.canStorePhoto();
        expect(canStore, true);
      });
    });
  });
}
