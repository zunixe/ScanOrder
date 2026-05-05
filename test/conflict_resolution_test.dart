import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/offline/conflict_resolution.dart';

void main() {
  final now = DateTime.now();
  final earlier = now.subtract(const Duration(hours: 1));
  final later = now.add(const Duration(hours: 1));

  final localData = {'id': '1', 'name': 'Local', 'status': 'active', 'notes': 'local notes'};
  final serverData = {'id': '1', 'name': 'Server', 'status': 'inactive', 'notes': 'server notes'};

  group('LastWriteWinsStrategy', () {
    final strategy = LastWriteWinsStrategy();

    test('local wins when local is more recent', () async {
      final result = await strategy.resolveConflict(
        tableName: 'scans',
        recordId: '1',
        localData: localData,
        serverData: serverData,
        localVersion: 2,
        serverVersion: 1,
        localUpdatedAt: later,
        serverUpdatedAt: earlier,
      );
      expect(result, true);
    });

    test('server wins when server is more recent', () async {
      final result = await strategy.resolveConflict(
        tableName: 'scans',
        recordId: '1',
        localData: localData,
        serverData: serverData,
        localVersion: 1,
        serverVersion: 2,
        localUpdatedAt: earlier,
        serverUpdatedAt: later,
      );
      expect(result, false);
    });

    test('server wins when timestamps are equal', () async {
      final result = await strategy.resolveConflict(
        tableName: 'scans',
        recordId: '1',
        localData: localData,
        serverData: serverData,
        localVersion: 1,
        serverVersion: 1,
        localUpdatedAt: now,
        serverUpdatedAt: now,
      );
      expect(result, false); // isAfter returns false for equal times
    });

    test('mergeData returns local data when local wins', () async {
      final merged = await strategy.mergeData(
        localData: localData,
        serverData: serverData,
        localWins: true,
      );
      expect(merged, localData);
    });

    test('mergeData returns server data when server wins', () async {
      final merged = await strategy.mergeData(
        localData: localData,
        serverData: serverData,
        localWins: false,
      );
      expect(merged, serverData);
    });
  });

  group('ServerWinsStrategy', () {
    final strategy = ServerWinsStrategy();

    test('always returns false (server wins)', () async {
      final result = await strategy.resolveConflict(
        tableName: 'scans',
        recordId: '1',
        localData: localData,
        serverData: serverData,
        localVersion: 2,
        serverVersion: 1,
        localUpdatedAt: later,
        serverUpdatedAt: earlier,
      );
      expect(result, false);
    });

    test('mergeData always returns server data', () async {
      final merged = await strategy.mergeData(
        localData: localData,
        serverData: serverData,
        localWins: true, // even when localWins is true
      );
      expect(merged, serverData);
    });
  });

  group('ManualResolutionStrategy', () {
    final strategy = ManualResolutionStrategy();

    test('resolveConflict throws ConflictRequiresManualResolutionException', () async {
      expect(
        () => strategy.resolveConflict(
          tableName: 'scans',
          recordId: '1',
          localData: localData,
          serverData: serverData,
          localVersion: 1,
          serverVersion: 2,
          localUpdatedAt: now,
          serverUpdatedAt: now,
        ),
        throwsA(isA<ConflictRequiresManualResolutionException>()),
      );
    });

    test('mergeData returns local when localWins', () async {
      final merged = await strategy.mergeData(
        localData: localData,
        serverData: serverData,
        localWins: true,
      );
      expect(merged, localData);
    });

    test('mergeData returns server when !localWins', () async {
      final merged = await strategy.mergeData(
        localData: localData,
        serverData: serverData,
        localWins: false,
      );
      expect(merged, serverData);
    });
  });

  group('SmartMergeStrategy', () {
    test('no conflicts returns true (local wins)', () async {
      final strategy = SmartMergeStrategy();
      final sameData = {'id': '1', 'name': 'Same'};
      final result = await strategy.resolveConflict(
        tableName: 'scans',
        recordId: '1',
        localData: sameData,
        serverData: sameData,
        localVersion: 1,
        serverVersion: 1,
        localUpdatedAt: now,
        serverUpdatedAt: now,
      );
      expect(result, true);
    });

    test('conflicts only in priority fields returns true', () async {
      final strategy = SmartMergeStrategy(priorityFields: ['status']);
      final local = {'id': '1', 'name': 'Same', 'status': 'active'};
      final server = {'id': '1', 'name': 'Same', 'status': 'inactive'};
      final result = await strategy.resolveConflict(
        tableName: 'scans',
        recordId: '1',
        localData: local,
        serverData: server,
        localVersion: 1,
        serverVersion: 1,
        localUpdatedAt: earlier,
        serverUpdatedAt: later,
      );
      expect(result, true);
    });

    test('conflicts in non-priority fields uses last-write-wins', () async {
      final strategy = SmartMergeStrategy(priorityFields: ['status']);
      final local = {'id': '1', 'name': 'Local', 'status': 'active'};
      final server = {'id': '1', 'name': 'Server', 'status': 'active'};
      final result = await strategy.resolveConflict(
        tableName: 'scans',
        recordId: '1',
        localData: local,
        serverData: server,
        localVersion: 1,
        serverVersion: 1,
        localUpdatedAt: later,
        serverUpdatedAt: earlier,
      );
      expect(result, true); // local is more recent
    });

    test('conflicts in non-priority fields, server more recent', () async {
      final strategy = SmartMergeStrategy(priorityFields: ['status']);
      final local = {'id': '1', 'name': 'Local', 'status': 'active'};
      final server = {'id': '1', 'name': 'Server', 'status': 'active'};
      final result = await strategy.resolveConflict(
        tableName: 'scans',
        recordId: '1',
        localData: local,
        serverData: server,
        localVersion: 1,
        serverVersion: 1,
        localUpdatedAt: earlier,
        serverUpdatedAt: later,
      );
      expect(result, false); // server is more recent
    });

    test('mergeData with localWins overlays priority fields', () async {
      final strategy = SmartMergeStrategy(priorityFields: ['status', 'notes']);
      final local = {'id': '1', 'name': 'Local', 'status': 'active', 'notes': 'local notes'};
      final server = {'id': '1', 'name': 'Server', 'status': 'inactive', 'notes': 'server notes'};
      final merged = await strategy.mergeData(
        localData: local,
        serverData: server,
        localWins: true,
      );
      expect(merged['name'], 'Server'); // from server
      expect(merged['status'], 'active'); // from local (priority)
      expect(merged['notes'], 'local notes'); // from local (priority)
    });

    test('mergeData with serverWins keeps local priority fields', () async {
      final strategy = SmartMergeStrategy(priorityFields: ['status']);
      final local = {'id': '1', 'name': 'Local', 'status': 'active'};
      final server = {'id': '1', 'name': 'Server', 'status': 'inactive'};
      final merged = await strategy.mergeData(
        localData: local,
        serverData: server,
        localWins: false,
      );
      expect(merged['name'], 'Server'); // from server (non-priority)
      expect(merged['status'], 'active'); // from local (priority)
    });
  });

  group('ConflictRequiresManualResolutionException', () {
    test('toString contains table and record info', () {
      final e = ConflictRequiresManualResolutionException(
        tableName: 'scans',
        recordId: '123',
        localData: {},
        serverData: {},
        localVersion: 1,
        serverVersion: 2,
        localUpdatedAt: now,
        serverUpdatedAt: later,
      );
      expect(e.toString(), contains('scans'));
      expect(e.toString(), contains('123'));
    });

    test('stores all fields', () {
      final e = ConflictRequiresManualResolutionException(
        tableName: 'scans',
        recordId: '123',
        localData: {'a': 1},
        serverData: {'b': 2},
        localVersion: 1,
        serverVersion: 2,
        localUpdatedAt: now,
        serverUpdatedAt: later,
      );
      expect(e.tableName, 'scans');
      expect(e.recordId, '123');
      expect(e.localData, {'a': 1});
      expect(e.serverData, {'b': 2});
      expect(e.localVersion, 1);
      expect(e.serverVersion, 2);
    });
  });

  group('ConflictResolutionConfig', () {
    test('default autoResolveTimeout is 24 hours', () {
      final config = ConflictResolutionConfig(
        tableName: 'scans',
        strategy: ServerWinsStrategy(),
      );
      expect(config.autoResolveTimeout, const Duration(hours: 24));
    });

    test('custom autoResolveTimeout', () {
      final config = ConflictResolutionConfig(
        tableName: 'scans',
        strategy: ServerWinsStrategy(),
        autoResolveTimeout: const Duration(hours: 48),
      );
      expect(config.autoResolveTimeout, const Duration(hours: 48));
    });
  });
}
