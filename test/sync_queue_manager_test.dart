import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/offline/sync_queue_manager.dart';
import 'package:scanorder/core/offline/sync_queue_item.dart';

void main() {
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
}
