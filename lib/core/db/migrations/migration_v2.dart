import 'package:sqflite/sqflite.dart';
import 'migration.dart';

/// V2: Add photo_path column to scans table.
class MigrationV2 extends DatabaseMigration {
  @override
  int get version => 2;

  @override
  String get description => 'Add photo_path column to scans table';

  @override
  Future<void> up(Database db) async {
    await db.execute('ALTER TABLE scans ADD COLUMN photo_path TEXT');
  }
}
