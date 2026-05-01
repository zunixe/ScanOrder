import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../core/db/database_helper.dart';
import '../../core/supabase/supabase_service.dart';

class StatsProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Map<String, int> dailyStats = {};
  Map<String, int> marketplaceStats = {};
  Map<String, int> categoryStats = {};
  int totalOrders = 0;
  int periodDays = 7;

  // Storage stats
  int dbSizeBytes = 0;
  int photoSizeBytes = 0;
  int photoCount = 0;

  Future<void> loadStats() async {
    final userId = SupabaseService().currentUser?.id;
    dailyStats = await _db.getDailyStats(periodDays);
    marketplaceStats = await _db.getMarketplaceStats();
    totalOrders = await _db.getTotalOrderCount(userId: userId);
    categoryStats = await _db.getCategoryStats(userId: userId);
    await _loadStorageStats();
    notifyListeners();
  }

  Future<void> _loadStorageStats() async {
    try {
      dbSizeBytes = 0;
      photoSizeBytes = 0;
      photoCount = 0;

      // Database size
      final dbPath = await getDatabasesPath();
      final dbFile = File(join(dbPath, 'scanorder.db'));
      if (await dbFile.exists()) {
        dbSizeBytes = await dbFile.length();
      }

      // Photos size
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory(docsDir.path);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.contains('scan_') && entity.path.endsWith('.jpg')) {
            photoCount++;
            photoSizeBytes += await entity.length();
          }
        }
      }
    } catch (e) {
      debugPrint('Storage stats error: $e');
    }
  }

  Future<void> setPeriod(int days) async {
    periodDays = days;
    await loadStats();
  }

  String get formattedDbSize => _formatBytes(dbSizeBytes);
  String get formattedPhotoSize => _formatBytes(photoSizeBytes);
  String get formattedTotalSize => _formatBytes(dbSizeBytes + photoSizeBytes);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
