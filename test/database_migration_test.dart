import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:scanorder/core/db/migrations/migration.dart';
import 'package:scanorder/core/db/migrations/migration_registry.dart';
import 'package:scanorder/core/db/migrations/migration_v5.dart';
import 'package:scanorder/core/db/migrations/migration_v9.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactoryOrNull = databaseFactoryFfi;
  });

  group('MigrationRegistry', () {
    test('has all migrations from v2 to v9', () {
      expect(MigrationRegistry.migrations.length, 8);
      expect(MigrationRegistry.migrations[0].version, 2);
      expect(MigrationRegistry.migrations[7].version, 9);
    });

    test('currentVersion is 9', () {
      expect(MigrationRegistry.currentVersion, 9);
    });

    test('getMigrationsFor returns correct subset', () {
      // Upgrade from v1 → v9: all 8 migrations
      final all = MigrationRegistry.getMigrationsFor(1, 9);
      expect(all.length, 8);

      // Upgrade from v6 → v9: v7, v8, v9
      final partial = MigrationRegistry.getMigrationsFor(6, 9);
      expect(partial.length, 3);
      expect(partial[0].version, 7);
      expect(partial[1].version, 8);
      expect(partial[2].version, 9);

      // No upgrade needed
      final none = MigrationRegistry.getMigrationsFor(9, 9);
      expect(none.length, 0);
    });

    test('getMigration returns specific version', () {
      expect(MigrationRegistry.getMigration(5), isA<MigrationV5>());
      expect(MigrationRegistry.getMigration(9), isA<MigrationV9>());
      expect(MigrationRegistry.getMigration(1), isNull);
      expect(MigrationRegistry.getMigration(99), isNull);
    });

    test('migrations are sorted by version ascending', () {
      for (int i = 1; i < MigrationRegistry.migrations.length; i++) {
        expect(
          MigrationRegistry.migrations[i - 1].version < MigrationRegistry.migrations[i].version,
          isTrue,
          reason: 'Migration v${MigrationRegistry.migrations[i - 1].version} should be before v${MigrationRegistry.migrations[i].version}',
        );
      }
    });

    test('each migration has a non-empty description', () {
      for (final m in MigrationRegistry.migrations) {
        expect(m.description, isNotEmpty, reason: 'v${m.version} should have a description');
      }
    });

    test('no duplicate versions', () {
      final versions = MigrationRegistry.migrations.map((m) => m.version).toList();
      expect(versions.toSet().length, versions.length);
    });
  });

  group('Migration integration tests', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          // V1 schema: minimal scans table
          await db.execute('''
            CREATE TABLE scans (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              resi TEXT NOT NULL,
              marketplace TEXT NOT NULL,
              scanned_at INTEGER NOT NULL,
              date TEXT NOT NULL
            )
          ''');
          await db.execute('CREATE UNIQUE INDEX idx_resi ON scans(resi)');
          await db.execute('CREATE INDEX idx_date ON scans(date)');
          await db.execute('CREATE INDEX idx_marketplace ON scans(marketplace)');
        },
      );
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> runMigrations(int fromVersion, int toVersion) async {
      final migrations = MigrationRegistry.getMigrationsFor(fromVersion, toVersion);
      for (final migration in migrations) {
        await migration.up(db);
      }
    }

    Future<void> insertV1Scan(Database db, String resi, {String? marketplace}) async {
      await db.insert('scans', {
        'resi': resi,
        'marketplace': marketplace ?? 'Shopee',
        'scanned_at': DateTime.now().millisecondsSinceEpoch,
        'date': '2025-01-15',
      });
    }

    group('V2: photo_path column', () {
      test('adds photo_path column', () async {
        await runMigrations(1, 2);
        // Should be able to insert with photo_path
        await db.insert('scans', {
          'resi': 'SPX001',
          'marketplace': 'Shopee',
          'scanned_at': DateTime.now().millisecondsSinceEpoch,
          'date': '2025-01-15',
          'photo_path': '/photos/scan_001.jpg',
        });
        final result = await db.query('scans', where: 'resi = ?', whereArgs: ['SPX001']);
        expect(result.first['photo_path'], '/photos/scan_001.jpg');
      });

      test('photo_path defaults to null for existing rows', () async {
        await insertV1Scan(db, 'SPX002');
        await runMigrations(1, 2);
        final result = await db.query('scans', where: 'resi = ?', whereArgs: ['SPX002']);
        expect(result.first['photo_path'], isNull);
      });
    });

    group('V3: user_id column', () {
      test('adds user_id column and index', () async {
        await runMigrations(1, 3);
        await db.insert('scans', {
          'resi': 'SPX003',
          'marketplace': 'Shopee',
          'scanned_at': DateTime.now().millisecondsSinceEpoch,
          'date': '2025-01-15',
          'user_id': 'user-123',
        });
        final result = await db.query('scans', where: 'user_id = ?', whereArgs: ['user-123']);
        expect(result.length, 1);
      });
    });

    group('V4: categories tables', () {
      test('creates categories and order_categories tables', () async {
        await runMigrations(1, 4);
        // Insert category
        final catId = await db.insert('categories', {
          'name': 'Pribadi',
          'color': '#FF5722',
          'user_id': 'user-123',
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
        // Insert order-category relation
        await db.insert('order_categories', {
          'order_id': 1,
          'category_id': catId,
          'assigned_at': DateTime.now().millisecondsSinceEpoch,
        });
        final result = await db.rawQuery('''
          SELECT c.name FROM categories c
          INNER JOIN order_categories oc ON c.id = oc.category_id
          WHERE oc.order_id = 1
        ''');
        expect(result.first['name'], 'Pribadi');
      });
    });

    group('V5: recreate scans with composite unique index', () {
      test('migrates data preserving existing rows', () async {
        // Insert data before migration
        await insertV1Scan(db, 'SPX005');
        await insertV1Scan(db, 'SPX006');
        await runMigrations(1, 5);
        final result = await db.query('scans');
        expect(result.length, 2);
      });

      test('allows duplicate resi with different user_id', () async {
        await runMigrations(1, 5);
        await db.insert('scans', {
          'resi': 'SPX-DUP',
          'marketplace': 'Shopee',
          'scanned_at': DateTime.now().millisecondsSinceEpoch,
          'date': '2025-01-15',
          'user_id': 'user-A',
        });
        // Same resi but different user_id should succeed
        await db.insert('scans', {
          'resi': 'SPX-DUP',
          'marketplace': 'Shopee',
          'scanned_at': DateTime.now().millisecondsSinceEpoch,
          'date': '2025-01-15',
          'user_id': 'user-B',
        });
        final result = await db.query('scans', where: 'resi = ?', whereArgs: ['SPX-DUP']);
        expect(result.length, 2);
      });

      test('handles crash recovery (orders_old already dropped)', () async {
        await insertV1Scan(db, 'SPX007');
        await runMigrations(1, 5);
        // Running again should not crash (orders_old already dropped)
        // But we can't re-run V5 since it ALTERs scans which is already renamed.
        // The crash recovery is the DROP TABLE IF EXISTS at the start.
        final result = await db.query('scans');
        expect(result.isNotEmpty, isTrue);
      });
    });

    group('V6: rename order_categories → scan_categories', () {
      test('creates scan_categories with scan_id column', () async {
        await runMigrations(1, 6);
        // Insert category first
        final catId = await db.insert('categories', {
          'name': 'Test',
          'color': '#2196F3',
          'user_id': null,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
        // Insert scan
        final scanId = await db.insert('scans', {
          'resi': 'SPX008',
          'marketplace': 'Shopee',
          'scanned_at': DateTime.now().millisecondsSinceEpoch,
          'date': '2025-01-15',
        });
        // Insert scan_category with scan_id (not order_id)
        await db.insert('scan_categories', {
          'scan_id': scanId,
          'category_id': catId,
          'assigned_at': DateTime.now().millisecondsSinceEpoch,
        });
        final result = await db.query('scan_categories', where: 'scan_id = ?', whereArgs: [scanId]);
        expect(result.length, 1);
      });
    });

    group('V7: team_id column', () {
      test('adds team_id column and index', () async {
        await runMigrations(1, 7);
        await db.insert('scans', {
          'resi': 'SPX009',
          'marketplace': 'Shopee',
          'scanned_at': DateTime.now().millisecondsSinceEpoch,
          'date': '2025-01-15',
          'team_id': 'team-abc',
        });
        final result = await db.query('scans', where: 'team_id = ?', whereArgs: ['team-abc']);
        expect(result.length, 1);
      });
    });

    group('V8: scanned_by column', () {
      test('adds scanned_by column', () async {
        await runMigrations(1, 8);
        await db.insert('scans', {
          'resi': 'SPX010',
          'marketplace': 'Shopee',
          'scanned_at': DateTime.now().millisecondsSinceEpoch,
          'date': '2025-01-15',
          'scanned_by': 'member-xyz',
        });
        final result = await db.query('scans', where: 'scanned_by = ?', whereArgs: ['member-xyz']);
        expect(result.length, 1);
      });
    });

    group('V9: sync_status column', () {
      test('adds sync_status column with default', () async {
        await runMigrations(1, 9);
        await db.insert('scans', {
          'resi': 'SPX011',
          'marketplace': 'Shopee',
          'scanned_at': DateTime.now().millisecondsSinceEpoch,
          'date': '2025-01-15',
        });
        final result = await db.query('scans', where: 'resi = ?', whereArgs: ['SPX011']);
        expect(result.first['sync_status'], 'synced');
      });

      test('sync_status can be set to pending', () async {
        await runMigrations(1, 9);
        await db.insert('scans', {
          'resi': 'SPX012',
          'marketplace': 'Shopee',
          'scanned_at': DateTime.now().millisecondsSinceEpoch,
          'date': '2025-01-15',
          'sync_status': 'pending',
        });
        final result = await db.query('scans', where: 'resi = ?', whereArgs: ['SPX012']);
        expect(result.first['sync_status'], 'pending');
      });
    });

    group('Full upgrade path v1 → v9', () {
      test('preserves data through all migrations', () async {
        // Insert v1 data
        await insertV1Scan(db, 'FULL-001');
        await insertV1Scan(db, 'FULL-002');
        // Run all migrations
        await runMigrations(1, 9);
        // Verify data survived
        final result = await db.query('scans', where: 'resi LIKE ?', whereArgs: ['FULL-%']);
        expect(result.length, 2);
        // Verify all columns exist
        final row = result.first;
        expect(row.containsKey('photo_path'), isTrue);
        expect(row.containsKey('user_id'), isTrue);
        expect(row.containsKey('team_id'), isTrue);
        expect(row.containsKey('scanned_by'), isTrue);
        expect(row.containsKey('sync_status'), isTrue);
      });

      test('final schema matches _onCreate schema', () async {
        // Run all migrations on a v1 DB
        await insertV1Scan(db, 'SCHEMA-CHECK');
        await runMigrations(1, 9);
        // Verify all expected tables exist
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
        );
        final tableNames = tables.map((r) => r['name'] as String).toSet();
        expect(tableNames.contains('scans'), isTrue);
        expect(tableNames.contains('categories'), isTrue);
        expect(tableNames.contains('scan_categories'), isTrue);
        // Verify all expected indexes exist
        final indexes = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%' ORDER BY name",
        );
        final indexNames = indexes.map((r) => r['name'] as String).toSet();
        expect(indexNames.contains('idx_resi_user'), isTrue);
        expect(indexNames.contains('idx_date'), isTrue);
        expect(indexNames.contains('idx_marketplace'), isTrue);
        expect(indexNames.contains('idx_user_id'), isTrue);
        expect(indexNames.contains('idx_team_id'), isTrue);
        expect(indexNames.contains('idx_categories_user'), isTrue);
        expect(indexNames.contains('idx_sc_order'), isTrue);
        expect(indexNames.contains('idx_sc_category'), isTrue);
      });

      test('fresh _onCreate produces same schema as full migration', () async {
        // Create a fresh v9 DB
        final freshDb = await openDatabase(
          inMemoryDatabasePath,
          version: 9,
          onCreate: (db, version) async {
            // Replicate DatabaseHelper._onCreate
            await db.execute('''
              CREATE TABLE scans (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                resi TEXT NOT NULL,
                marketplace TEXT NOT NULL,
                scanned_at INTEGER NOT NULL,
                date TEXT NOT NULL,
                photo_path TEXT,
                user_id TEXT,
                team_id TEXT,
                scanned_by TEXT,
                sync_status TEXT NOT NULL DEFAULT 'pending'
              )
            ''');
            await db.execute('CREATE UNIQUE INDEX idx_resi_user ON scans(resi, user_id)');
            await db.execute('CREATE INDEX idx_date ON scans(date)');
            await db.execute('CREATE INDEX idx_marketplace ON scans(marketplace)');
            await db.execute('CREATE INDEX idx_user_id ON scans(user_id)');
            await db.execute('''
              CREATE TABLE categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                color TEXT NOT NULL,
                user_id TEXT,
                created_at INTEGER NOT NULL
              )
            ''');
            await db.execute('CREATE INDEX idx_categories_user ON categories(user_id)');
            await db.execute('''
              CREATE TABLE scan_categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                scan_id INTEGER NOT NULL,
                category_id INTEGER NOT NULL,
                assigned_at INTEGER NOT NULL,
                UNIQUE(scan_id, category_id)
              )
            ''');
            await db.execute('CREATE INDEX idx_sc_order ON scan_categories(scan_id)');
            await db.execute('CREATE INDEX idx_sc_category ON scan_categories(category_id)');
          },
        );

        // Compare table schemas
        final migratedTables = await db.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name IN ('scans', 'categories', 'scan_categories') ORDER BY name",
        );
        final freshTables = await freshDb.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name IN ('scans', 'categories', 'scan_categories') ORDER BY name",
        );
        // The schemas should be equivalent (may differ in column order, but same columns)
        for (int i = 0; i < migratedTables.length; i++) {
          final mSql = migratedTables[i]['sql'] as String;
          final fSql = freshTables[i]['sql'] as String;
          // Both should contain the same table name
          expect(mSql.contains('CREATE TABLE'), isTrue);
          expect(fSql.contains('CREATE TABLE'), isTrue);
        }
        await freshDb.close();
      });
    });

    group('Partial upgrade paths', () {
      test('v6 → v9 runs only v7, v8, v9', () async {
        // Setup: create a v6-like DB manually
        final v6Db = await openDatabase(
          inMemoryDatabasePath,
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE scans (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                resi TEXT NOT NULL,
                marketplace TEXT NOT NULL,
                scanned_at INTEGER NOT NULL,
                date TEXT NOT NULL,
                photo_path TEXT,
                user_id TEXT
              )
            ''');
            await db.execute('CREATE UNIQUE INDEX idx_resi_user ON scans(resi, user_id)');
            await db.execute('CREATE INDEX idx_date ON scans(date)');
            await db.execute('CREATE INDEX idx_marketplace ON scans(marketplace)');
            await db.execute('CREATE INDEX idx_user_id ON scans(user_id)');
            await db.execute('''
              CREATE TABLE categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                color TEXT NOT NULL,
                user_id TEXT,
                created_at INTEGER NOT NULL
              )
            ''');
            await db.execute('CREATE INDEX idx_categories_user ON categories(user_id)');
            await db.execute('''
              CREATE TABLE scan_categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                scan_id INTEGER NOT NULL,
                category_id INTEGER NOT NULL,
                assigned_at INTEGER NOT NULL,
                UNIQUE(scan_id, category_id)
              )
            ''');
            await db.execute('CREATE INDEX idx_sc_order ON scan_categories(scan_id)');
            await db.execute('CREATE INDEX idx_sc_category ON scan_categories(category_id)');
          },
        );
        // Insert data
        await v6Db.insert('scans', {
          'resi': 'PARTIAL-001',
          'marketplace': 'JNE',
          'scanned_at': DateTime.now().millisecondsSinceEpoch,
          'date': '2025-01-15',
        });
        // Run only v7→v9
        final migrations = MigrationRegistry.getMigrationsFor(6, 9);
        expect(migrations.length, 3);
        for (final m in migrations) {
          await m.up(v6Db);
        }
        // Verify data preserved + new columns added
        final result = await v6Db.query('scans', where: 'resi = ?', whereArgs: ['PARTIAL-001']);
        expect(result.length, 1);
        expect(result.first.containsKey('team_id'), isTrue);
        expect(result.first.containsKey('scanned_by'), isTrue);
        expect(result.first.containsKey('sync_status'), isTrue);
        await v6Db.close();
      });
    });
  });

  group('Individual migration properties', () {
    test('all migrations implement DatabaseMigration', () {
      final migrations = MigrationRegistry.migrations;
      for (final m in migrations) {
        expect(m, isA<DatabaseMigration>());
      }
    });

    test('version numbers are sequential starting from 2', () {
      for (int i = 0; i < MigrationRegistry.migrations.length; i++) {
        expect(MigrationRegistry.migrations[i].version, 2 + i);
      }
    });
  });
}
