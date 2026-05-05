import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqflite.dart' show databaseFactoryOrNull;
import 'package:scanorder/core/db/database_helper.dart';
import 'package:scanorder/models/scan_record.dart';
import 'package:scanorder/models/category.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactoryOrNull = databaseFactoryFfi;
    DatabaseHelper.setTestMode(true);
  });

  group('DatabaseHelper', () {
    late DatabaseHelper db;

    setUp(() async {
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('scan_categories');
      await database.delete('categories');
      await database.delete('scans');
    });

    group('Scans CRUD', () {
      test('insertScan and findByResi', () async {
        final now = DateTime.now();
        final record = ScanRecord(
          resi: 'SPX123456789',
          marketplace: 'Shopee',
          scannedAt: now,
          date: now.toIso8601String().substring(0, 10),
        );
        await db.insertScan(record, userId: 'user1');
        final found = await db.findByResi('SPX123456789', userId: 'user1');
        expect(found, isNotNull);
        expect(found!.resi, 'SPX123456789');
        expect(found.marketplace, 'Shopee');
      });

      test('same resi different userId is allowed', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'SPXBBB', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'user1');
        await db.insertScan(ScanRecord(resi: 'SPXBBB', marketplace: 'JNE', scannedAt: now, date: date), userId: 'user2');

        final found1 = await db.findByResi('SPXBBB', userId: 'user1');
        expect(found1?.marketplace, 'Shopee');
        final found2 = await db.findByResi('SPXBBB', userId: 'user2');
        expect(found2?.marketplace, 'JNE');
      });

      test('getAllScans returns only user scans (no team)', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'SPX1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'user1');
        await db.insertScan(ScanRecord(resi: 'SPX2', marketplace: 'JNE', scannedAt: now, date: date), userId: 'user1');
        await db.insertScan(ScanRecord(resi: 'SPX3', marketplace: 'J&T', scannedAt: now, date: date), userId: 'user2');

        final user1Scans = await db.getAllScans(userId: 'user1');
        expect(user1Scans.length, 2);
      });

      test('deleteScan removes scan', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'SPXDEL', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        final found = await db.findByResi('SPXDEL', userId: 'u1');
        expect(found, isNotNull);

        await db.deleteScan(found!.id!);
        final afterDelete = await db.findByResi('SPXDEL', userId: 'u1');
        expect(afterDelete, isNull);
      });

      test('updateOrderSyncStatusByResi', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'SPXSYNC', marketplace: 'Shopee', scannedAt: now, date: date, syncStatus: 'pending'), userId: 'u1');
        await db.updateOrderSyncStatusByResi('SPXSYNC', 'synced', userId: 'u1');

        final found = await db.findByResi('SPXSYNC', userId: 'u1');
        expect(found?.syncStatus, 'synced');
      });

      test('getDailyStats returns correct counts', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'SPXD1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        await db.insertScan(ScanRecord(resi: 'SPXD2', marketplace: 'JNE', scannedAt: now, date: date), userId: 'u1');

        final stats = await db.getDailyStats(7, userId: 'u1');
        expect(stats[date], 2);
      });

      test('getTotalOrderCount', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'SPXC1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        await db.insertScan(ScanRecord(resi: 'SPXC2', marketplace: 'JNE', scannedAt: now, date: date), userId: 'u1');

        final count = await db.getTotalOrderCount(userId: 'u1');
        expect(count, 2);
      });

      test('searchScans', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'SPXSEARCH1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        await db.insertScan(ScanRecord(resi: 'JNESEARCH2', marketplace: 'JNE', scannedAt: now, date: date), userId: 'u1');

        final results = await db.searchScans('SEARCH', userId: 'u1');
        expect(results.length, 2);
      });

      test('getMarketplaceStats', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'SPXM1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        await db.insertScan(ScanRecord(resi: 'SPXM2', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        await db.insertScan(ScanRecord(resi: 'JNEM1', marketplace: 'JNE', scannedAt: now, date: date), userId: 'u1');

        final stats = await db.getMarketplaceStats(userId: 'u1');
        expect(stats['Shopee'], 2);
        expect(stats['JNE'], 1);
      });
    });

    group('Categories CRUD', () {
      test('insertCategory and getAllCategories', () async {
        final cat = ScanCategory(name: 'Pakaian', color: '#FF5722', userId: 'u1');
        await db.insertCategory(cat);

        final cats = await db.getAllCategories(userId: 'u1');
        expect(cats.length, 1);
        expect(cats.first.name, 'Pakaian');
      });

      test('deleteCategory removes category', () async {
        final cat = ScanCategory(name: 'Test', color: '#000', userId: 'u1');
        final id = await db.insertCategory(cat);
        await db.deleteCategory(id);

        final cats = await db.getAllCategories(userId: 'u1');
        expect(cats.length, 0);
      });

      test('getCategoryById returns correct category', () async {
        final cat = ScanCategory(name: 'Elektronik', color: '#2196F3', userId: 'u1');
        final id = await db.insertCategory(cat);

        final found = await db.getCategoryById(id);
        expect(found, isNotNull);
        expect(found!.name, 'Elektronik');
      });

      test('insertCategory prevents duplicate name+userId', () async {
        await db.insertCategory(ScanCategory(name: 'Pakaian', color: '#FF5722', userId: 'u1'));
        await db.insertCategory(ScanCategory(name: 'Pakaian', color: '#FF5722', userId: 'u1'));

        final cats = await db.getAllCategories(userId: 'u1');
        expect(cats.length, 1);
      });
    });

    group('Scan-Categories junction', () {
      test('assignCategoryToOrder and getCategoriesForOrder', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'SPXCAT', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        final scan = await db.findByResi('SPXCAT', userId: 'u1');

        final catId = await db.insertCategory(ScanCategory(name: 'Pakaian', color: '#FF5722', userId: 'u1'));
        await db.assignCategoryToOrder(scan!.id!, catId);

        final cats = await db.getCategoriesForOrder(scan.id!);
        expect(cats.length, 1);
        expect(cats.first.name, 'Pakaian');
      });

      test('isOrderInCategory returns true when assigned', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'SPXCHK', marketplace: 'JNE', scannedAt: now, date: date), userId: 'u1');
        final scan = await db.findByResi('SPXCHK', userId: 'u1');
        final catId = await db.insertCategory(ScanCategory(name: 'Test', color: '#000', userId: 'u1'));
        await db.assignCategoryToOrder(scan!.id!, catId);

        final isInCat = await db.isOrderInCategory('SPXCHK', catId, userId: 'u1');
        expect(isInCat, isTrue);
      });

      test('removeCategoryFromOrder', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'SPXRM', marketplace: 'JNE', scannedAt: now, date: date), userId: 'u1');
        final scan = await db.findByResi('SPXRM', userId: 'u1');
        final catId = await db.insertCategory(ScanCategory(name: 'Remove', color: '#000', userId: 'u1'));
        await db.assignCategoryToOrder(scan!.id!, catId);

        await db.removeCategoryFromOrder(scan.id!, catId);
        final cats = await db.getCategoriesForOrder(scan.id!);
        expect(cats.length, 0);
      });
    });

    group('Team scans', () {
      test('insertScan with teamId', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(
          ScanRecord(resi: 'SPXTEAM', marketplace: 'Shopee', scannedAt: now, date: date),
          userId: 'u1',
          teamId: 'team1',
        );

        final count = await db.getTotalOrderCount(teamId: 'team1');
        expect(count, 1);
      });

      test('getScansByDate with teamId', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'SPXT1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1', teamId: 'team1');
        await db.insertScan(ScanRecord(resi: 'SPXP', marketplace: 'J&T', scannedAt: now, date: date), userId: 'u1');

        final teamScans = await db.getScansByDate(date, teamId: 'team1');
        expect(teamScans.length, 1);
        expect(teamScans.first.resi, 'SPXT1');
      });
    });

    group('Additional queries', () {
      test('getOrderCountByDate', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'CNT1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        await db.insertScan(ScanRecord(resi: 'CNT2', marketplace: 'JNE', scannedAt: now, date: date), userId: 'u1');
        await db.insertScan(ScanRecord(resi: 'CNT3', marketplace: 'J&T', scannedAt: now, date: '2026-01-01'), userId: 'u1');

        final count = await db.getOrderCountByDate(date, userId: 'u1');
        expect(count, 2);
      });

      test('getDistinctDates', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'DT1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        await db.insertScan(ScanRecord(resi: 'DT2', marketplace: 'JNE', scannedAt: now, date: date), userId: 'u1');
        await db.insertScan(ScanRecord(resi: 'DT3', marketplace: 'J&T', scannedAt: now, date: '2026-01-01'), userId: 'u1');

        final dates = await db.getDistinctDates(userId: 'u1');
        expect(dates.length, 2);
      });

      test('updateScanPhoto', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'PHOTO1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        final scan = await db.findByResi('PHOTO1', userId: 'u1');

        await db.updateScanPhoto(scan!.id!, '/new/photo.jpg');
        final updated = await db.findByResi('PHOTO1', userId: 'u1');
        expect(updated!.photoPath, '/new/photo.jpg');
      });

      test('updateScanPhoto to null', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'PHOTO2', marketplace: 'Shopee', scannedAt: now, date: date, photoPath: '/old.jpg'), userId: 'u1');
        final scan = await db.findByResi('PHOTO2', userId: 'u1');

        await db.updateScanPhoto(scan!.id!, null);
        final updated = await db.findByResi('PHOTO2', userId: 'u1');
        expect(updated!.photoPath, isNull);
      });

      test('searchScans with teamId', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'TEAMSEARCH1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1', teamId: 'team1');
        await db.insertScan(ScanRecord(resi: 'PERSONALSEARCH', marketplace: 'JNE', scannedAt: now, date: date), userId: 'u1');

        final results = await db.searchScans('SEARCH', teamId: 'team1');
        expect(results.length, 1);
        expect(results.first.resi, 'TEAMSEARCH1');
      });

      test('updateOrderSyncStatusByResi with teamId', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'TEAMSYNC', marketplace: 'Shopee', scannedAt: now, date: date, syncStatus: 'pending'), userId: 'u1', teamId: 'team1');
        await db.updateOrderSyncStatusByResi('TEAMSYNC', 'synced', teamId: 'team1');

        final scans = await db.getScansByDate(date, teamId: 'team1');
        expect(scans.first.syncStatus, 'synced');
      });

      test('getMarketplaceStats with date filter', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'MS1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        await db.insertScan(ScanRecord(resi: 'MS2', marketplace: 'JNE', scannedAt: now, date: '2026-01-01'), userId: 'u1');

        final stats = await db.getMarketplaceStats(date: date, userId: 'u1');
        expect(stats.length, 1);
        expect(stats['Shopee'], 1);
      });

      test('getCategoryStats', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        final scanId = await db.insertScan(ScanRecord(resi: 'CATSTAT', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        final catId = await db.insertCategory(ScanCategory(name: 'StatCat', color: '#000', userId: 'u1'));
        await db.assignCategoryToOrder(scanId, catId);

        final stats = await db.getCategoryStats(userId: 'u1');
        expect(stats, isNotEmpty);
        expect(stats['StatCat'], 1);
      });

      test('updateCategory', () async {
        final catId = await db.insertCategory(ScanCategory(name: 'Old', color: '#000', userId: 'u1'));
        final cat = await db.getCategoryById(catId);
        await db.updateCategory(ScanCategory(id: catId, name: 'Updated', color: '#FFF', userId: 'u1', createdAt: cat!.createdAt));
        final updated = await db.getCategoryById(catId);
        expect(updated!.name, 'Updated');
        expect(updated.color, '#FFF');
      });

      test('getScansByCategory', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        final scanId = await db.insertScan(ScanRecord(resi: 'CATSCAN', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        final catId = await db.insertCategory(ScanCategory(name: 'CatA', color: '#000', userId: 'u1'));
        await db.assignCategoryToOrder(scanId, catId);

        final scans = await db.getScansByCategory(catId, userId: 'u1');
        expect(scans.length, 1);
        expect(scans.first.resi, 'CATSCAN');
      });

      test('getCategoryCounts', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        final s1 = await db.insertScan(ScanRecord(resi: 'CC1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        final s2 = await db.insertScan(ScanRecord(resi: 'CC2', marketplace: 'JNE', scannedAt: now, date: date), userId: 'u1');
        final catId = await db.insertCategory(ScanCategory(name: 'CCCat', color: '#000', userId: 'u1'));
        await db.assignCategoryToOrder(s1, catId);
        await db.assignCategoryToOrder(s2, catId);

        final counts = await db.getCategoryCounts(userId: 'u1');
        expect(counts[catId], 2);
      });

      test('getAllScanCategoriesWithResi', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        final scanId = await db.insertScan(ScanRecord(resi: 'ASC1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        final catId = await db.insertCategory(ScanCategory(name: 'ASCCat', color: '#000', userId: 'u1'));
        await db.assignCategoryToOrder(scanId, catId);

        final result = await db.getAllScanCategoriesWithResi();
        expect(result, isNotEmpty);
        expect(result.first['resi'], 'ASC1');
      });

      test('deleteTeamOrders', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'TEAM1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1', teamId: 'team1');
        await db.insertScan(ScanRecord(resi: 'PERS1', marketplace: 'JNE', scannedAt: now, date: date), userId: 'u1');

        await db.deleteTeamOrders('u1');
        final teamScans = await db.getTeamScans();
        expect(teamScans, isEmpty);
        // Personal scan should remain
        final personal = await db.getAllScans(userId: 'u1');
        expect(personal.length, 1);
      });

      test('getTeamScans', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'TSCAN1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1', teamId: 'team1');

        final teamScans = await db.getTeamScans();
        expect(teamScans.length, 1);
        expect(teamScans.first.resi, 'TSCAN1');
      });

      test('deleteTeamCategories', () async {
        await db.insertCategory(ScanCategory(name: 'MyCat', color: '#000', userId: 'u1'));
        await db.insertCategory(ScanCategory(name: 'AdminCat', color: '#FFF', userId: 'admin1'));

        await db.deleteTeamCategories('u1');
        final cats = await db.getAllCategories(userId: 'u1');
        expect(cats.length, 1);
        expect(cats.first.name, 'MyCat');
      });

      test('deleteAllScans', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'DEL1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        await db.insertScan(ScanRecord(resi: 'DEL2', marketplace: 'JNE', scannedAt: now, date: date), userId: 'u1');

        await db.deleteAllScans();
        final count = await db.getTotalOrderCount(userId: 'u1');
        expect(count, 0);
      });

      test('updateTeamIdForUser', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'TEAMUP', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');

        await db.updateTeamIdForUser('u1', 'team1');
        final teamScans = await db.getTeamScans();
        expect(teamScans.any((s) => s.resi == 'TEAMUP'), true);
      });

      test('deleteOrphanPersonalScans', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        await db.insertScan(ScanRecord(resi: 'ORPHAN1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        await db.insertScan(ScanRecord(resi: 'TEAMSCAN', marketplace: 'JNE', scannedAt: now, date: date), userId: 'u1', teamId: 'team1');

        final deleted = await db.deleteOrphanPersonalScans('u1');
        expect(deleted, 1);
        // Team scan should remain
        final teamScans = await db.getTeamScans();
        expect(teamScans.length, 1);
      });

      test('deleteCategory removes associated orphan scans', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        final scanId = await db.insertScan(ScanRecord(resi: 'DELCAT', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        final catId = await db.insertCategory(ScanCategory(name: 'DelCat', color: '#000', userId: 'u1'));
        await db.assignCategoryToOrder(scanId, catId);

        await db.deleteCategory(catId);
        final scan = await db.findByResi('DELCAT', userId: 'u1');
        // Scan should be deleted since it was only in this category
        expect(scan, isNull);
      });

      test('deleteCategory keeps scans in other categories', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        final scanId = await db.insertScan(ScanRecord(resi: 'KEEPCAT', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1');
        final cat1 = await db.insertCategory(ScanCategory(name: 'Cat1', color: '#000', userId: 'u1'));
        final cat2 = await db.insertCategory(ScanCategory(name: 'Cat2', color: '#FFF', userId: 'u1'));
        await db.assignCategoryToOrder(scanId, cat1);
        await db.assignCategoryToOrder(scanId, cat2);

        await db.deleteCategory(cat1);
        final scan = await db.findByResi('KEEPCAT', userId: 'u1');
        expect(scan, isNotNull);
      });

      test('getAllCategories with adminUserId for team', () async {
        await db.insertCategory(ScanCategory(name: 'MyCat', color: '#000', userId: 'u1'));
        await db.insertCategory(ScanCategory(name: 'AdminCat', color: '#FFF', userId: 'admin1'));

        final cats = await db.getAllCategories(userId: 'u1', adminUserId: 'admin1');
        expect(cats.length, 2);
      });

      test('getScansByCategory with teamId', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        final scanId = await db.insertScan(ScanRecord(resi: 'TCAT1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1', teamId: 'team1');
        final catId = await db.insertCategory(ScanCategory(name: 'TCat', color: '#000', userId: 'u1'));
        await db.assignCategoryToOrder(scanId, catId);

        final scans = await db.getScansByCategory(catId, teamId: 'team1');
        expect(scans.length, 1);
      });

      test('getCategoryStats with teamId', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        final scanId = await db.insertScan(ScanRecord(resi: 'TCS1', marketplace: 'Shopee', scannedAt: now, date: date), userId: 'u1', teamId: 'team1');
        final catId = await db.insertCategory(ScanCategory(name: 'TCatStat', color: '#000', userId: 'u1'));
        await db.assignCategoryToOrder(scanId, catId);

        final stats = await db.getCategoryStats(teamId: 'team1');
        expect(stats, isNotEmpty);
      });

      test('insertScan with scannedBy', () async {
        final now = DateTime.now();
        final date = now.toIso8601String().substring(0, 10);
        final id = await db.insertScan(
          ScanRecord(resi: 'SBY1', marketplace: 'Shopee', scannedAt: now, date: date),
          userId: 'u1',
          scannedBy: 'scanner1',
        );
        expect(id, greaterThan(0));
      });
    });
  });
}
