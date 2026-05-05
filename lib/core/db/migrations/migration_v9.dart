import 'package:sqflite/sqflite.dart';
import 'migration.dart';

/// V9: Add sync_status column to scans table for tracking sync state.
class MigrationV9 extends DatabaseMigration {
  @override
  int get version => 9;

  @override
  String get description => 'Add sync_status column to scans table';

  @override
  Future<void> up(Database db) async {
    await db.execute("ALTER TABLE scans ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'synced'");
  }
}
