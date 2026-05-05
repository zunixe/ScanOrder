import 'package:sqflite/sqflite.dart';
import 'migration.dart';

/// V3: Add user_id column and index to scans table.
class MigrationV3 extends DatabaseMigration {
  @override
  int get version => 3;

  @override
  String get description => 'Add user_id column and index to scans table';

  @override
  Future<void> up(Database db) async {
    await db.execute('ALTER TABLE scans ADD COLUMN user_id TEXT');
    await db.execute('CREATE INDEX idx_user_id ON scans(user_id)');
  }
}
