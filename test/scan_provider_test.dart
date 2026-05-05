import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/features/scan/scan_provider.dart';
import 'package:scanorder/services/quota_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScanResult', () {
    test('creates with required fields', () {
      final result = ScanResult(
        status: ScanStatus.success,
        resi: 'SPX123',
        marketplace: 'Shopee',
      );
      expect(result.status, ScanStatus.success);
      expect(result.resi, 'SPX123');
      expect(result.marketplace, 'Shopee');
      expect(result.existingOrder, isNull);
    });

    test('creates with existing order', () {
      final result = ScanResult(
        status: ScanStatus.duplicate,
        resi: 'SPX123',
        marketplace: 'Shopee',
        existingOrder: null,
      );
      expect(result.status, ScanStatus.duplicate);
    });
  });

  group('ScanStatus', () {
    test('has all expected values', () {
      expect(ScanStatus.values.length, 6);
      expect(ScanStatus.values, contains(ScanStatus.idle));
      expect(ScanStatus.values, contains(ScanStatus.success));
      expect(ScanStatus.values, contains(ScanStatus.duplicate));
      expect(ScanStatus.values, contains(ScanStatus.recentRepeat));
      expect(ScanStatus.values, contains(ScanStatus.quotaExceeded));
      expect(ScanStatus.values, contains(ScanStatus.noCategory));
    });
  });

  group('ScanProvider', () {
    test('initial values', () {
      final provider = ScanProvider();
      expect(provider.lastResult, isNull);
      expect(provider.todayCount, 0);
      expect(provider.totalCount, 0);
      expect(provider.remainingScans, 0);
      expect(provider.scanLimit, 0);
      expect(provider.currentTier, StorageTier.free);
      expect(provider.categories, isEmpty);
      expect(provider.activeCategoryId, isNull);
    });

    test('dispose does not throw', () {
      final provider = ScanProvider();
      expect(() => provider.dispose(), returnsNormally);
    });
  });
}
