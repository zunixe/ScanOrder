import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/services/quota_service.dart';

void main() {
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
        id: 'free', name: 'Free', price: 0, scanLimit: 100,
        maxMembers: 1, features: [], isPopular: false,
      );
      expect(pkg.priceDisplay, 'Gratis');
    });

    test('priceDisplay formats Rp with dots', () {
      const pkg = PackageInfo(
        id: 'pro', name: 'Pro', price: 99000, scanLimit: 5000,
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
        id: 'pro', name: 'Pro', price: 99000, scanLimit: 5000,
        maxMembers: 1, features: [], isPopular: true,
      );
      expect(pkg.scanLimitDisplay, '5rb');
    });

    test('scanLimitDisplay returns number for < 1000', () {
      const pkg = PackageInfo(
        id: 'free', name: 'Free', price: 0, scanLimit: 100,
        maxMembers: 1, features: [], isPopular: false,
      );
      expect(pkg.scanLimitDisplay, '100');
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
      expect(free.scanLimit, 100);
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
      expect(quota.getScanLimitDisplay(StorageTier.free), '100');
      expect(quota.getScanLimitDisplay(StorageTier.basic), '1rb');
      expect(quota.getScanLimitDisplay(StorageTier.pro), '5rb');
      expect(quota.getScanLimitDisplay(StorageTier.unlimited), '∞');
    });
  });
}
