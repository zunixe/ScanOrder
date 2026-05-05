import 'package:sqflite/sqflite.dart';
import 'migration.dart';

/// V7: Add team_id column to scans for team data filtering.
class MigrationV7 extends DatabaseMigration {
  @override
  int get version => 7;

  @override
  String get description => 'Add team_id column and index to scans table';

  @override
  Future<void> up(Database db) async {
    await db.execute('ALTER TABLE scans ADD COLUMN team_id TEXT');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_team_id ON scans(team_id)');
  }
}
