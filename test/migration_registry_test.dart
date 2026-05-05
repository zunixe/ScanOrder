import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/db/migrations/migration_registry.dart';
import 'package:scanorder/core/db/migrations/migration_v9.dart';

void main() {
  group('MigrationRegistry', () {
    test('has 8 migrations registered', () {
      expect(MigrationRegistry.migrations.length, 8);
    });

    test('migrations are sorted by version ascending', () {
      for (int i = 1; i < MigrationRegistry.migrations.length; i++) {
        expect(
          MigrationRegistry.migrations[i].version > MigrationRegistry.migrations[i - 1].version,
          true,
        );
      }
    });

    test('currentVersion matches last migration', () {
      expect(MigrationRegistry.currentVersion, MigrationV9().version);
    });

    test('getMigrationsFor returns correct range', () {
      final migrations = MigrationRegistry.getMigrationsFor(1, 4);
      expect(migrations.length, 3); // v2, v3, v4
      expect(migrations[0].version, 2);
      expect(migrations[1].version, 3);
      expect(migrations[2].version, 4);
    });

    test('getMigrationsFor returns empty for same version', () {
      final migrations = MigrationRegistry.getMigrationsFor(5, 5);
      expect(migrations, isEmpty);
    });

    test('getMigrationsFor returns all for 0 to current', () {
      final migrations = MigrationRegistry.getMigrationsFor(0, MigrationRegistry.currentVersion);
      expect(migrations.length, 8);
    });

    test('getMigration returns correct migration', () {
      final m2 = MigrationRegistry.getMigration(2);
      expect(m2, isNotNull);
      expect(m2!.version, 2);
    });

    test('getMigration returns null for unknown version', () {
      final m = MigrationRegistry.getMigration(999);
      expect(m, isNull);
    });

    test('each migration has a description', () {
      for (final m in MigrationRegistry.migrations) {
        expect(m.description, isNotEmpty);
      }
    });

    test('migration versions are sequential starting from 2', () {
      for (int i = 0; i < MigrationRegistry.migrations.length; i++) {
        expect(MigrationRegistry.migrations[i].version, i + 2);
      }
    });
  });
}
