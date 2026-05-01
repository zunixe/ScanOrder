import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../core/supabase/supabase_service.dart';

/// Task yang perlu di-sync ke Supabase
enum SyncTaskType { insertOrder, uploadPhoto, syncSubscription }

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
      p.entries.map((e) => '${e.key}=${e.value ?? ''}').join('|');

  static Map<String, dynamic> _decodePayload(String raw) {
    // Simple decode: we store structured data as JSON-like string
    // For complex payloads we use a helper
    try {
      final map = <String, dynamic>{};
      // Parse key=value pairs separated by |
      for (final pair in raw.split('|')) {
        final parts = pair.split('=');
        if (parts.length == 2) {
          map[parts[0]] = parts[1];
        }
      }
      return map;
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
      return true;
    } catch (e) {
      debugPrint('[SyncQueue] insertOrder error: $e');
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
      // Update photo_url di orders table (Supabase)
      final client = _supabase.client;
      if (client != null && p['resi'] != null) {
        try {
          await client
              .from('scans')
              .update({'photo_url': url})
              .eq('resi', p['resi'] as String);
        } catch (_) {}
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
    return p.entries.map((e) => '${e.key}=${e.value}').join('|');
  }
}
