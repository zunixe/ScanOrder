import 'migration.dart';
import 'migration_v2.dart';
import 'migration_v3.dart';
import 'migration_v4.dart';
import 'migration_v5.dart';
import 'migration_v6.dart';
import 'migration_v7.dart';
import 'migration_v8.dart';
import 'migration_v9.dart';

/// Registry of all database migrations, ordered by version.
/// Used by DatabaseHelper._onUpgrade to run the correct sequence of migrations.
class MigrationRegistry {
  /// All registered migrations, sorted by version ascending.
  static final List<DatabaseMigration> migrations = [
    MigrationV2(),
    MigrationV3(),
    MigrationV4(),
    MigrationV5(),
    MigrationV6(),
    MigrationV7(),
    MigrationV8(),
    MigrationV9(),
  ];

  /// Get migrations that need to run to upgrade from [oldVersion] to [newVersion].
  static List<DatabaseMigration> getMigrationsFor(int oldVersion, int newVersion) {
    return migrations
        .where((m) => m.version > oldVersion && m.version <= newVersion)
        .toList();
  }

  /// Get a specific migration by version, or null if not found.
  static DatabaseMigration? getMigration(int version) {
    for (final m in migrations) {
      if (m.version == version) return m;
    }
    return null;
  }

  /// Current (latest) database version.
  static int get currentVersion => migrations.last.version;
}
