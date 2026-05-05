import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/services/sync_queue.dart';

void main() {
  group('SyncTaskType', () {
    test('has expected values', () {
      expect(SyncTaskType.values.length, 4);
      expect(SyncTaskType.values, contains(SyncTaskType.insertScan));
      expect(SyncTaskType.values, contains(SyncTaskType.uploadPhoto));
      expect(SyncTaskType.values, contains(SyncTaskType.syncSubscription));
      expect(SyncTaskType.values, contains(SyncTaskType.insertScanCategory));
    });

    test('index is correct', () {
      expect(SyncTaskType.insertScan.index, 0);
      expect(SyncTaskType.uploadPhoto.index, 1);
      expect(SyncTaskType.syncSubscription.index, 2);
      expect(SyncTaskType.insertScanCategory.index, 3);
    });
  });

  group('SyncTask', () {
    final now = DateTime.now();

    test('creates with required fields', () {
      final task = SyncTask(
        id: 'task-1',
        type: SyncTaskType.insertScan,
        payload: {'resi': 'SPX123', 'marketplace': 'Shopee'},
        createdAt: now,
      );
      expect(task.id, 'task-1');
      expect(task.type, SyncTaskType.insertScan);
      expect(task.retryCount, 0);
      expect(task.nextRetryAt, isNull);
    });

    test('toMap and fromMap round-trip', () {
      final task = SyncTask(
        id: 'task-2',
        type: SyncTaskType.uploadPhoto,
        payload: {'local_path': '/path/to/photo.jpg', 'resi': 'SPX456'},
        retryCount: 2,
        createdAt: now,
        nextRetryAt: now.add(const Duration(minutes: 5)),
      );
      final map = task.toMap();
      final restored = SyncTask.fromMap(map);
      expect(restored.id, task.id);
      expect(restored.type, task.type);
      expect(restored.payload, task.payload);
      expect(restored.retryCount, task.retryCount);
      expect(restored.createdAt.millisecondsSinceEpoch, task.createdAt.millisecondsSinceEpoch);
      expect(restored.nextRetryAt?.millisecondsSinceEpoch, task.nextRetryAt?.millisecondsSinceEpoch);
    });

    test('toMap includes all fields', () {
      final task = SyncTask(
        id: 'task-3',
        type: SyncTaskType.syncSubscription,
        payload: {'user_id': 'u1', 'tier': 'pro'},
        retryCount: 3,
        createdAt: now,
        nextRetryAt: now.add(const Duration(hours: 1)),
      );
      final map = task.toMap();
      expect(map['id'], 'task-3');
      expect(map['type'], SyncTaskType.syncSubscription.index);
      expect(map['retry_count'], 3);
      expect(map['next_retry_at'], isNotNull);
    });

    test('fromMap handles null nextRetryAt', () {
      final map = {
        'id': 'task-4',
        'type': 0,
        'payload': '{"key":"value"}',
        'retry_count': 0,
        'created_at': now.millisecondsSinceEpoch,
        // next_retry_at omitted
      };
      final task = SyncTask.fromMap(map);
      expect(task.nextRetryAt, isNull);
    });

    test('copyWith updates specified fields', () {
      final task = SyncTask(
        id: 'task-5',
        type: SyncTaskType.insertScan,
        payload: {},
        createdAt: now,
      );
      final updated = task.copyWith(
        retryCount: 5,
        nextRetryAt: now.add(const Duration(minutes: 30)),
      );
      expect(updated.retryCount, 5);
      expect(updated.nextRetryAt, isNotNull);
      expect(updated.id, task.id);
      expect(updated.type, task.type);
    });

    test('copyWith preserves fields when not specified', () {
      final task = SyncTask(
        id: 'task-6',
        type: SyncTaskType.insertScanCategory,
        payload: {},
        retryCount: 2,
        createdAt: now,
        nextRetryAt: now.add(const Duration(seconds: 10)),
      );
      final updated = task.copyWith();
      expect(updated.retryCount, 2);
      expect(updated.nextRetryAt, task.nextRetryAt);
    });

    test('toMap encodes payload as JSON string', () {
      final payload = {'key': 'value', 'number': 42};
      final task = SyncTask(
        id: 'task-encode',
        type: SyncTaskType.insertScan,
        payload: payload,
        createdAt: now,
      );
      final map = task.toMap();
      expect(map['payload'], isA<String>());
      expect(map['payload'], contains('key'));
    });

    test('fromMap decodes payload from JSON string', () {
      final map = {
        'id': 'task-decode',
        'type': 0,
        'payload': '{"resi":"SPX123","marketplace":"Shopee"}',
        'retry_count': 0,
        'created_at': now.millisecondsSinceEpoch,
      };
      final task = SyncTask.fromMap(map);
      expect(task.payload['resi'], 'SPX123');
      expect(task.payload['marketplace'], 'Shopee');
    });

    test('fromMap returns empty payload on invalid JSON', () {
      final map = {
        'id': 'task-invalid',
        'type': 0,
        'payload': 'invalid json',
        'retry_count': 0,
        'created_at': now.millisecondsSinceEpoch,
      };
      final task = SyncTask.fromMap(map);
      expect(task.payload, isEmpty);
    });

    test('handles complex nested payload', () {
      final complex = {
        'resi': 'SPX999',
        'marketplace': 'Shopee',
        'metadata': {'source': 'scan', 'device': 'iPhone'},
        'tags': ['urgent', 'priority'],
      };
      final task = SyncTask(
        id: 'task-complex',
        type: SyncTaskType.insertScan,
        payload: complex,
        createdAt: now,
      );
      final restored = SyncTask.fromMap(task.toMap());
      expect(restored.payload['resi'], 'SPX999');
      expect(restored.payload['metadata']['source'], 'scan');
      expect(restored.payload['tags'], ['urgent', 'priority']);
    });

    test('handles empty payload', () {
      final task = SyncTask(
        id: 'task-empty',
        type: SyncTaskType.insertScan,
        payload: {},
        createdAt: now,
      );
      final restored = SyncTask.fromMap(task.toMap());
      expect(restored.payload, isEmpty);
    });
  });
}
