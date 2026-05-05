import 'package:sqflite/sqflite.dart';
import 'migration.dart';

/// V5: Recreate scans table with UNIQUE(resi, user_id) instead of UNIQUE(resi).
///
/// This is a destructive migration that:
/// 1. Renames scans → orders_old
/// 2. Creates new scans table with composite unique index
/// 3. Copies data (keeping latest row per resi+user_id to resolve conflicts)
/// 4. Drops orders_old
class MigrationV5 extends DatabaseMigration {
  @override
  int get version => 5;

  @override
  String get description => 'Recreate scans with UNIQUE(resi, user_id) composite index';

  @override
  Future<void> up(Database db) async {
    // Handle partial migration from previous crash: drop orders_old if it exists
    try {
      await db.execute('DROP TABLE IF EXISTS orders_old');
    } catch (_) {}
    await db.execute('ALTER TABLE scans RENAME TO orders_old');
    // Drop indexes that referenced the old table — they now point to orders_old
    // and will block creating new indexes with the same names on the new scans table.
    // SQLite auto-drops indexes when the table they reference is dropped,
    // but since orders_old still exists, we need to drop them explicitly.
    try { await db.execute('DROP INDEX IF EXISTS idx_resi'); } catch (_) {}
    try { await db.execute('DROP INDEX IF EXISTS idx_date'); } catch (_) {}
    try { await db.execute('DROP INDEX IF EXISTS idx_marketplace'); } catch (_) {}
    try { await db.execute('DROP INDEX IF EXISTS idx_user_id'); } catch (_) {}
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
    // Copy data: keep latest row per (resi, user_id) to resolve old global UNIQUE(resi) conflicts
    await db.execute('''
      INSERT INTO scans (resi, marketplace, scanned_at, date, photo_path, user_id)
      SELECT resi, marketplace, scanned_at, date, photo_path, user_id
      FROM orders_old
      WHERE id IN (
        SELECT MAX(id) FROM orders_old GROUP BY resi, COALESCE(user_id, '')
      )
    ''');
    await db.execute('DROP TABLE orders_old');
  }
}
