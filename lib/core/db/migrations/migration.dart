import 'package:sqflite/sqflite.dart';

/// Base class for database migrations.
/// Each migration upgrades the database from version (id-1) to version (id).
///
/// Naming convention: MigrationV2 upgrades from v1 → v2.
abstract class DatabaseMigration {
  /// Target database version after this migration runs.
  int get version;

  /// Human-readable description of what this migration does.
  String get description;

  /// Execute the migration.
  /// [db] is the open database connection.
  /// This method must be idempotent where possible (safe to re-run).
  Future<void> up(Database db);

  /// Optional: rollback the migration (for testing/development only).
  /// Not used in production — SQLite doesn't support transactional DDL rollback.
  Future<void> down(Database db) async {}
}
