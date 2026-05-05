import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/offline/sync_queue_item.dart';

void main() {
  final now = DateTime.now();

  group('SyncQueueItem', () {
    late SyncQueueItem item;

    setUp(() {
      item = SyncQueueItem(
        id: 'test-id',
        tableName: 'scans',
        recordId: 'record-1',
        operationType: SyncOperationType.create,
        payload: {'resi': 'SPX123', 'marketplace': 'Shopee'},
        status: SyncStatus.pending,
        retryCount: 0,
        createdAt: now,
      );
    });

    test('creates with correct defaults', () {
      expect(item.id, 'test-id');
      expect(item.tableName, 'scans');
      expect(item.recordId, 'record-1');
      expect(item.operationType, SyncOperationType.create);
      expect(item.status, SyncStatus.pending);
      expect(item.retryCount, 0);
      expect(item.updatedAt, isNull);
      expect(item.lastAttemptAt, isNull);
      expect(item.errorMessage, isNull);
      expect(item.serverVersion, isNull);
      expect(item.localVersion, isNull);
    });

    test('copyWith updates specified fields', () {
      final updated = item.copyWith(
        status: SyncStatus.syncing,
        retryCount: 1,
        errorMessage: 'timeout',
      );
      expect(updated.status, SyncStatus.syncing);
      expect(updated.retryCount, 1);
      expect(updated.errorMessage, 'timeout');
      // Unchanged fields
      expect(updated.id, item.id);
      expect(updated.tableName, item.tableName);
      expect(updated.payload, item.payload);
    });

    test('equality works correctly', () {
      final same = SyncQueueItem(
        id: 'test-id',
        tableName: 'scans',
        recordId: 'record-1',
        operationType: SyncOperationType.create,
        payload: {'resi': 'SPX123', 'marketplace': 'Shopee'},
        status: SyncStatus.pending,
        retryCount: 0,
        createdAt: now,
      );
      expect(item, same);
      expect(item.hashCode, same.hashCode);
    });

    test('different items are not equal', () {
      final other = item.copyWith(id: 'different-id');
      expect(item, isNot(equals(other)));
    });

    test('toMap and fromMap round-trip', () {
      final map = item.toMap();
      final restored = SyncQueueItem.fromMap(map);
      expect(restored.id, item.id);
      expect(restored.tableName, item.tableName);
      expect(restored.recordId, item.recordId);
      expect(restored.operationType, item.operationType);
      expect(restored.status, item.status);
      expect(restored.retryCount, item.retryCount);
      expect(restored.createdAt, item.createdAt);
    });

    test('toMap includes all fields', () {
      final fullItem = SyncQueueItem(
        id: 'full-id',
        tableName: 'scans',
        recordId: 'r1',
        operationType: SyncOperationType.update,
        payload: {'key': 'value'},
        status: SyncStatus.failed,
        retryCount: 3,
        createdAt: now,
        updatedAt: now,
        lastAttemptAt: now,
        errorMessage: 'connection lost',
        serverVersion: 5,
        localVersion: 3,
      );
      final map = fullItem.toMap();
      expect(map['id'], 'full-id');
      expect(map['table_name'], 'scans');
      expect(map['record_id'], 'r1');
      expect(map['operation_type'], SyncOperationType.update.index);
      expect(map['status'], SyncStatus.failed.index);
      expect(map['retry_count'], 3);
      expect(map['updated_at'], now.toIso8601String());
      expect(map['last_attempt_at'], now.toIso8601String());
      expect(map['error_message'], 'connection lost');
      expect(map['server_version'], 5);
      expect(map['local_version'], 3);
    });

    test('fromMap handles null optional fields', () {
      final map = {
        'id': 'test',
        'table_name': 'scans',
        'record_id': 'r1',
        'operation_type': 0,
        'payload': {'key': 'val'},
        'status': 0,
        'retry_count': 0,
        'created_at': now.toIso8601String(),
        // updated_at, last_attempt_at, error_message, server_version, local_version omitted
      };
      final restored = SyncQueueItem.fromMap(map);
      expect(restored.updatedAt, isNull);
      expect(restored.lastAttemptAt, isNull);
      expect(restored.errorMessage, isNull);
      expect(restored.serverVersion, isNull);
      expect(restored.localVersion, isNull);
    });

    test('fromMap with all optional fields', () {
      final map = {
        'id': 'full',
        'table_name': 'orders',
        'record_id': 'r2',
        'operation_type': 2,
        'payload': {'data': 'test'},
        'status': 3,
        'retry_count': 5,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'last_attempt_at': now.toIso8601String(),
        'error_message': 'timeout',
        'server_version': 10,
        'local_version': 8,
      };
      final restored = SyncQueueItem.fromMap(map);
      expect(restored.operationType, SyncOperationType.delete);
      expect(restored.status, SyncStatus.failed);
      expect(restored.retryCount, 5);
      expect(restored.updatedAt, isNotNull);
      expect(restored.lastAttemptAt, isNotNull);
      expect(restored.errorMessage, 'timeout');
      expect(restored.serverVersion, 10);
      expect(restored.localVersion, 8);
    });

    test('copyWith preserves nullable fields when not specified', () {
      final fullItem = SyncQueueItem(
        id: 'id1',
        tableName: 'scans',
        recordId: 'r1',
        operationType: SyncOperationType.create,
        payload: {},
        status: SyncStatus.pending,
        retryCount: 2,
        createdAt: now,
        updatedAt: now,
        lastAttemptAt: now,
        errorMessage: 'err',
        serverVersion: 1,
        localVersion: 2,
      );
      final copy = fullItem.copyWith(status: SyncStatus.completed);
      expect(copy.updatedAt, now);
      expect(copy.lastAttemptAt, now);
      expect(copy.errorMessage, 'err');
      expect(copy.serverVersion, 1);
      expect(copy.localVersion, 2);
    });

    test('copyWith can update nullable fields', () {
      final copy = item.copyWith(
        updatedAt: now,
        lastAttemptAt: now,
        errorMessage: 'new error',
        serverVersion: 99,
        localVersion: 88,
      );
      expect(copy.updatedAt, now);
      expect(copy.lastAttemptAt, now);
      expect(copy.errorMessage, 'new error');
      expect(copy.serverVersion, 99);
      expect(copy.localVersion, 88);
    });

    test('toMap payload is preserved', () {
      final map = item.toMap();
      expect(map['payload'], {'resi': 'SPX123', 'marketplace': 'Shopee'});
    });

    test('fromMap payload is preserved', () {
      final map = item.toMap();
      final restored = SyncQueueItem.fromMap(map);
      expect(restored.payload, {'resi': 'SPX123', 'marketplace': 'Shopee'});
    });
  });

  group('SyncOperationType', () {
    test('has expected values', () {
      expect(SyncOperationType.values.length, 3);
      expect(SyncOperationType.values, [SyncOperationType.create, SyncOperationType.update, SyncOperationType.delete]);
    });

    test('index is correct', () {
      expect(SyncOperationType.create.index, 0);
      expect(SyncOperationType.update.index, 1);
      expect(SyncOperationType.delete.index, 2);
    });
  });

  group('SyncStatus', () {
    test('has expected values', () {
      expect(SyncStatus.values.length, 5);
      expect(SyncStatus.values, contains(SyncStatus.pending));
      expect(SyncStatus.values, contains(SyncStatus.syncing));
      expect(SyncStatus.values, contains(SyncStatus.completed));
      expect(SyncStatus.values, contains(SyncStatus.failed));
      expect(SyncStatus.values, contains(SyncStatus.conflict));
    });
  });
}
