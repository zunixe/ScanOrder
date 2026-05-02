import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../core/supabase/supabase_service.dart';
import '../core/db/database_helper.dart';

/// Task yang perlu di-sync ke Supabase
enum SyncTaskType { insertOrder, uploadPhoto, syncSubscription, insertOrderCategory }

class SyncTask {
  final String id;
  final SyncTaskType type;
  final Map<String, dynamic> payload;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? nextRetryAt;

  const SyncTask({
    required this.id,
    required this.type,
    required this.payload,
    this.retryCount = 0,
    required this.createdAt,
    this.nextRetryAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.index,
    'payload': _encodePayload(payload),
    'retry_count': retryCount,
    'created_at': createdAt.millisecondsSinceEpoch,
    'next_retry_at': nextRetryAt?.millisecondsSinceEpoch,
  };

  factory SyncTask.fromMap(Map<String, dynamic> map) => SyncTask(
    id: map['id'] as String,
    type: SyncTaskType.values[map['type'] as int],
    payload: _decodePayload(map['payload'] as String),
    retryCount: map['retry_count'] as int? ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    nextRetryAt: map['next_retry_at'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['next_retry_at'] as int)
        : null,
  );

  SyncTask copyWith({int? retryCount, DateTime? nextRetryAt}) => SyncTask(
    id: id,
    type: type,
    payload: payload,
    retryCount: retryCount ?? this.retryCount,
    createdAt: createdAt,
    nextRetryAt: nextRetryAt ?? this.nextRetryAt,
  );

  static String _encodePayload(Map<String, dynamic> p) =>
      jsonEncode(p);

  static Map<String, dynamic> _decodePayload(String raw) {
    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }
}

/// Queue system untuk sync data ke Supabase dengan retry & rate limiting.
/// Menggunakan SQLite lokal sebagai persistent queue.
class SyncQueue {
  static final SyncQueue _instance = SyncQueue._internal();
  factory SyncQueue() => _instance;
  SyncQueue._internal();

  final SupabaseService _supabase = SupabaseService();
  bool _isProcessing = false;
  bool _isOnline = true;
  int _tasksProcessedInWindow = 0;
  DateTime? _windowStart;

  static const int _maxRetries = 5;
  static const int _maxTasksPerMinute = 30; // rate limit
  static const int _concurrentUploads = 3;

  /// Jumlah task pending di queue
  Future<int> get pendingCount async {
    final db = await _getQueueDb();
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM sync_queue');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Tambah task ke queue
  Future<void> enqueue(SyncTaskType type, Map<String, dynamic> payload) async {
    final task = SyncTask(
      id: '${type.index}_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
    );
    final db = await _getQueueDb();
    await db.insert('sync_queue', _taskToDbMap(task));
    debugPrint('[SyncQueue] Enqueued: ${type.name} (id=${task.id})');
    _tryProcess();
  }

  /// Proses queue (dipanggil otomatis setelah enqueue, dan saat app online lagi)
  Future<void> _tryProcess() async {
    if (_isProcessing || !_isOnline) return;
    _isProcessing = true;

    try {
      final db = await _getQueueDb();

      while (true) {
        // Rate limiting
        if (!_checkRateLimit()) {
          debugPrint('[SyncQueue] Rate limit hit, pausing for 60s');
          await Future.delayed(const Duration(seconds: 60));
          _resetRateLimitWindow();
          continue;
        }

        // Ambil task yang siap diproses (next_retry_at sudah lewat atau null)
        final now = DateTime.now().millisecondsSinceEpoch;
        final rows = await db.query(
          'sync_queue',
          where: 'next_retry_at IS NULL OR next_retry_at <= ?',
          whereArgs: [now],
          orderBy: 'created_at ASC',
          limit: _concurrentUploads,
        );

        if (rows.isEmpty) break;

        final tasks = rows.map((r) => SyncTask.fromMap(r)).toList();

        // Process tasks concurrently
        await Future.wait(
          tasks.map((task) => _processTask(task)),
          eagerError: false,
        );
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Proses satu task
  Future<void> _processTask(SyncTask task) async {
    final client = _supabase.client;
    if (client == null) {
      _markRetry(task);
      return;
    }

    bool success = false;

    try {
      switch (task.type) {
        case SyncTaskType.insertOrder:
          success = await _processInsertOrder(task);
          break;
        case SyncTaskType.uploadPhoto:
          success = await _processUploadPhoto(task);
          break;
        case SyncTaskType.syncSubscription:
          success = await _processSyncSubscription(task);
          break;
        case SyncTaskType.insertOrderCategory:
          success = await _processInsertOrderCategory(task);
          break;
      }
    } catch (e) {
      debugPrint('[SyncQueue] Task ${task.id} error: $e');
    }

    if (success) {
      final db = await _getQueueDb();
      await db.delete('sync_queue', where: 'id = ?', whereArgs: [task.id]);
      _tasksProcessedInWindow++;
      debugPrint('[SyncQueue] Task ${task.id} completed ✓');
    } else {
      _markRetry(task);
    }
  }

  Future<bool> _processInsertOrder(SyncTask task) async {
    final client = _supabase.client;
    if (client == null) return false;

    final p = task.payload;
    try {
      await client.from('scans').insert({
        'device_id': p['device_id'] ?? 'unknown',
        'user_id': p['user_id'],
        'resi': p['resi'],
        'marketplace': p['marketplace'],
        'scanned_at': int.tryParse(p['scanned_at']?.toString() ?? '0') ?? 0,
        'date': p['date'],
        'photo_url': p['photo_url'],
        'team_id': p['team_id'],
      });
      // Also insert scan_categories if category_id is present (map local int -> Supabase UUID)
      final categoryId = p['category_id'];
      if (categoryId != null) {
        try {
          // Find Supabase scan id by resi
          final rows = await client.from('scans').select('id').eq('resi', p['resi']).limit(1);
          final rowList = List<Map<String, dynamic>>.from(rows);
          if (rowList.isNotEmpty) {
            final scanId = rowList.first['id'];
            // Resolve Supabase category UUID by local category name + owner
            final localCat = await DatabaseHelper.instance.getCategoryById(categoryId as int);
            if (localCat != null) {
              final ownerUserId = localCat.userId ?? SupabaseService().currentUser?.id;
              if (ownerUserId == null) {
                debugPrint('[SyncQueue] insertOrder: cannot resolve ownerUserId for category ${localCat.name}');
                return true; // do not fail the whole task
              }
              final catRows = await client
                  .from('categories')
                  .select('id')
                  .eq('user_id', ownerUserId)
                  .eq('name', localCat.name)
                  .limit(1);
              final catList = List<Map<String, dynamic>>.from(catRows);
              if (catList.isNotEmpty) {
                final catUuid = catList.first['id'];
                debugPrint('[SyncQueue] insertOrder: inserting scan_categories scan_id=$scanId, category_uuid=$catUuid (from local id=$categoryId)');
                await client.from('scan_categories').insert({
                  'scan_id': scanId,
                  'category_id': catUuid,
                });
                debugPrint('[SyncQueue] insertOrder: scan_categories inserted OK');
              } else {
                debugPrint('[SyncQueue] insertOrder: Supabase category not found for name=${localCat.name}, owner=$ownerUserId');
              }
            } else {
              debugPrint('[SyncQueue] insertOrder: local category not found id=$categoryId');
            }
          }
        } catch (e2) {
          debugPrint('[SyncQueue] insertOrder: scan_categories error: $e2');
        }
      }
      return true;
    } catch (e) {
      debugPrint('[SyncQueue] insertOrder error: $e');
      return false;
    }
  }

  /// Insert relation into scan_categories using resi lookup to get scan_id.
  /// If the scan row hasn't been inserted yet, this will return false to retry later.
  Future<bool> _processInsertOrderCategory(SyncTask task) async {
    final client = _supabase.client;
    if (client == null) return false;

    final p = task.payload;
    final resi = p['resi'] as String?;
    final categoryId = p['category_id'];
    if (resi == null || categoryId == null) return false;

    try {
      // Find scan id by resi
      final rows = await client.from('scans').select('id').eq('resi', resi).limit(1) as List<dynamic>;
      if (rows.isNotEmpty) {
        final scanId = rows.first['id'];
        // Resolve Supabase category UUID by local category name + owner
        final localCat = await DatabaseHelper.instance.getCategoryById(categoryId as int);
        if (localCat == null) {
          debugPrint('[SyncQueue] insertOrderCategory: local category not found id=$categoryId');
          return false;
        }
        final ownerUserId = localCat.userId ?? SupabaseService().currentUser?.id;
        if (ownerUserId == null) {
          debugPrint('[SyncQueue] insertOrderCategory: cannot resolve ownerUserId for category ${localCat.name}');
          return false;
        }
        final catRows = await client
            .from('categories')
            .select('id')
            .eq('user_id', ownerUserId)
            .eq('name', localCat.name)
            .limit(1) as List<dynamic>;
        if (catRows.isEmpty) {
          debugPrint('[SyncQueue] insertOrderCategory: Supabase category not found for name=${localCat.name}, owner=$ownerUserId');
          return false;
        }
        final catUuid = catRows.first['id'];
        await client.from('scan_categories').upsert({
          'scan_id': scanId,
          'category_id': catUuid,
        });
        return true;
      }
      // Scan not found yet, retry later
      return false;
    } catch (e) {
      debugPrint('[SyncQueue] insertOrderCategory error: $e');
      return false;
    }
  }

  Future<bool> _processUploadPhoto(SyncTask task) async {
    final p = task.payload;
    final localPath = p['local_path'] as String?;
    if (localPath == null) return false;

    final file = File(localPath);
    if (!file.existsSync()) {
      // File sudah dihapus, skip
      final db = await _getQueueDb();
      await db.delete('sync_queue', where: 'id = ?', whereArgs: [task.id]);
      return true;
    }

    final userId = p['user_id'] as String?;
    final fileName = p['cloud_filename'] as String? ??
        '${userId ?? 'anon'}/${DateTime.now().millisecondsSinceEpoch}.jpg';

    final url = await _supabase.uploadPhoto(file, fileName);
    if (url != null) {
      // Update photo_url di Supabase scans table
      final client = _supabase.client;
      if (client != null && p['resi'] != null) {
        try {
          await client
              .from('scans')
              .update({'photo_url': url})
              .eq('resi', p['resi'] as String);
        } catch (e) {
          debugPrint('[SyncQueue] Update photo_url in Supabase error: $e');
          // Don't mark as success — retry later
          return false;
        }
      }
      // Update photo_path di DB lokal ke cloud URL
      try {
        final dbHelper = DatabaseHelper.instance;
        final orders = await dbHelper.getAllOrders(userId: userId);
        for (final o in orders) {
          if (o.photoPath == localPath && o.id != null) {
            await dbHelper.updateOrderPhoto(o.id!, url);
            debugPrint('[SyncQueue] Updated local photo_path to cloud URL for resi=${o.resi}');
            break;
          }
        }
      } catch (e) {
        debugPrint('[SyncQueue] Update local photo_path error: $e');
      }
      return true;
    }
    return false;
  }

  Future<bool> _processSyncSubscription(SyncTask task) async {
    final p = task.payload;
    final client = _supabase.client;
    if (client == null) return false;

    final userId = p['user_id'] as String?;
    if (userId == null) return false;

    try {
      await client.from('user_subscriptions').upsert({
        'user_id': userId,
        'email': p['email'],
        'tier': p['tier'],
        'active_from': p['active_from'],
        'active_until': p['active_until'],
        'cycle_allowance': int.tryParse(p['cycle_allowance']?.toString() ?? '0'),
        'cycle_used': int.tryParse(p['cycle_used']?.toString() ?? '0'),
        'storage_used': int.tryParse(p['storage_used']?.toString() ?? '0'),
        'updated_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('[SyncQueue] syncSubscription error: $e');
      return false;
    }
  }

  /// Tandai task untuk retry dengan exponential backoff
  Future<void> _markRetry(SyncTask task) async {
    if (task.retryCount >= _maxRetries) {
      // Max retry, hapus task
      debugPrint('[SyncQueue] Task ${task.id} max retries reached, dropping');
      final db = await _getQueueDb();
      await db.delete('sync_queue', where: 'id = ?', whereArgs: [task.id]);
      return;
    }

    // Exponential backoff: 5s, 30s, 2m, 10m, 30m
    final delays = [
      Duration(seconds: 5),
      Duration(seconds: 30),
      Duration(minutes: 2),
      Duration(minutes: 10),
      Duration(minutes: 30),
    ];
    final delay = delays[task.retryCount.clamp(0, delays.length - 1)];
    final nextRetry = DateTime.now().add(delay);

    final updated = task.copyWith(
      retryCount: task.retryCount + 1,
      nextRetryAt: nextRetry,
    );

    final db = await _getQueueDb();
    await db.update(
      'sync_queue',
      _taskToDbMap(updated),
      where: 'id = ?',
      whereArgs: [task.id],
    );
    debugPrint('[SyncQueue] Task ${task.id} retry ${updated.retryCount}/$_maxRetries, next at $nextRetry');
  }

  /// Rate limiting check
  bool _checkRateLimit() {
    final now = DateTime.now();
    if (_windowStart == null || now.difference(_windowStart!) > const Duration(minutes: 1)) {
      _resetRateLimitWindow();
    }
    return _tasksProcessedInWindow < _maxTasksPerMinute;
  }

  void _resetRateLimitWindow() {
    _windowStart = DateTime.now();
    _tasksProcessedInWindow = 0;
  }

  /// Set online/offline status
  void setOnline(bool online) {
    final wasOffline = !_isOnline;
    _isOnline = online;
    if (wasOffline && online) {
      debugPrint('[SyncQueue] Back online, processing queue...');
      _tryProcess();
    }
  }

  /// Process any pending tasks in the queue (call on app start)
  Future<void> processPending() async {
    final count = await pendingCount;
    if (count > 0) {
      debugPrint('[SyncQueue] Processing $count pending tasks on startup');
      _tryProcess();
    }
  }

  /// Get/create the queue database
  Future<Database> _getQueueDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'sync_queue.db');
    return openDatabase(
      path,
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
        await db.execute('CREATE INDEX idx_sync_queue_next_retry ON sync_queue(next_retry_at)');
        await db.execute('CREATE INDEX idx_sync_queue_created ON sync_queue(created_at)');
      },
    );
  }

  Map<String, dynamic> _taskToDbMap(SyncTask task) => {
    'id': task.id,
    'type': task.type.index,
    'payload': _encodePayload(task.payload),
    'retry_count': task.retryCount,
    'created_at': task.createdAt.millisecondsSinceEpoch,
    'next_retry_at': task.nextRetryAt?.millisecondsSinceEpoch,
  };

  /// Encode payload to storable string format
  String _encodePayload(Map<String, dynamic> p) {
    return jsonEncode(p);
  }
}
