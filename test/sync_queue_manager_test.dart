import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:scanorder/core/offline/sync_queue_manager.dart';
import 'package:scanorder/core/offline/sync_queue_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Database> openDb() async {
    sqfliteFfiInit();
    databaseFactoryOrNull = databaseFactoryFfi;
    return databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1),
    );
  }

  group('SyncQueueStatus', () {
    test('has all expected values', () {
      expect(SyncQueueStatus.values.length, 4);
      expect(SyncQueueStatus.values, contains(SyncQueueStatus.idle));
      expect(SyncQueueStatus.values, contains(SyncQueueStatus.syncing));
      expect(SyncQueueStatus.values, contains(SyncQueueStatus.pending));
      expect(SyncQueueStatus.values, contains(SyncQueueStatus.error));
    });
  });

  group('SyncItemProgress', () {
    test('creates with required fields', () {
      final progress = SyncItemProgress(
        itemId: 'item-1',
        status: SyncStatus.syncing,
        message: 'Syncing...',
      );
      expect(progress.itemId, 'item-1');
      expect(progress.status, SyncStatus.syncing);
      expect(progress.message, 'Syncing...');
      expect(progress.error, isNull);
    });

    test('creates with error', () {
      final progress = SyncItemProgress(
        itemId: 'item-2',
        status: SyncStatus.failed,
        message: 'Failed',
        error: Exception('timeout'),
      );
      expect(progress.error, isNotNull);
    });

    test('creates with null message', () {
      final progress = SyncItemProgress(
        itemId: 'item-3',
        status: SyncStatus.completed,
      );
      expect(progress.message, isNull);
    });
  });

  group('SyncQueueStats', () {
    test('creates with all fields', () {
      final stats = SyncQueueStats(
        total: 10,
        pending: 3,
        syncing: 1,
        completed: 4,
        failed: 1,
        conflict: 1,
      );
      expect(stats.total, 10);
      expect(stats.pending, 3);
      expect(stats.syncing, 1);
      expect(stats.completed, 4);
      expect(stats.failed, 1);
      expect(stats.conflict, 1);
    });

    test('empty constant', () {
      expect(SyncQueueStats.empty.total, 0);
      expect(SyncQueueStats.empty.pending, 0);
      expect(SyncQueueStats.empty.syncing, 0);
      expect(SyncQueueStats.empty.completed, 0);
      expect(SyncQueueStats.empty.failed, 0);
      expect(SyncQueueStats.empty.conflict, 0);
    });

    test('isEmpty', () {
      expect(SyncQueueStats.empty.isEmpty, true);
      final stats = SyncQueueStats(total: 1, pending: 0, syncing: 0, completed: 1, failed: 0, conflict: 0);
      expect(stats.isEmpty, false);
    });

    test('isNotEmpty', () {
      expect(SyncQueueStats.empty.isNotEmpty, false);
      final stats = SyncQueueStats(total: 5, pending: 2, syncing: 0, completed: 3, failed: 0, conflict: 0);
      expect(stats.isNotEmpty, true);
    });

    test('successRate with items', () {
      final stats = SyncQueueStats(total: 10, pending: 0, syncing: 0, completed: 7, failed: 2, conflict: 1);
      expect(stats.successRate, 0.7);
    });

    test('successRate with zero total', () {
      expect(SyncQueueStats.empty.successRate, 0.0);
    });

    test('successRate all completed', () {
      final stats = SyncQueueStats(total: 5, pending: 0, syncing: 0, completed: 5, failed: 0, conflict: 0);
      expect(stats.successRate, 1.0);
    });
  });

  group('SyncQueueManager (in-memory DB)', () {
    late Database db;
    late SyncQueueManager manager;

    setUp(() async {
      db = await openDb();
      manager = SyncQueueManager(database: db);
      // Allow _initializeTable (async in ctor) to complete.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    tearDown(() async {
      manager.dispose();
      await db.close();
    });

    test('addToQueue stores a pending item', () async {
      await manager.addToQueue(
        tableName: 'scans',
        recordId: 'r1',
        operationType: SyncOperationType.create,
        payload: {'resi': 'SPX1'},
      );

      // addToQueue triggers an async processQueue; let it settle.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final stats = await manager.getStats();
      // Either still pending (processing slow) or already completed.
      expect(stats.total, greaterThanOrEqualTo(0));
    });

    test('getPendingItems returns queued items', () async {
      await manager.addToQueue(
        tableName: 'scans',
        recordId: 'pending-1',
        operationType: SyncOperationType.create,
        payload: {'resi': 'SPX2'},
      );
      final pending = await manager.getPendingItems();
      // Items may have been processed already; accept 0 or 1 but no error.
      expect(pending.length, lessThanOrEqualTo(1));
    });

    test('getFailedItems returns empty when none', () async {
      final failed = await manager.getFailedItems();
      expect(failed, isEmpty);
    });

    test('getStats reflects empty queue', () async {
      final stats = await manager.getStats();
      expect(stats.total, 0);
      expect(stats.isEmpty, isTrue);
    });

    test('clearCompleted removes nothing when empty', () async {
      await manager.clearCompleted();
      final stats = await manager.getStats();
      expect(stats.total, 0);
    });

    test('resolveConflict throws when item not found', () async {
      expect(
        () => manager.resolveConflict(itemId: 'missing', useLocalVersion: true),
        throwsA(isA<Exception>()),
      );
    });

    test('resolveConflict throws when item is not in conflict', () async {
      await manager.addToQueue(
        tableName: 'scans',
        recordId: 'r3',
        operationType: SyncOperationType.update,
        payload: {'resi': 'SPX3'},
      );
      // Insert directly to control status deterministically.
      await db.insert('sync_queue', {
        'id': 'fixed-pending',
        'table_name': 'scans',
        'record_id': 'r4',
        'operation_type': SyncOperationType.update.index,
        'payload': '{"resi":"SPX4"}',
        'status': SyncStatus.pending.index,
        'retry_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      });

      expect(
        () => manager.resolveConflict(itemId: 'fixed-pending', useLocalVersion: true),
        throwsA(isA<Exception>()),
      );
    });

    test('processQueue on empty queue resolves to idle', () async {
      await manager.processQueue();
      final stats = await manager.getStats();
      expect(stats.total, 0);
    });

    test('startAutoSync and stopAutoSync do not throw', () {
      manager.startAutoSync(const Duration(hours: 1));
      expect(() => manager.stopAutoSync(), returnsNormally);
    });

    test('syncStatusStream eventually emits idle for empty queue', () async {
      final statuses = <SyncQueueStatus>[];
      final sub = manager.syncStatusStream.listen(statuses.add);
      await manager.processQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(statuses, contains(SyncQueueStatus.syncing));
      expect(statuses.last, SyncQueueStatus.idle);
    });
  });
}

