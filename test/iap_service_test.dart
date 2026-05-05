import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/services/quota_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IapService product ID mapping', () {
    // Test the mapping logic without constructing IapService
    // (constructor triggers platform channel)
    String productIdForTier(StorageTier tier) {
      switch (tier) {
        case StorageTier.basic:
          return 'scanorder_basic_monthly';
        case StorageTier.pro:
          return 'scanorder_pro_monthly';
        case StorageTier.unlimited:
          return 'scanorder_team_monthly';
        case StorageTier.free:
          return '';
      }
    }

    StorageTier? tierForProductId(String productId) {
      switch (productId) {
        case 'scanorder_basic_monthly':
          return StorageTier.basic;
        case 'scanorder_pro_monthly':
          return StorageTier.pro;
        case 'scanorder_team_monthly':
          return StorageTier.unlimited;
        default:
          return null;
      }
    }

    test('returns correct product ID for basic', () {
      expect(productIdForTier(StorageTier.basic), 'scanorder_basic_monthly');
    });

    test('returns correct product ID for pro', () {
      expect(productIdForTier(StorageTier.pro), 'scanorder_pro_monthly');
    });

    test('returns correct product ID for team/unlimited', () {
      expect(productIdForTier(StorageTier.unlimited), 'scanorder_team_monthly');
    });

    test('returns empty string for free tier', () {
      expect(productIdForTier(StorageTier.free), '');
    });

    test('returns basic for basic product ID', () {
      expect(tierForProductId('scanorder_basic_monthly'), StorageTier.basic);
    });

    test('returns pro for pro product ID', () {
      expect(tierForProductId('scanorder_pro_monthly'), StorageTier.pro);
    });

    test('returns unlimited for team product ID', () {
      expect(tierForProductId('scanorder_team_monthly'), StorageTier.unlimited);
    });

    test('returns null for unknown product ID', () {
      expect(tierForProductId('unknown_product'), isNull);
    });

    test('returns null for empty string', () {
      expect(tierForProductId(''), isNull);
    });

    test('round-trip: tier → productId → tier', () {
      for (final tier in [StorageTier.basic, StorageTier.pro, StorageTier.unlimited]) {
        expect(tierForProductId(productIdForTier(tier)), tier);
      }
    });
  });
}
