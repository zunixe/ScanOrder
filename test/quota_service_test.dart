import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:scanorder/core/supabase/supabase_service.dart';
import 'package:scanorder/services/quota_service.dart';

import 'helpers/test_db.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

class MockUser extends Mock implements User {}

void main() {
  setUpAll(setupTestDatabase);
  tearDownAll(teardownTestDatabase);
  group('StorageTier', () {
    test('Tier order: free < basic < pro < unlimited', () {
      expect(StorageTier.free.index < StorageTier.basic.index, isTrue);
      expect(StorageTier.basic.index < StorageTier.pro.index, isTrue);
      expect(StorageTier.pro.index < StorageTier.unlimited.index, isTrue);
    });

    test('Tier names match expected strings', () {
      expect(StorageTier.free.name, 'free');
      expect(StorageTier.basic.name, 'basic');
      expect(StorageTier.pro.name, 'pro');
      expect(StorageTier.unlimited.name, 'unlimited');
    });

    test('4 tiers exist', () {
      expect(StorageTier.values.length, 4);
    });
  });

  group('QuotaService tier constants', () {
    test('Free tier is index 0', () {
      expect(StorageTier.free.index, 0);
    });

    test('Basic tier is index 1', () {
      expect(StorageTier.basic.index, 1);
    });

    test('Pro tier is index 2', () {
      expect(StorageTier.pro.index, 2);
    });

    test('Unlimited tier is index 3', () {
      expect(StorageTier.unlimited.index, 3);
    });
  });

  group('Upgrade logic (tier index comparison)', () {
    test('Basic to Pro is upgrade', () {
      expect(StorageTier.pro.index > StorageTier.basic.index, isTrue);
    });

    test('Basic to Unlimited is upgrade', () {
      expect(StorageTier.unlimited.index > StorageTier.basic.index, isTrue);
    });

    test('Pro to Unlimited is upgrade', () {
      expect(StorageTier.unlimited.index > StorageTier.pro.index, isTrue);
    });

    test('Pro to Basic is NOT upgrade', () {
      expect(StorageTier.basic.index > StorageTier.pro.index, isFalse);
    });

    test('Same tier is NOT upgrade', () {
      expect(StorageTier.pro.index > StorageTier.pro.index, isFalse);
    });
  });

  group('Carry-over rule', () {
    bool shouldCarryOver(StorageTier oldTier, StorageTier newTier) {
      return oldTier != StorageTier.free && newTier.index > oldTier.index;
    }

    test('Free to Basic does NOT carry over', () {
      expect(shouldCarryOver(StorageTier.free, StorageTier.basic), isFalse);
    });

    test('Free to Pro does NOT carry over', () {
      expect(shouldCarryOver(StorageTier.free, StorageTier.pro), isFalse);
    });

    test('Free to Team does NOT carry over', () {
      expect(shouldCarryOver(StorageTier.free, StorageTier.unlimited), isFalse);
    });

    test('Basic to Pro carries over', () {
      expect(shouldCarryOver(StorageTier.basic, StorageTier.pro), isTrue);
    });

    test('Basic to Team carries over', () {
      expect(shouldCarryOver(StorageTier.basic, StorageTier.unlimited), isTrue);
    });

    test('Pro to Team carries over', () {
      expect(shouldCarryOver(StorageTier.pro, StorageTier.unlimited), isTrue);
    });
  });

  group('PackageInfo', () {
    test('priceDisplay returns Gratis for price 0', () {
      const pkg = PackageInfo(
        id: 'free', name: 'Free', price: 0, scanLimit: 200,
        maxMembers: 1, features: [], isPopular: false,
      );
      expect(pkg.priceDisplay, 'Gratis');
    });

    test('priceDisplay formats Rp with dots', () {
      const pkg = PackageInfo(
        id: 'pro', name: 'Pro', price: 99000, scanLimit: 9000,
        maxMembers: 1, features: [], isPopular: true,
      );
      expect(pkg.priceDisplay, 'Rp 99.000');
    });

    test('priceDisplay formats large price', () {
      const pkg = PackageInfo(
        id: 'team', name: 'Team', price: 399000, scanLimit: 0,
        maxMembers: 10, features: [], isPopular: false,
      );
      expect(pkg.priceDisplay, 'Rp 399.000');
    });

    test('scanLimitDisplay returns ∞ for 0', () {
      const pkg = PackageInfo(
        id: 'unlimited', name: 'Team', price: 399000, scanLimit: 0,
        maxMembers: 10, features: [], isPopular: false,
      );
      expect(pkg.scanLimitDisplay, '∞');
    });

    test('scanLimitDisplay returns rb for >= 1000', () {
      const pkg = PackageInfo(
        id: 'pro', name: 'Pro', price: 99000, scanLimit: 9000,
        maxMembers: 1, features: [], isPopular: true,
      );
      expect(pkg.scanLimitDisplay, '9rb');
    });

    test('scanLimitDisplay returns number for < 1000', () {
      const pkg = PackageInfo(
        id: 'free', name: 'Free', price: 0, scanLimit: 200,
        maxMembers: 1, features: [], isPopular: false,
      );
      expect(pkg.scanLimitDisplay, '200');
    });
  });

  group('QuotaService fallback packages', () {
    test('fallback packages have 4 entries', () {
      final quota = QuotaService();
      expect(quota.packages.length, 4);
    });

    test('fallback packages contain expected ids', () {
      final quota = QuotaService();
      final ids = quota.packages.map((p) => p.id).toList();
      expect(ids, containsAll(['free', 'basic', 'pro', 'unlimited']));
    });

    test('fallback free package has correct limits', () {
      final quota = QuotaService();
      final free = quota.packages.firstWhere((p) => p.id == 'free');
      expect(free.scanLimit, 200);
      expect(free.price, 0);
      expect(free.maxMembers, 1);
    });

    test('fallback pro package is popular', () {
      final quota = QuotaService();
      final pro = quota.packages.firstWhere((p) => p.id == 'pro');
      expect(pro.isPopular, isTrue);
    });

    test('fallback team package has unlimited scans', () {
      final quota = QuotaService();
      final team = quota.packages.firstWhere((p) => p.id == 'unlimited');
      expect(team.scanLimit, 0);
      expect(team.maxMembers, 10);
    });
  });

  group('QuotaService display helpers', () {
    test('getTierName returns correct names', () {
      final quota = QuotaService();
      expect(quota.getTierName(StorageTier.free), 'Gratis');
      expect(quota.getTierName(StorageTier.basic), 'Basic');
      expect(quota.getTierName(StorageTier.pro), 'Pro');
      expect(quota.getTierName(StorageTier.unlimited), 'Tim');
    });

    test('getPriceDisplay returns correct prices', () {
      final quota = QuotaService();
      expect(quota.getPriceDisplay(StorageTier.free), 'Gratis');
      expect(quota.getPriceDisplay(StorageTier.basic), 'Rp 29.000');
      expect(quota.getPriceDisplay(StorageTier.pro), 'Rp 99.000');
      expect(quota.getPriceDisplay(StorageTier.unlimited), 'Rp 399.000');
    });

    test('getScanLimitDisplay returns correct limits', () {
      final quota = QuotaService();
      expect(quota.getScanLimitDisplay(StorageTier.free), '200');
      expect(quota.getScanLimitDisplay(StorageTier.basic), '3rb');
      expect(quota.getScanLimitDisplay(StorageTier.pro), '9rb');
      expect(quota.getScanLimitDisplay(StorageTier.unlimited), '∞');
    });
  });

  group('QuotaService behavior (anon user, mocked prefs)', () {
    late MockSupabaseService supabase;
    late QuotaService quota;

    setUp(() async {
      await clearTestData();
      SharedPreferences.setMockInitialValues({});
      supabase = MockSupabaseService();
      when(() => supabase.currentUser).thenReturn(null);
      when(() => supabase.client).thenReturn(null);
      quota = QuotaService(supabase: supabase);
    });

    test('getTier defaults to free', () async {
      expect(await quota.getTier(), StorageTier.free);
    });

    test('getTier reads stored tier', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('storage_tier_anon', 'pro');
      expect(await quota.getTier(), StorageTier.pro);
    });

    test('getTier clears corrupt pending tier', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('storage_tier_anon', 'pending');
      await prefs.setInt('subscription_cycle_allowance_anon', 100);
      await prefs.setInt('subscription_cycle_used_anon', 50);
      expect(await quota.getTier(), StorageTier.free);
      expect(prefs.getString('storage_tier_anon'), isNull);
      expect(prefs.getInt('subscription_cycle_allowance_anon'), isNull);
      expect(prefs.getInt('subscription_cycle_used_anon'), isNull);
    });

    test('getLimit returns bytes per tier', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(await quota.getLimit(), 0); // free = no cloud

      await prefs.setString('storage_tier_anon', 'basic');
      expect(await quota.getLimit(), 2 * 1024 * 1024 * 1024);

      await prefs.setString('storage_tier_anon', 'pro');
      expect(await quota.getLimit(), 5 * 1024 * 1024 * 1024);

      await prefs.setString('storage_tier_anon', 'unlimited');
      expect(await quota.getLimit(), 15 * 1024 * 1024 * 1024);
    });

    test('canScan true for fresh free tier', () async {
      expect(await quota.canScan(), isTrue);
    });

    test('canScan false when quota exhausted', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('storage_tier_anon', 'free');
      await prefs.setInt('subscription_cycle_allowance_anon', 2);
      await prefs.setInt('subscription_cycle_used_anon', 2);
      await prefs.setInt('subscription_cycle_start_ms_anon', DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt('subscription_cycle_end_ms_anon', DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);
      expect(await quota.canScan(), isFalse);
    });

    test('consumeScan increments used count', () async {
      expect(await quota.getUsedInCurrentCycle(), 0);
      await quota.consumeScan();
      expect(await quota.getUsedInCurrentCycle(), 1);
      await quota.consumeScan();
      expect(await quota.getUsedInCurrentCycle(), 2);
    });

    test('getRemainingFreeScans decreases', () async {
      final before = await quota.getRemainingFreeScans();
      await quota.consumeScan();
      final after = await quota.getRemainingFreeScans();
      expect(after, before - 1);
    });

    test('getScanLimit returns free allowance', () async {
      expect(await quota.getScanLimit(), 200);
    });

    test('unlimited tier has negative remaining (∞)', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('storage_tier_anon', 'unlimited');
      await prefs.setInt('subscription_cycle_allowance_anon', -1);
      await prefs.setInt('subscription_cycle_used_anon', 0);
      await prefs.setInt('subscription_cycle_start_ms_anon', DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt('subscription_cycle_end_ms_anon', DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);
      expect(await quota.getRemainingFreeScans(), -1);
      expect(await quota.canScan(), isTrue);
    });

    test('isSubscriptionActive true for free', () async {
      expect(await quota.isSubscriptionActive(), isTrue);
    });

    test('isSubscriptionActive false when expired', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('storage_tier_anon', 'pro');
      await prefs.setInt('subscription_cycle_start_ms_anon', DateTime.now().subtract(const Duration(days: 60)).millisecondsSinceEpoch);
      await prefs.setInt('subscription_cycle_end_ms_anon', DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch);
      await prefs.setInt('subscription_cycle_allowance_anon', 9000);
      expect(await quota.isSubscriptionActive(), isFalse);
    });

    test('isPro true for active pro', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('storage_tier_anon', 'pro');
      await prefs.setInt('subscription_cycle_start_ms_anon', DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt('subscription_cycle_end_ms_anon', DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch);
      await prefs.setInt('subscription_cycle_allowance_anon', 9000);
      expect(await quota.isPro(), isTrue);
    });

    test('isPro false for free', () async {
      expect(await quota.isPro(), isFalse);
    });

    test('purchaseOrChangeTier free→pro resets allowance (no carry-over)', () async {
      await quota.purchaseOrChangeTier(StorageTier.pro);
      expect(await quota.getTier(), StorageTier.pro);
      expect(await quota.getCycleAllowance(), 9000);
      expect(await quota.getUsedInCurrentCycle(), 0);
    });

    test('purchaseOrChangeTier upgrade carries over remaining', () async {
      // Active basic with some used.
      await quota.purchaseOrChangeTier(StorageTier.basic);
      await quota.consumeScan();
      await quota.consumeScan();
      final remainingBefore = await quota.getRemainingFreeScans(); // 3000-2

      await quota.purchaseOrChangeTier(StorageTier.pro);
      // allowance = 9000 + (3000-2)
      expect(await quota.getCycleAllowance(), 9000 + remainingBefore);
    });

    test('purchaseOrChangeTier downgrade resets to tier limit', () async {
      await quota.purchaseOrChangeTier(StorageTier.pro);
      await quota.consumeScan();
      await quota.purchaseOrChangeTier(StorageTier.basic);
      expect(await quota.getCycleAllowance(), 3000);
      expect(await quota.getUsedInCurrentCycle(), 0);
    });

    test('purchaseOrChangeTier to unlimited sets -1', () async {
      await quota.purchaseOrChangeTier(StorageTier.unlimited);
      expect(await quota.getCycleAllowance(), -1);
    });

    test('setTier persists tier', () async {
      await quota.setTier(StorageTier.basic);
      expect(await quota.getTier(), StorageTier.basic);
    });

    test('setPro toggles pro/free', () async {
      await quota.setPro(true);
      expect(await quota.getTier(), StorageTier.pro);
      await quota.setPro(false);
      expect(await quota.getTier(), StorageTier.free);
    });

    test('savePhoto preference round-trips', () async {
      expect(await quota.getSavePhoto(), isTrue);
      await quota.setSavePhoto(false);
      expect(await quota.getSavePhoto(), isFalse);
      expect(await quota.canStorePhoto(), isFalse);
    });

    test('manualPhoto preference round-trips', () async {
      expect(await quota.getManualPhoto(), isFalse);
      await quota.setManualPhoto(true);
      expect(await quota.getManualPhoto(), isTrue);
    });

    test('getActiveFrom / getActiveUntil return cycle bounds', () async {
      await quota.getCycleAllowance(); // force init
      expect(await quota.getActiveFrom(), isNotNull);
      expect(await quota.getActiveUntil(), isNotNull);
    });

    test('migrateToUserScopedKeys is a no-op when not logged in', () async {
      await quota.migrateToUserScopedKeys();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('_migrated_anon'), isNull);
    });

    test('getUsedBytes is 0 with no scans', () async {
      expect(await quota.getUsedBytes(), 0);
    });

    test('getRemainingBytes returns -1 for free tier', () async {
      expect(await quota.getRemainingBytes(), -1);
    });

    test('isCloudStorageFull false for free tier', () async {
      expect(await quota.isCloudStorageFull(), isFalse);
    });

    test('evictOldPhotosIfNeeded returns 0 for free tier', () async {
      expect(await quota.evictOldPhotosIfNeeded(), 0);
    });

    test('loadPackages keeps fallback when not configured', () async {
      await quota.loadPackages();
      expect(quota.packages, hasLength(4));
    });
  });

  group('QuotaService cloud sync & packages (mocked Supabase)', () {
    late MockSupabaseService supabase;
    late QuotaService quota;
    late MockUser user;

    setUp(() async {
      await clearTestData();
      SharedPreferences.setMockInitialValues({});
      supabase = MockSupabaseService();
      user = MockUser();
      when(() => user.id).thenReturn('u1');
      when(() => user.email).thenReturn('u1@example.com');
      when(() => supabase.client).thenReturn(null);
      quota = QuotaService(supabase: supabase);
    });

    test('loadPackages loads rows from Supabase', () async {
      when(() => supabase.fetchPackages()).thenAnswer((_) async => [
            {
              'id': 'free',
              'name': 'Gratis',
              'price': 0,
              'scan_limit': 200,
              'max_members': 1,
              'features': ['Scan'],
              'is_popular': false,
            },
            {
              'id': 'pro',
              'name': 'Pro',
              'price': 99000,
              'scan_limit': 9000,
              'max_members': 1,
              'features': ['Semua'],
              'is_popular': true,
            },
          ]);
      await quota.loadPackages();
      expect(quota.packages, hasLength(2));
      expect(quota.packages.first.id, 'free');
      expect(quota.packages[1].name, 'Pro');
    });

    test('loadPackages handles fetch error gracefully', () async {
      when(() => supabase.fetchPackages()).thenThrow(Exception('boom'));
      await quota.loadPackages();
      expect(quota.packages, hasLength(4)); // fallback
    });

    test('migrateToUserScopedKeys copies legacy keys for logged-in user', () async {
      when(() => supabase.currentUser).thenReturn(user);
      final prefs = await SharedPreferences.getInstance();
      // Legacy (non user-scoped) values.
      await prefs.setString('storage_tier', 'pro');
      await prefs.setInt('subscription_cycle_allowance', 9000);
      await prefs.setBool('save_photo', false);

      await quota.migrateToUserScopedKeys();

      expect(prefs.getString('storage_tier_u1'), 'pro');
      expect(prefs.getInt('subscription_cycle_allowance_u1'), 9000);
      expect(prefs.getBool('save_photo_u1'), false);
      expect(prefs.getBool('_migrated_u1'), isTrue);
    });

    test('migrateToUserScopedKeys is idempotent', () async {
      when(() => supabase.currentUser).thenReturn(user);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('_migrated_u1', true);
      await prefs.setString('storage_tier', 'pro');

      await quota.migrateToUserScopedKeys();
      // Already migrated → legacy key is NOT copied again.
      expect(prefs.getString('storage_tier_u1'), isNull);
    });

    test('getUsedBytes uses cloud-reported storage_used', () async {
      when(() => supabase.currentUser).thenReturn(user);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('cloud_storage_used_u1', 12345);
      expect(await quota.getUsedBytes(), 12345);
    });

    test('getRemainingBytes for paid tier', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('storage_tier_anon', 'basic');
      await prefs.setInt('cloud_storage_used_anon', 1000);
      expect(await quota.getRemainingBytes(), (2 * 1024 * 1024 * 1024) - 1000);
    });

    test('isCloudStorageFull true when over limit', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('storage_tier_anon', 'basic');
      await prefs.setInt('cloud_storage_used_anon', 3 * 1024 * 1024 * 1024);
      expect(await quota.isCloudStorageFull(), isTrue);
    });

    test('evictOldPhotosIfNeeded returns 0 when within limit', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('storage_tier_anon', 'basic');
      await prefs.setInt('cloud_storage_used_anon', 100);
      expect(await quota.evictOldPhotosIfNeeded(), 0);
    });

    test('syncFromCloud returns early when not logged in', () async {
      when(() => supabase.currentUser).thenReturn(null);
      await expectLater(quota.syncFromCloud(), completes);
    });

    test('syncFromCloud initializes cycle when cloud has no subscription', () async {
      when(() => supabase.currentUser).thenReturn(user);
      when(() => supabase.fetchMySubscription()).thenAnswer((_) async => null);
      when(() => supabase.claimSubscriptionByEmail()).thenAnswer((_) async {});

      await quota.syncFromCloud();
      expect(await quota.getTier(), StorageTier.free);
      expect(await quota.getCycleAllowance(), 200);
    });

    test('syncFromCloud applies cloud tier and allowance', () async {
      when(() => supabase.currentUser).thenReturn(user);
      when(() => supabase.fetchMySubscription()).thenAnswer((_) async => {
            'tier': 'pro',
            'cycle_allowance': 9000,
            'cycle_used': 42,
            'active_from':
                DateTime.now().toIso8601String(),
            'active_until':
                DateTime.now().add(const Duration(days: 30)).toIso8601String(),
          });

      await quota.syncFromCloud();
      expect(await quota.getTier(), StorageTier.pro);
      expect(await quota.getCycleAllowance(), 9000);
      expect(await quota.getUsedInCurrentCycle(), 42);
    });

    test('syncFromCloud skips pending cloud tier', () async {
      when(() => supabase.currentUser).thenReturn(user);
      when(() => supabase.fetchMySubscription()).thenAnswer((_) async => {
            'tier': 'pending',
          });

      await quota.syncFromCloud();
      expect(await quota.getTier(), StorageTier.free); // local unchanged
    });

    test('syncFromCloud does not downgrade local tier', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('storage_tier_u1', 'pro');

      when(() => supabase.currentUser).thenReturn(user);
      when(() => supabase.fetchMySubscription()).thenAnswer((_) async => {
            'tier': 'basic',
            'cycle_allowance': 3000,
          });

      await quota.syncFromCloud();
      expect(await quota.getTier(), StorageTier.pro); // not downgraded
    });

    test('syncToCloud does nothing when not logged in', () async {
      when(() => supabase.currentUser).thenReturn(null);
      await expectLater(quota.syncToCloud(), completes);
    });
  });
}
