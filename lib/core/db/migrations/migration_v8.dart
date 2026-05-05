import 'package:sqflite/sqflite.dart';
import 'migration.dart';

/// V8: Add scanned_by column to track who actually scanned (differs from user_id for team members).
class MigrationV8 extends DatabaseMigration {
  @override
  int get version => 8;

  @override
  String get description => 'Add scanned_by column to scans table';

  @override
  Future<void> up(Database db) async {
    await db.execute('ALTER TABLE scans ADD COLUMN scanned_by TEXT');
  }
}
