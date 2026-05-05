import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../logging/logger.dart';
import '../../models/scan_record.dart';
import '../../models/category.dart';

/// Full backup & restore service.
/// Exports all local data as JSON, imports from JSON file.
class BackupService {
  final _db = DatabaseHelper.instance;

  /// Create a full backup JSON file and share it.
  Future<void> backupAndShare(String? userId) async {
    try {
      final data = await _collectAllData(userId);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/scanorder_backup_$timestamp.json');
      await file.writeAsString(jsonStr);

      AppLogger.info('BackupService', 'Backup created: ${file.path}');

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'ScanOrder Backup $timestamp',
      );
    } catch (e) {
      AppLogger.error('BackupService', 'Backup failed', exception: e);
      rethrow;
    }
  }

  /// Collect all data from local DB into a map.
  Future<Map<String, dynamic>> _collectAllData(String? userId) async {
    final scans = await _db.getAllScans(userId: userId);
    final categories = await _db.getAllCategories(userId: userId);

    // Attach categories to each scan
    for (var i = 0; i < scans.length; i++) {
      if (scans[i].id != null) {
        final cats = await _db.getCategoriesForOrder(scans[i].id!);
        scans[i] = scans[i].copyWith(categories: cats);
      }
    }

    return {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'scans': scans.map((s) => s.toMap()).toList(),
      'categories': categories.map((c) => c.toMap()).toList(),
    };
  }

  /// Restore data from a JSON file.
  /// Returns a map with 'scans' and 'categories' counts.
  Future<Map<String, int>> restoreFromFile(String filePath) async {
    try {
      final file = File(filePath);
      final jsonStr = await file.readAsString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      final version = data['version'] as int? ?? 1;
      if (version > 1) {
        throw FormatException('Backup version $version not supported');
      }

      final scanList = data['scans'] as List<dynamic>;
      final catList = data['categories'] as List<dynamic>;

      int scanCount = 0;
      int catCount = 0;

      // Restore categories first (scans reference them)
      for (final catMap in catList) {
        final cat = ScanCategory.fromMap(catMap as Map<String, dynamic>);
        try {
          await _db.insertCategory(cat);
          catCount++;
        } catch (e) {
          AppLogger.info('BackupService', 'Skip existing category: ${cat.name}');
        }
      }

      // Restore scans
      for (final scanMap in scanList) {
        final scan = ScanRecord.fromMap(scanMap as Map<String, dynamic>);
        try {
          final id = await _db.insertScan(scan);
          // Restore scan-category junctions
          for (final cat in scan.categories) {
            if (cat.id != null && id > 0) {
              await _db.assignCategoryToOrder(id, cat.id!);
            }
          }
          scanCount++;
        } catch (e) {
          AppLogger.info('BackupService', 'Skip existing scan: ${scan.resi}');
        }
      }

      AppLogger.info('BackupService', 'Restored: $scanCount scans, $catCount categories');
      return {'scans': scanCount, 'categories': catCount};
    } catch (e) {
      AppLogger.error('BackupService', 'Restore failed', exception: e);
      rethrow;
    }
  }
}
