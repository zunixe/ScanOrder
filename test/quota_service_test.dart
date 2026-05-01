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
}
