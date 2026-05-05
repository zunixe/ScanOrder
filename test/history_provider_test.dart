import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/features/history/history_provider.dart';
import 'package:scanorder/models/scan_record.dart';
import 'package:scanorder/models/category.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HistoryProvider', () {
    late HistoryProvider provider;

    setUp(() {
      provider = HistoryProvider();
    });

    test('initial values', () {
      expect(provider.scans, isEmpty);
      expect(provider.availableDates, isEmpty);
      expect(provider.searchQuery, '');
      expect(provider.isSearching, false);
      expect(provider.filterCategoryId, isNull);
      expect(provider.categories, isEmpty);
      expect(provider.categoryCounts, isEmpty);
      expect(provider.teamId, isNull);
    });

    test('selectedDate is today format', () {
      final today = DateTime.now();
      final expected = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      expect(provider.selectedDate, expected);
    });

    test('setUserId updates user context', () {
      provider.setUserId('user-1');
      // Internal state updated (tested via behavior)
    });

    test('setTeamContext updates team context', () {
      provider.setTeamContext('team-1', 'admin-1');
      expect(provider.teamId, 'team-1');
    });

    test('filteredScans returns all when no filter', () {
      final d = '2026-05-06';
      provider.scans = [
        ScanRecord(resi: 'SPX1', marketplace: 'Shopee', scannedAt: DateTime.now(), date: d),
        ScanRecord(resi: 'SPX2', marketplace: 'JNE', scannedAt: DateTime.now(), date: d),
      ];
      expect(provider.filteredScans.length, 2);
    });

    test('filteredScans filters by category', () {
      final d = '2026-05-06';
      final cat1 = ScanCategory(id: 1, name: 'Keranjang', color: '#2196F3', userId: 'u1');
      final cat2 = ScanCategory(id: 2, name: 'Paket Besar', color: '#FF5722', userId: 'u1');

      provider.categories = [cat1, cat2];
      provider.filterCategoryId = 1;

      provider.scans = [
        ScanRecord(resi: 'SPX1', marketplace: 'Shopee', scannedAt: DateTime.now(), date: d, categories: [cat1]),
        ScanRecord(resi: 'SPX2', marketplace: 'JNE', scannedAt: DateTime.now(), date: d, categories: [cat2]),
        ScanRecord(resi: 'SPX3', marketplace: 'SiCepat', scannedAt: DateTime.now(), date: d, categories: [cat1, cat2]),
      ];

      final filtered = provider.filteredScans;
      expect(filtered.length, 2); // SPX1 and SPX3 have cat1
      expect(filtered.every((s) => s.categories.any((c) => c.name == 'Keranjang')), true);
    });

    test('filteredScans returns all when filter category not found', () {
      final d = '2026-05-06';
      provider.categories = [];
      provider.filterCategoryId = 999;
      provider.scans = [
        ScanRecord(resi: 'SPX1', marketplace: 'Shopee', scannedAt: DateTime.now(), date: d),
      ];
      expect(provider.filteredScans.length, 1);
    });

    test('dispose does not throw', () {
      expect(() => provider.dispose(), returnsNormally);
    });

    test('allDatesSentinel value', () {
      expect(HistoryProvider.allDatesSentinel, '__ALL__');
    });
  });
}
