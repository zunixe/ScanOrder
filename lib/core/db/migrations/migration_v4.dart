import 'package:sqflite/sqflite.dart';
import 'migration.dart';

/// V4: Add categories and order_categories tables.
class MigrationV4 extends DatabaseMigration {
  @override
  int get version => 4;

  @override
  String get description => 'Add categories and order_categories tables';

  @override
  Future<void> up(Database db) async {
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
      CREATE TABLE order_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        category_id INTEGER NOT NULL,
        assigned_at INTEGER NOT NULL,
        UNIQUE(order_id, category_id)
      )
    ''');
    await db.execute('CREATE INDEX idx_oc_order ON order_categories(order_id)');
    await db.execute('CREATE INDEX idx_oc_category ON order_categories(category_id)');
  }
}
