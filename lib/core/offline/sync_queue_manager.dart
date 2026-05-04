import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'sync_queue_item.dart';
import 'conflict_resolution.dart';
import 'exponential_backoff.dart';

/// Enhanced sync queue manager with conflict resolution and exponential backoff
class SyncQueueManager {
  final Database _database;
  final ConflictResolutionStrategy _defaultStrategy;
  final Map<String, ConflictResolutionConfig> _tableConfigs;
  final SyncRetryConfig _retryConfig;
  final RetryExecutor _retryExecutor;
  
  bool _isSyncing = false;
  Timer? _autoSyncTimer;
  
  // Stream controllers for sync status
  final _syncStatusController = StreamController<SyncQueueStatus>.broadcast();
  final _itemProgressController = StreamController<SyncItemProgress>.broadcast();

  Stream<SyncQueueStatus> get syncStatusStream => _syncStatusController.stream;
  Stream<SyncItemProgress> get itemProgressStream => _itemProgressController.stream;
  
  SyncQueueStatus _currentStatus = SyncQueueStatus.idle;
  
  set _status(SyncQueueStatus status) {
    _currentStatus = status;
    _syncStatusController.add(status);
  }

  SyncQueueManager({
    required Database database,
    ConflictResolutionStrategy? defaultStrategy,
    Map<String, ConflictResolutionConfig>? tableConfigs,
    SyncRetryConfig? retryConfig,
  })  : _database = database,
        _defaultStrategy = defaultStrategy ?? LastWriteWinsStrategy(),
        _tableConfigs = tableConfigs ?? {},
        _retryConfig = retryConfig ?? const SyncRetryConfig(),
        _retryExecutor = RetryExecutor(
          policy: const RetryPolicy(
            type: RetryPolicyType.exponentialBackoff,
            maxRetries: 5,
          ),
        ) {
    _initializeTable();
  }

  /// Initialize the sync queue table
  Future<void> _initializeTable() async {
    await _database.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        operation_type INTEGER NOT NULL,
        payload TEXT NOT NULL,
        status INTEGER NOT NULL DEFAULT 0,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        last_attempt_at TEXT,
        error_message TEXT,
        server_version INTEGER,
        local_version INTEGER
      )
    ''');

    // Create indexes for better performance
    await _database.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_queue_status 
      ON sync_queue(status)
    ''');

    await _database.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_queue_table 
      ON sync_queue(table_name)
    ''');

    await _database.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_queue_created 
      ON sync_queue(created_at)
    ''');
  }

  /// Add an item to the sync queue
  Future<void> addToQueue({
    required String tableName,
    required String recordId,
    required SyncOperationType operationType,
    required Map<String, dynamic> payload,
    int? localVersion,
  }) async {
    final itemId = '${tableName}_$recordId_${DateTime.now().millisecondsSinceEpoch}';
    
    final item = SyncQueueItem(
      id: itemId,
      tableName: tableName,
      recordId: recordId,
      operationType: operationType,
      payload: payload,
      status: SyncStatus.pending,
      createdAt: DateTime.now(),
      localVersion: localVersion,
    );

    await _database.insert(
      'sync_queue',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    debugPrint('Added to sync queue: $itemId (${operationType.name})');
    
    // Trigger sync if not already syncing
    if (!_isSyncing) {
      _triggerSync();
    }
  }

  /// Get pending items from the queue
  Future<List<SyncQueueItem>> getPendingItems({int limit = 50}) async {
    final maps = await _database.query(
      'sync_queue',
      where: 'status = ?',
      whereArgs: [SyncStatus.pending.index],
      orderBy: 'created_at ASC',
      limit: limit,
    );

    return maps.map((map) => SyncQueueItem.fromMap(map)).toList();
  }

  /// Get failed items that can be retried
  Future<List<SyncQueueItem>> getFailedItems({int maxRetries = 5}) async {
    final maps = await _database.query(
      'sync_queue',
      where: 'status = ? AND retry_count < ?',
      whereArgs: [SyncStatus.failed.index, maxRetries],
      orderBy: 'last_attempt_at ASC',
      limit: 50,
    );

    return maps.map((map) => SyncQueueItem.fromMap(map)).toList();
  }

  /// Process the sync queue
  Future<void> processQueue() async {
    if (_isSyncing) {
      debugPrint('Sync already in progress, skipping...');
      return;
    }

    _isSyncing = true;
    _status = SyncQueueStatus.syncing;

    try {
      // Get pending and failed items
      final pendingItems = await getPendingItems();
      final failedItems = await getFailedItems();
      
      final allItems = [...pendingItems, ...failedItems];
      
      if (allItems.isEmpty) {
        _status = SyncQueueStatus.idle;
        debugPrint('Sync queue is empty');
        return;
      }

      debugPrint('Processing ${allItems.length} items from sync queue');

      int successCount = 0;
      int failureCount = 0;
      int conflictCount = 0;

      for (final item in allItems) {
        try {
          _itemProgressController.add(SyncItemProgress(
            itemId: item.id,
            status: SyncStatus.syncing,
            message: 'Syncing...',
          ));

          await _processItem(item);
          successCount++;
          
          _itemProgressController.add(SyncItemProgress(
            itemId: item.id,
            status: SyncStatus.completed,
            message: 'Synced successfully',
          ));
        } catch (e) {
          if (e is ConflictRequiresManualResolutionException) {
            conflictCount++;
            await _handleConflict(item, e);
            
            _itemProgressController.add(SyncItemProgress(
              itemId: item.id,
              status: SyncStatus.conflict,
              message: 'Conflict detected',
              error: e,
            ));
          } else {
            failureCount++;
            await _handleFailure(item, e as Exception);
            
            _itemProgressController.add(SyncItemProgress(
              itemId: item.id,
              status: SyncStatus.failed,
              message: 'Sync failed',
              error: e,
            ));
          }
        }
      }

      debugPrint(
        'Sync completed: $successCount succeeded, $failureCount failed, $conflictCount conflicts'
      );

      // Check if there are still pending items
      final remainingItems = await getPendingItems();
      final hasMoreWork = remainingItems.isNotEmpty || 
                         (await getFailedItems()).isNotEmpty;

      _status = hasMoreWork 
          ? SyncQueueStatus.pending 
          : SyncQueueStatus.idle;

    } catch (e) {
      debugPrint('Sync queue processing error: $e');
      _status = SyncQueueStatus.error;
    } finally {
      _isSyncing = false;
    }
  }

  /// Process a single sync queue item
  Future<void> _processItem(SyncQueueItem item) async {
    // Update item status to syncing
    await _updateItemStatus(item, SyncStatus.syncing);

    // Get the appropriate conflict resolution strategy for this table
    final config = _tableConfigs[item.tableName];
    final strategy = config?.strategy ?? _defaultStrategy;

    // Execute with retry logic
    await _retryExecutor.execute(() async {
      // Here you would call your actual sync service
      // For now, we'll simulate the sync operation
      await _performSync(item, strategy);
    });

    // Remove from queue on success
    await _removeFromQueue(item.id);
  }

  /// Perform the actual sync operation (to be implemented based on your backend)
  Future<void> _performSync(
    SyncQueueItem item,
    ConflictResolutionStrategy strategy,
  ) async {
    // This is where you would call your backend API
    // Example implementation:
    
    switch (item.operationType) {
      case SyncOperationType.create:
        // await apiClient.create(item.tableName, item.payload);
        break;
        
      case SyncOperationType.update:
        // Check for conflicts first
        // final serverData = await apiClient.get(item.tableName, item.recordId);
        // if (serverData != null && _hasConflict(serverData, item)) {
        //   throw ConflictRequiresManualResolutionException(...);
        // }
        // await apiClient.update(item.tableName, item.recordId, item.payload);
        break;
        
      case SyncOperationType.delete:
        // await apiClient.delete(item.tableName, item.recordId);
        break;
    }

    // Simulate network delay for demo
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Check if there's a conflict between local and server data
  bool _hasConflict(Map<String, dynamic> serverData, SyncQueueItem item) {
    final serverVersion = serverData['version'] as int? ?? 0;
    final localVersion = item.localVersion ?? 0;
    
    // If server version is newer than what we have, there might be a conflict
    return serverVersion > localVersion;
  }

  /// Handle sync failure with exponential backoff
  Future<void> _handleFailure(SyncQueueItem item, Exception error) async {
    final newRetryCount = item.retryCount + 1;
    
    final backoff = ExponentialBackoff(
      baseDelay: _retryConfig.syncPolicy.baseDelay,
      maxDelay: _retryConfig.syncPolicy.maxDelay,
      maxRetries: _retryConfig.syncPolicy.maxRetries,
    );

    if (!backoff.shouldRetry(newRetryCount)) {
      // Max retries exceeded, mark as permanently failed
      await _updateItemStatus(
        item,
        SyncStatus.failed,
        errorMessage: 'Max retries exceeded: ${error.toString()}',
        retryCount: newRetryCount,
      );
      debugPrint('Item ${item.id} permanently failed after ${newRetryCount} attempts');
      return;
    }

    final nextDelay = backoff.getDelay(newRetryCount);
    
    await _updateItemStatus(
      item,
      SyncStatus.failed,
      errorMessage: error.toString(),
      retryCount: newRetryCount,
      lastAttemptAt: DateTime.now(),
    );

    debugPrint(
      'Item ${item.id} failed (attempt ${newRetryCount}), '
      'will retry in ${nextDelay.inSeconds}s'
    );
  }

  /// Handle conflict resolution
  Future<void> _handleConflict(
    SyncQueueItem item,
    ConflictRequiresManualResolutionException exception,
  ) async {
    debugPrint('Conflict detected for ${item.tableName}.${item.recordId}');

    // Update item status to conflict
    await _updateItemStatus(
      item,
      SyncStatus.conflict,
      errorMessage: 'Manual resolution required',
    );

    // In a real app, you would notify the UI to let the user resolve the conflict
    // For now, we'll just log it
  }

  /// Update item status in the database
  Future<void> _updateItemStatus(
    SyncQueueItem item,
    SyncStatus status, {
    String? errorMessage,
    int? retryCount,
    DateTime? lastAttemptAt,
  }) async {
    final updatedItem = item.copyWith(
      status: status,
      updatedAt: DateTime.now(),
      errorMessage: errorMessage,
      retryCount: retryCount ?? item.retryCount,
      lastAttemptAt: lastAttemptAt ?? item.lastAttemptAt,
    );

    await _database.update(
      'sync_queue',
      updatedItem.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  /// Remove item from queue
  Future<void> _removeFromQueue(String itemId) async {
    await _database.delete(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  /// Manually resolve a conflict
  Future<void> resolveConflict({
    required String itemId,
    required bool useLocalVersion,
    Map<String, dynamic>? mergedData,
  }) async {
    final maps = await _database.query(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );

    if (maps.isEmpty) {
      throw Exception('Sync queue item not found: $itemId');
    }

    final item = SyncQueueItem.fromMap(maps.first);
    
    if (item.status != SyncStatus.conflict) {
      throw Exception('Item is not in conflict state');
    }

    // Use the provided merged data or the winning version
    final finalPayload = mergedData ?? item.payload;

    // Update the item and reset status to pending for re-sync
    final updatedItem = item.copyWith(
      payload: finalPayload,
      status: SyncStatus.pending,
      retryCount: 0,
      errorMessage: null,
      updatedAt: DateTime.now(),
    );

    await _database.update(
      'sync_queue',
      updatedItem.toMap(),
      where: 'id = ?',
      whereArgs: [itemId],
    );

    debugPrint('Conflict resolved for $itemId, using ${useLocalVersion ? "local" : "server"} version');

    // Trigger sync to process the resolved item
    _triggerSync();
  }

  /// Trigger sync process
  void _triggerSync() {
    if (!_isSyncing) {
      // Use runZonedGuarded to catch any errors
      runZonedGuarded(() async {
        await processQueue();
      }, (error, stackTrace) {
        debugPrint('Error in sync trigger: $error');
      });
    }
  }

  /// Start auto-sync timer
  void startAutoSync(Duration interval) {
    stopAutoSync();
    
    _autoSyncTimer = Timer.periodic(interval, (_) {
      _triggerSync();
    });
    
    debugPrint('Auto-sync started with interval: $interval');
  }

  /// Stop auto-sync timer
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    debugPrint('Auto-sync stopped');
  }

  /// Get current queue statistics
  Future<SyncQueueStats> getStats() async {
    final results = await _database.rawQuery('''
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN status = 0 THEN 1 ELSE 0 END) as pending,
        SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) as syncing,
        SUM(CASE WHEN status = 2 THEN 1 ELSE 0 END) as completed,
        SUM(CASE WHEN status = 3 THEN 1 ELSE 0 END) as failed,
        SUM(CASE WHEN status = 4 THEN 1 ELSE 0 END) as conflict
      FROM sync_queue
    ''');

    if (results.isEmpty) {
      return SyncQueueStats.empty;
    }

    final row = results.first;
    return SyncQueueStats(
      total: row['total'] as int? ?? 0,
      pending: row['pending'] as int? ?? 0,
      syncing: row['syncing'] as int? ?? 0,
      completed: row['completed'] as int? ?? 0,
      failed: row['failed'] as int? ?? 0,
      conflict: row['conflict'] as int? ?? 0,
    );
  }

  /// Clear completed items from queue
  Future<void> clearCompleted() async {
    await _database.delete(
      'sync_queue',
      where: 'status = ?',
      whereArgs: [SyncStatus.completed.index],
    );
    debugPrint('Cleared completed items from sync queue');
  }

  /// Dispose resources
  void dispose() {
    stopAutoSync();
    _syncStatusController.close();
    _itemProgressController.close();
  }
}

/// Status of the sync queue
enum SyncQueueStatus {
  idle,
  syncing,
  pending,
  error,
}

/// Progress information for a sync item
class SyncItemProgress {
  final String itemId;
  final SyncStatus status;
  final String? message;
  final Exception? error;

  SyncItemProgress({
    required this.itemId,
    required this.status,
    this.message,
    this.error,
  });
}

/// Statistics for the sync queue
class SyncQueueStats {
  final int total;
  final int pending;
  final int syncing;
  final int completed;
  final int failed;
  final int conflict;

  const SyncQueueStats({
    required this.total,
    required this.pending,
    required this.syncing,
    required this.completed,
    required this.failed,
    required this.conflict,
  });

  static const empty = SyncQueueStats(
    total: 0,
    pending: 0,
    syncing: 0,
    completed: 0,
    failed: 0,
    conflict: 0,
  );

  bool get isEmpty => total == 0;
  bool get isNotEmpty => total > 0;
  
  double get successRate => total > 0 ? completed / total : 0.0;
}
