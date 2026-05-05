import 'package:sqflite/sqflite.dart';
import 'migration.dart';

/// V6: Rename order_categories → scan_categories, rename column order_id → scan_id.
///
/// SQLite doesn't support ALTER COLUMN, so this recreates scan_categories.
class MigrationV6 extends DatabaseMigration {
  @override
  int get version => 6;

  @override
  String get description => 'Rename order_categories → scan_categories, order_id → scan_id';

  @override
  Future<void> up(Database db) async {
    // Rename order_categories → scan_categories
    await db.execute('ALTER TABLE order_categories RENAME TO scan_categories');
    // SQLite doesn't support ALTER COLUMN, so recreate scan_categories with scan_id
    try {
      await db.execute('DROP TABLE IF EXISTS scan_categories_old');
    } catch (_) {}
    await db.execute('ALTER TABLE scan_categories RENAME TO scan_categories_old');
    await db.execute('''
      CREATE TABLE scan_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scan_id INTEGER NOT NULL,
        category_id INTEGER NOT NULL,
        assigned_at INTEGER NOT NULL,
        UNIQUE(scan_id, category_id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sc_order ON scan_categories(scan_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sc_category ON scan_categories(category_id)');
    await db.execute('''
      INSERT INTO scan_categories (id, scan_id, category_id, assigned_at)
      SELECT id, order_id, category_id, assigned_at FROM scan_categories_old
    ''');
    await db.execute('DROP TABLE scan_categories_old');
  }
}
