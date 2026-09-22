import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient, User;
import 'package:scanorder/core/supabase/supabase_service.dart';
import 'package:scanorder/services/sync_queue.dart';

class MockSupabaseService extends Mock implements SupabaseService {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockUser extends Mock implements User {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Database> openQueueDb() async {
    sqfliteFfiInit();
    databaseFactoryOrNull = databaseFactoryFfi;
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE sync_queue (
              id TEXT PRIMARY KEY,
              type INTEGER NOT NULL,
              payload TEXT NOT NULL,
              retry_count INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              next_retry_at INTEGER
            )
          ''');
        },
      ),
    );
    return db;
  }

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

  group('SyncQueue behavior (in-memory DB, offline)', () {
    late Database db;
    late SyncQueue queue;

    setUp(() async {
      db = await openQueueDb();
      queue = SyncQueue();
      queue.setTestDatabase(db);
      // Offline prevents _tryProcess from touching the network.
      queue.setTestOnline(false);
      queue.setTeamContext(null);
    });

    tearDown(() async {
      await db.close();
    });

    test('pendingCount is 0 initially', () async {
      expect(await queue.pendingCount, 0);
    });

    test('enqueue increases pendingCount and persists row', () async {
      await queue.enqueue(SyncTaskType.insertScan, {
        'resi': 'SPX1',
        'user_id': 'u1',
      });
      expect(await queue.pendingCount, 1);

      final rows = await db.query('sync_queue');
      expect(rows, hasLength(1));
      final task = SyncTask.fromMap(rows.first);
      expect(task.type, SyncTaskType.insertScan);
      expect(task.payload['resi'], 'SPX1');
    });

    test('enqueues multiple distinct task types', () async {
      await queue.enqueue(SyncTaskType.insertScan, {'resi': 'SPX1'});
      await queue.enqueue(SyncTaskType.uploadPhoto, {'local_path': '/a.jpg'});
      await queue.enqueue(SyncTaskType.syncSubscription, {'tier': 'pro'});
      expect(await queue.pendingCount, 3);
    });

    test('setTeamContext stores team id', () {
      queue.setTeamContext('team-1');
      // No public getter; assert no throw and behavior remains stable.
      expect(() => queue.setTeamContext(null), returnsNormally);
    });

    test('payload round-trips through DB encoding', () async {
      await queue.enqueue(SyncTaskType.insertScan, {
        'resi': 'SPX2',
        'marketplace': 'Shopee',
        'nested': {'a': 1},
      });
      final rows = await db.query('sync_queue');
      final task = SyncTask.fromMap(rows.first);
      expect(task.payload['marketplace'], 'Shopee');
      expect((task.payload['nested'] as Map)['a'], 1);
    });
  });

  group('SyncQueue processing branches (mocked Supabase)', () {
    late Database db;
    late SyncQueue queue;
    late MockSupabaseService supabase;
    late MockSupabaseClient client;

    setUp(() async {
      db = await openQueueDb();
      supabase = MockSupabaseService();
      client = MockSupabaseClient();
      queue = SyncQueue();
      queue.setTestDatabase(db);
      queue.setSupabaseService(supabase);
      queue.setTestOnline(true);
      queue.setTeamContext(null);
    });

    tearDown(() async {
      queue.setTestOnline(false);
      await db.close();
    });

    test('task stays queued when client is null (retry)', () async {
      when(() => supabase.client).thenReturn(null);
      await queue.enqueue(SyncTaskType.insertScan, {'resi': 'SPX1'});
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // Cannot be delivered without a client → remains in queue.
      expect(await queue.pendingCount, 1);
    });

    test('drops stale personal task from another user', () async {
      final user = MockUser();
      when(() => user.id).thenReturn('current-user');
      when(() => supabase.client).thenReturn(client);
      when(() => supabase.currentUser).thenReturn(user);

      await queue.enqueue(SyncTaskType.insertScan, {
        'resi': 'SPX-OLD',
        'user_id': 'other-user',
        // no team_id → personal stale task
      });
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(await queue.pendingCount, 0);
    });

    test('drops task belonging to a left team', () async {
      when(() => supabase.client).thenReturn(client);
      when(() => supabase.currentUser).thenReturn(null);
      queue.setTeamContext('team-current');

      await queue.enqueue(SyncTaskType.insertScan, {
        'resi': 'SPX-TEAM',
        'user_id': 'admin',
        'team_id': 'team-old',
      });
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(await queue.pendingCount, 0);
    });

    test('uploadPhoto with missing file is dropped', () async {
      when(() => supabase.client).thenReturn(client);
      when(() => supabase.currentUser).thenReturn(null);

      await queue.enqueue(SyncTaskType.uploadPhoto, {
        'local_path': '/does/not/exist.jpg',
        'user_id': 'u1',
        'resi': 'SPX1',
      });
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(await queue.pendingCount, 0);
    });
  });
}
