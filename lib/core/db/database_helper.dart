import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/order.dart';
import '../../models/category.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'scanorder.db');

    return await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        resi TEXT NOT NULL UNIQUE,
        marketplace TEXT NOT NULL,
        scanned_at INTEGER NOT NULL,
        date TEXT NOT NULL,
        photo_path TEXT,
        user_id TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_date ON orders(date)');
    await db.execute('CREATE INDEX idx_marketplace ON orders(marketplace)');
    await db.execute('CREATE INDEX idx_user_id ON orders(user_id)');
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

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE orders ADD COLUMN photo_path TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE orders ADD COLUMN user_id TEXT');
      await db.execute('CREATE INDEX idx_user_id ON orders(user_id)');
    }
    if (oldVersion < 4) {
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

  Future<int> insertOrder(ScannedOrder order, {String? userId}) async {
    final db = await database;
    final map = order.toMap();
    if (userId != null) map['user_id'] = userId;
    return await db.insert(
      'orders',
      map,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<ScannedOrder?> findByResi(String resi) async {
    final db = await database;
    final maps = await db.query(
      'orders',
      where: 'resi = ?',
      whereArgs: [resi],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ScannedOrder.fromMap(maps.first);
  }

  Future<List<ScannedOrder>> getOrdersByDate(String date, {String? userId}) async {
    final db = await database;
    if (userId != null) {
      final maps = await db.query(
        'orders',
        where: 'date = ? AND user_id = ?',
        whereArgs: [date, userId],
        orderBy: 'scanned_at DESC',
      );
      return maps.map((m) => ScannedOrder.fromMap(m)).toList();
    }
    final maps = await db.query(
      'orders',
      where: 'date = ? AND user_id IS NULL',
      whereArgs: [date],
      orderBy: 'scanned_at DESC',
    );
    return maps.map((m) => ScannedOrder.fromMap(m)).toList();
  }

  Future<int> updateOrderPhoto(int id, String? photoPath) async {
    final db = await database;
    return await db.update(
      'orders',
      {'photo_path': photoPath},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<ScannedOrder>> searchOrders(String query, {String? userId}) async {
    final db = await database;
    if (userId != null) {
      final maps = await db.query(
        'orders',
        where: 'resi LIKE ? AND user_id = ?',
        whereArgs: ['%$query%', userId],
        orderBy: 'scanned_at DESC',
        limit: 100,
      );
      return maps.map((m) => ScannedOrder.fromMap(m)).toList();
    }
    final maps = await db.query(
      'orders',
      where: 'resi LIKE ? AND user_id IS NULL',
      whereArgs: ['%$query%'],
      orderBy: 'scanned_at DESC',
      limit: 100,
    );
    return maps.map((m) => ScannedOrder.fromMap(m)).toList();
  }

  Future<int> getTotalOrderCount({String? userId}) async {
    final db = await database;
    if (userId != null) {
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM orders WHERE user_id = ?', [userId]);
      return Sqflite.firstIntValue(result) ?? 0;
    }
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM orders WHERE user_id IS NULL');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getOrderCountByDate(String date) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM orders WHERE date = ?',
      [date],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<String, int>> getDailyStats(int days) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startStr =
        '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';

    final result = await db.rawQuery(
      'SELECT date, COUNT(*) as count FROM orders WHERE date >= ? GROUP BY date ORDER BY date ASC',
      [startStr],
    );

    final stats = <String, int>{};
    for (final row in result) {
      stats[row['date'] as String] = row['count'] as int;
    }
    return stats;
  }

  Future<Map<String, int>> getMarketplaceStats({String? date}) async {
    final db = await database;
    String query =
        'SELECT marketplace, COUNT(*) as count FROM orders';
    List<Object?> args = [];

    if (date != null) {
      query += ' WHERE date = ?';
      args.add(date);
    }
    query += ' GROUP BY marketplace ORDER BY count DESC';

    final result = await db.rawQuery(query, args);
    final stats = <String, int>{};
    for (final row in result) {
      stats[row['marketplace'] as String] = row['count'] as int;
    }
    return stats;
  }

  Future<List<ScannedOrder>> getAllOrders({String? userId}) async {
    final db = await database;
    List<Map<String, Object?>> maps;
    if (userId != null) {
      maps = await db.query('orders', where: 'user_id = ?', whereArgs: [userId], orderBy: 'scanned_at DESC');
    } else {
      maps = await db.query('orders', where: 'user_id IS NULL', orderBy: 'scanned_at DESC');
    }
    return maps.map((m) => ScannedOrder.fromMap(m)).toList();
  }

  Future<int> deleteOrder(int id) async {
    final db = await database;
    return await db.delete('orders', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> getDistinctDates({String? userId}) async {
    final db = await database;
    if (userId != null) {
      final result = await db.rawQuery(
        'SELECT DISTINCT date FROM orders WHERE user_id = ? ORDER BY date DESC',
        [userId],
      );
      return result.map((r) => r['date'] as String).toList();
    }
    final result = await db.rawQuery(
      'SELECT DISTINCT date FROM orders WHERE user_id IS NULL ORDER BY date DESC',
    );
    return result.map((r) => r['date'] as String).toList();
  }

  // ── Category CRUD ──

  Future<int> insertCategory(ScanCategory category) async {
    final db = await database;
    return await db.insert('categories', category.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<ScanCategory>> getAllCategories({String? userId}) async {
    final db = await database;
    List<Map<String, Object?>> maps;
    if (userId != null) {
      maps = await db.query('categories', where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at ASC');
    } else {
      maps = await db.query('categories', where: 'user_id IS NULL', orderBy: 'created_at ASC');
    }
    return maps.map((m) => ScanCategory.fromMap(m)).toList();
  }

  Future<int> updateCategory(ScanCategory category) async {
    final db = await database;
    return await db.update('categories', category.toMap(), where: 'id = ?', whereArgs: [category.id]);
  }

  Future<int> deleteCategory(int id) async {
    final db = await database;
    await db.delete('order_categories', where: 'category_id = ?', whereArgs: [id]);
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // ── Order-Category Relations ──

  Future<int> assignCategoryToOrder(int orderId, int categoryId) async {
    final db = await database;
    return await db.insert(
      'order_categories',
      {'order_id': orderId, 'category_id': categoryId, 'assigned_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<ScanCategory>> getCategoriesForOrder(int orderId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT c.* FROM categories c
      INNER JOIN order_categories oc ON c.id = oc.category_id
      WHERE oc.order_id = ?
      ORDER BY c.name ASC
    ''', [orderId]);
    return result.map((m) => ScanCategory.fromMap(m)).toList();
  }

  Future<List<ScannedOrder>> getOrdersByCategory(int categoryId, {String? userId}) async {
    final db = await database;
    String userFilter = userId != null ? 'AND o.user_id = ?' : 'AND o.user_id IS NULL';
    List<Object?> args = userId != null ? [categoryId, userId] : [categoryId];
    final result = await db.rawQuery('''
      SELECT o.* FROM orders o
      INNER JOIN order_categories oc ON o.id = oc.order_id
      WHERE oc.category_id = ? $userFilter
      ORDER BY o.scanned_at DESC
    ''', args);
    return result.map((m) => ScannedOrder.fromMap(m)).toList();
  }

  Future<Map<String, int>> getCategoryStats({String? userId}) async {
    final db = await database;
    String userFilter = userId != null ? 'AND o.user_id = ?' : 'AND o.user_id IS NULL';
    List<Object?> args = userId != null ? [userId] : [];
    final result = await db.rawQuery('''
      SELECT c.name, COUNT(oc.order_id) as count
      FROM categories c
      LEFT JOIN order_categories oc ON c.id = oc.category_id
      LEFT JOIN orders o ON oc.order_id = o.id
      WHERE c.user_id ${userId != null ? '= ?' : 'IS NULL'} $userFilter
      GROUP BY c.id
      ORDER BY count DESC
    ''', args);
    final stats = <String, int>{};
    for (final row in result) {
      stats[row['name'] as String] = (row['count'] as int?) ?? 0;
    }
    return stats;
  }

  Future<void> removeCategoryFromOrder(int orderId, int categoryId) async {
    final db = await database;
    await db.delete('order_categories', where: 'order_id = ? AND category_id = ?', whereArgs: [orderId, categoryId]);
  }
}
