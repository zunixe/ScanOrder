import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scanorder/core/db/database_helper.dart';
import 'package:scanorder/core/state/async_state.dart';
import 'package:scanorder/core/supabase/supabase_service.dart';
import 'package:scanorder/features/history/history_provider.dart';
import 'package:scanorder/models/category.dart';
import 'package:scanorder/models/scan_record.dart';

import 'helpers/test_db.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(setupTestDatabase);
  tearDownAll(teardownTestDatabase);

  group('HistoryProvider', () {
    late DatabaseHelper db;
    late MockSupabaseService supabase;
    late HistoryProvider provider;

    String isoDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    setUp(() async {
      await clearTestData();
      db = DatabaseHelper.instance;
      supabase = MockSupabaseService();
      when(() => supabase.currentUser).thenReturn(null);
      when(() => supabase.client).thenReturn(null);
      when(() => supabase.deleteScanByResi(any())).thenAnswer((_) async {});
      provider = HistoryProvider(database: db, supabase: supabase);
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
      expect(provider.scansState, isA<AsyncState<void>>());
      expect(provider.datesState, isA<AsyncState<void>>());
    });

    test('selectedDate is today format', () {
      final today = DateTime.now();
      expect(provider.selectedDate, isoDate(today));
    });

    test('setUserId / setTeamContext update context', () {
      provider.setUserId('user-1');
      provider.setTeamContext('team-1', 'admin-1');
      expect(provider.teamId, 'team-1');
    });

    test('allDatesSentinel value', () {
      expect(HistoryProvider.allDatesSentinel, '__ALL__');
    });

    test('dispose does not throw', () {
      expect(() => provider.dispose(), returnsNormally);
    });

    group('loadScans (personal mode)', () {
      test('loads scans for today', () async {
        final today = isoDate(DateTime.now());
        await db.insertScan(ScanRecord(
          resi: 'SPX1',
          marketplace: 'Shopee',
          scannedAt: DateTime.now(),
          date: today,
        ));
        await provider.loadScans();
        expect(provider.scans, hasLength(1));
        expect(provider.scansState, isA<AsyncState<void>>());
      });

      test('loads all scans with sentinel date', () async {
        final today = isoDate(DateTime.now());
        await db.insertScan(ScanRecord(resi: 'SPX1', marketplace: 'Shopee', scannedAt: DateTime.now(), date: today));
        await db.insertScan(ScanRecord(resi: 'SPX2', marketplace: 'JNE', scannedAt: DateTime.now(), date: '2020-01-01'));
        provider.selectedDate = HistoryProvider.allDatesSentinel;
        await provider.loadScans();
        expect(provider.scans, hasLength(2));
      });

      test('search filters by resi substring', () async {
        final today = isoDate(DateTime.now());
        await db.insertScan(ScanRecord(resi: 'SPXAAA', marketplace: 'Shopee', scannedAt: DateTime.now(), date: today));
        await db.insertScan(ScanRecord(resi: 'JNEBBB', marketplace: 'JNE', scannedAt: DateTime.now(), date: today));
        await provider.search('AAA');
        expect(provider.isSearching, isTrue);
        expect(provider.scans, hasLength(1));
        expect(provider.scans.first.resi, 'SPXAAA');
      });

      test('scans carry attached categories', () async {
        final today = isoDate(DateTime.now());
        final catId = await db.insertCategory(ScanCategory(name: 'Keranjang', color: '#000', userId: null));
        final orderId = await db.insertScan(
          ScanRecord(resi: 'SPXCAT', marketplace: 'Shopee', scannedAt: DateTime.now(), date: today),
        );
        await db.assignCategoryToOrder(orderId, catId);
        await provider.loadScans();
        expect(provider.scans.first.categories, hasLength(1));
      });
    });

    group('loadDates', () {
      test('loads distinct dates and auto-selects first', () async {
        await db.insertScan(ScanRecord(resi: 'SPX1', marketplace: 'Shopee', scannedAt: DateTime.now(), date: '2021-03-03'));
        provider.selectedDate = '1999-01-01';
        await provider.loadDates();
        expect(provider.availableDates, contains('2021-03-03'));
        expect(provider.selectedDate, '2021-03-03');
      });

      test('keeps sentinel when set to ALL', () async {
        await db.insertScan(ScanRecord(resi: 'SPX1', marketplace: 'Shopee', scannedAt: DateTime.now(), date: '2021-03-03'));
        provider.selectedDate = HistoryProvider.allDatesSentinel;
        await provider.loadDates();
        expect(provider.selectedDate, HistoryProvider.allDatesSentinel);
      });
    });

    group('setDate', () {
      test('resets search and reloads scans', () async {
        await provider.search('something');
        expect(provider.searchQuery, 'something');
        await provider.setDate('2020-05-05');
        expect(provider.selectedDate, '2020-05-05');
        expect(provider.searchQuery, '');
        expect(provider.isSearching, isFalse);
      });
    });

    group('deleteScan', () {
      test('deletes from DB and reloads', () async {
        final today = isoDate(DateTime.now());
        final id = await db.insertScan(
          ScanRecord(resi: 'SPXDEL', marketplace: 'Shopee', scannedAt: DateTime.now(), date: today),
        );
        provider.selectedDate = HistoryProvider.allDatesSentinel;
        await provider.loadScans();
        expect(provider.scans, hasLength(1));

        await provider.deleteScan(id);
        expect(provider.scans, isEmpty);
        expect(await db.findByResi('SPXDEL'), isNull);
      });
    });

    group('loadCategories', () {
      test('loads categories and counts', () async {
        await db.insertCategory(ScanCategory(name: 'A', color: '#000', userId: null));
        await provider.loadCategories();
        expect(provider.categories, hasLength(1));
        expect(provider.categoryCounts, isNotEmpty);
        expect(provider.categoriesLoadState, isA<AsyncState<void>>());
      });
    });

    group('updatePhoto', () {
      test('persists new photo and updates memory', () async {
        final today = isoDate(DateTime.now());
        final id = await db.insertScan(
          ScanRecord(resi: 'SPXPIC', marketplace: 'Shopee', scannedAt: DateTime.now(), date: today),
        );
        provider.selectedDate = HistoryProvider.allDatesSentinel;
        await provider.loadScans();

        await provider.updatePhoto(id, '/tmp/new.jpg');
        expect(provider.scans.first.photoPath, '/tmp/new.jpg');
        final fromDb = await db.getScanById(id);
        expect(fromDb!.photoPath, '/tmp/new.jpg');
      });

      test('updatePhotoLocal updates memory without DB write', () async {
        final today = isoDate(DateTime.now());
        final id = await db.insertScan(
          ScanRecord(resi: 'SPXPIC2', marketplace: 'Shopee', scannedAt: DateTime.now(), date: today),
        );
        provider.selectedDate = HistoryProvider.allDatesSentinel;
        await provider.loadScans();

        provider.updatePhotoLocal(id, '/local/path.jpg');
        expect(provider.scans.first.photoPath, '/local/path.jpg');
        final fromDb = await db.getScanById(id);
        expect(fromDb!.photoPath, isNull);
      });
    });

    group('getAllForExport', () {
      test('returns all scans with categories attached', () async {
        final catId = await db.insertCategory(ScanCategory(name: 'Exp', color: '#000', userId: null));
        final orderId = await db.insertScan(
          ScanRecord(resi: 'SPXEXP', marketplace: 'Shopee', scannedAt: DateTime.now(), date: '2022-02-02'),
        );
        await db.assignCategoryToOrder(orderId, catId);

        final all = await provider.getAllForExport();
        expect(all, hasLength(1));
        expect(all.first.categories, hasLength(1));
      });
    });

    group('filteredScans', () {
      test('returns all when no filter', () {
        provider.scans = [
          ScanRecord(resi: 'SPX1', marketplace: 'Shopee', scannedAt: DateTime.now(), date: '2026-05-06'),
          ScanRecord(resi: 'SPX2', marketplace: 'JNE', scannedAt: DateTime.now(), date: '2026-05-06'),
        ];
        expect(provider.filteredScans, hasLength(2));
      });

      test('filters by category name and user', () {
        final cat1 = ScanCategory(id: 1, name: 'Keranjang', color: '#000', userId: 'u1');
        final cat2 = ScanCategory(id: 2, name: 'Besar', color: '#111', userId: 'u1');
        provider.categories = [cat1, cat2];
        provider.filterCategoryId = 1;
        provider.scans = [
          ScanRecord(resi: 'SPX1', marketplace: 'Shopee', scannedAt: DateTime.now(), date: 'd', categories: [cat1]),
          ScanRecord(resi: 'SPX2', marketplace: 'JNE', scannedAt: DateTime.now(), date: 'd', categories: [cat2]),
        ];
        expect(provider.filteredScans, hasLength(1));
        expect(provider.filteredScans.first.resi, 'SPX1');
      });

      test('returns all when filter category not found', () {
        provider.categories = [];
        provider.filterCategoryId = 999;
        provider.scans = [
          ScanRecord(resi: 'SPX1', marketplace: 'Shopee', scannedAt: DateTime.now(), date: 'd'),
        ];
        expect(provider.filteredScans, hasLength(1));
      });
    });

    group('setFilterCategory (personal)', () {
      test('reloads scans when filter cleared', () async {
        provider.setFilterCategory(null);
        await Future<void>.delayed(Duration.zero);
        expect(provider.filterCategoryId, isNull);
      });
    });

    group('refresh', () {
      test('loads dates, scans and categories', () async {
        final today = isoDate(DateTime.now());
        await db.insertScan(ScanRecord(resi: 'SPXR', marketplace: 'Shopee', scannedAt: DateTime.now(), date: today));
        await provider.refresh();
        expect(provider.scans, hasLength(1));
        expect(provider.datesState, isA<AsyncState<void>>());
      });
    });
  });
}
