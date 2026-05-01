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
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
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
    if (oldVersion < 5) {
      // Recreate orders table with UNIQUE(resi, user_id) instead of UNIQUE(resi)
      // Handle partial migration from previous crash: drop orders_old if it exists
      try { await db.execute('DROP TABLE IF EXISTS orders_old'); } catch (_) {}
      await db.execute('ALTER TABLE orders RENAME TO orders_old');
      await db.execute('''
        CREATE TABLE orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          resi TEXT NOT NULL,
          marketplace TEXT NOT NULL,
          scanned_at INTEGER NOT NULL,
          date TEXT NOT NULL,
          photo_path TEXT,
          user_id TEXT
        )
      ''');
      await db.execute('CREATE UNIQUE INDEX idx_resi_user ON orders(resi, user_id)');
      await db.execute('CREATE INDEX idx_date ON orders(date)');
      await db.execute('CREATE INDEX idx_marketplace ON orders(marketplace)');
      await db.execute('CREATE INDEX idx_user_id ON orders(user_id)');
      // Copy data: keep latest row per (resi, user_id) to resolve old global UNIQUE(resi) conflicts
      await db.execute('''
        INSERT INTO orders (resi, marketplace, scanned_at, date, photo_path, user_id)
        SELECT resi, marketplace, scanned_at, date, photo_path, user_id
        FROM orders_old
        WHERE id IN (
          SELECT MAX(id) FROM orders_old GROUP BY resi, COALESCE(user_id, '')
        )
      ''');
      await db.execute('DROP TABLE orders_old');
    }
    if (oldVersion < 6) {
      // Rename orders → scans, order_categories → scan_categories
      // Also rename column order_id → scan_id in scan_categories
      await db.execute('ALTER TABLE orders RENAME TO scans');
      await db.execute('ALTER TABLE order_categories RENAME TO scan_categories');
      // SQLite doesn't support ALTER COLUMN, so recreate scan_categories with scan_id
      try { await db.execute('DROP TABLE IF EXISTS scan_categories_old'); } catch (_) {}
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
      await db.execute('CREATE INDEX idx_sc_order ON scan_categories(scan_id)');
      await db.execute('CREATE INDEX idx_sc_category ON scan_categories(category_id)');
      await db.execute('''
        INSERT INTO scan_categories (id, scan_id, category_id, assigned_at)
        SELECT id, order_id, category_id, assigned_at FROM scan_categories_old
      ''');
      await db.execute('DROP TABLE scan_categories_old');
    }
  }

  Future<int> insertOrder(ScannedOrder order, {String? userId}) async {
    final db = await database;
    final map = order.toMap();
    if (userId != null) map['user_id'] = userId;
    return await db.insert(
      'scans',
      map,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<ScannedOrder?> findByResi(String resi, {String? userId}) async {
    final db = await database;
    List<Map<String, Object?>> maps;
    if (userId != null) {
      maps = await db.query(
        'scans',
        where: 'resi = ? AND user_id = ?',
        whereArgs: [resi, userId],
        limit: 1,
      );
    } else {
      maps = await db.query(
        'scans',
        where: 'resi = ? AND user_id IS NULL',
        whereArgs: [resi],
        limit: 1,
      );
    }
    if (maps.isEmpty) return null;
    return ScannedOrder.fromMap(maps.first);
  }

  Future<List<ScannedOrder>> getOrdersByDate(String date, {String? userId}) async {
    final db = await database;
    if (userId != null) {
      final maps = await db.query(
        'scans',
        where: 'date = ? AND user_id = ?',
        whereArgs: [date, userId],
        orderBy: 'scanned_at DESC',
      );
      return maps.map((m) => ScannedOrder.fromMap(m)).toList();
    }
    final maps = await db.query(
      'scans',
      where: 'date = ? AND user_id IS NULL',
      whereArgs: [date],
      orderBy: 'scanned_at DESC',
    );
    return maps.map((m) => ScannedOrder.fromMap(m)).toList();
  }

  Future<int> updateOrderPhoto(int id, String? photoPath) async {
    final db = await database;
    return await db.update(
      'scans',
      {'photo_path': photoPath},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<ScannedOrder>> searchOrders(String query, {String? userId}) async {
    final db = await database;
    if (userId != null) {
      final maps = await db.query(
        'scans',
        where: 'resi LIKE ? AND user_id = ?',
        whereArgs: ['%$query%', userId],
        orderBy: 'scanned_at DESC',
        limit: 100,
      );
      return maps.map((m) => ScannedOrder.fromMap(m)).toList();
    }
    final maps = await db.query(
      'scans',
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
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM scans WHERE user_id = ?', [userId]);
      return Sqflite.firstIntValue(result) ?? 0;
    }
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM scans WHERE user_id IS NULL');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getOrderCountByDate(String date, {String? userId}) async {
    final db = await database;
    if (userId != null) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM scans WHERE date = ? AND user_id = ?',
        [date, userId],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM scans WHERE date = ? AND user_id IS NULL',
      [date],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<String, int>> getDailyStats(int days, {String? userId}) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startStr =
        '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';

    String query = 'SELECT date, COUNT(*) as count FROM scans WHERE date >= ?';
    List<Object?> args = [startStr];
    if (userId != null) {
      query += ' AND user_id = ?';
      args.add(userId);
    } else {
      query += ' AND user_id IS NULL';
    }
    query += ' GROUP BY date ORDER BY date ASC';

    final result = await db.rawQuery(query, args);

    final stats = <String, int>{};
    for (final row in result) {
      stats[row['date'] as String] = row['count'] as int;
    }
    return stats;
  }

  Future<Map<String, int>> getMarketplaceStats({String? date, String? userId}) async {
    final db = await database;
    String query =
        'SELECT marketplace, COUNT(*) as count FROM scans';
    List<Object?> args = [];

    final List<String> conditions = [];
    if (date != null) {
      conditions.add('date = ?');
      args.add(date);
    }
    if (userId != null) {
      conditions.add('user_id = ?');
      args.add(userId);
    } else {
      conditions.add('user_id IS NULL');
    }
    if (conditions.isNotEmpty) {
      query += ' WHERE ${conditions.join(' AND ')}';
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
      maps = await db.query('scans', where: 'user_id = ?', whereArgs: [userId], orderBy: 'scanned_at DESC');
    } else {
      maps = await db.query('scans', where: 'user_id IS NULL', orderBy: 'scanned_at DESC');
    }
    return maps.map((m) => ScannedOrder.fromMap(m)).toList();
  }

  Future<int> deleteOrder(int id) async {
    final db = await database;
    return await db.delete('scans', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> getDistinctDates({String? userId}) async {
    final db = await database;
    if (userId != null) {
      final result = await db.rawQuery(
        'SELECT DISTINCT date FROM scans WHERE user_id = ? ORDER BY date DESC',
        [userId],
      );
      return result.map((r) => r['date'] as String).toList();
    }
    final result = await db.rawQuery(
      'SELECT DISTINCT date FROM scans WHERE user_id IS NULL ORDER BY date DESC',
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
    // Cari order_id yang hanya ada di kategori ini (tidak di kategori lain)
    final onlyInThisCategory = await db.rawQuery('''
      SELECT sc.scan_id FROM scan_categories sc
      WHERE sc.category_id = ?
      AND sc.scan_id NOT IN (
        SELECT sc2.scan_id FROM scan_categories sc2
        WHERE sc2.category_id != ?
      )
    ''', [id, id]);
    // Hapus order-category relations untuk kategori ini
    await db.delete('scan_categories', where: 'category_id = ?', whereArgs: [id]);
    // Hapus orders yang hanya ada di kategori ini
    for (final row in onlyInThisCategory) {
      final orderId = row['scan_id'] as int;
      await db.delete('scans', where: 'id = ?', whereArgs: [orderId]);
    }
    // Hapus kategori
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // ── Order-Category Relations ──

  Future<int> assignCategoryToOrder(int orderId, int categoryId) async {
    final db = await database;
    return await db.insert(
      'scan_categories',
      {'scan_id': orderId, 'category_id': categoryId, 'assigned_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<ScanCategory>> getCategoriesForOrder(int orderId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT c.* FROM categories c
      INNER JOIN scan_categories sc ON c.id = sc.category_id
      WHERE sc.scan_id = ?
      ORDER BY c.name ASC
    ''', [orderId]);
    return result.map((m) => ScanCategory.fromMap(m)).toList();
  }

  Future<List<ScannedOrder>> getOrdersByCategory(int categoryId, {String? userId}) async {
    final db = await database;
    String userFilter = userId != null ? 'AND o.user_id = ?' : 'AND o.user_id IS NULL';
    List<Object?> args = userId != null ? [categoryId, userId] : [categoryId];
    final result = await db.rawQuery('''
      SELECT o.* FROM scans o
      INNER JOIN scan_categories sc ON o.id = sc.scan_id
      WHERE sc.category_id = ? $userFilter
      ORDER BY o.scanned_at DESC
    ''', args);
    return result.map((m) => ScannedOrder.fromMap(m)).toList();
  }

  Future<Map<String, int>> getCategoryStats({String? userId}) async {
    final db = await database;
    String userFilter = userId != null ? 'AND o.user_id = ?' : 'AND o.user_id IS NULL';
    List<Object?> args = userId != null ? [userId, userId] : [];
    final result = await db.rawQuery('''
      SELECT c.name, COUNT(sc.scan_id) as count
      FROM categories c
      LEFT JOIN scan_categories sc ON c.id = sc.category_id
      LEFT JOIN scans o ON sc.scan_id = o.id
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
    await db.delete('scan_categories', where: 'scan_id = ? AND category_id = ?', whereArgs: [orderId, categoryId]);
  }

  /// Cek apakah resi sudah ada dalam kategori tertentu (untuk duplicate check per-kategori)
  Future<bool> isOrderInCategory(String resi, int categoryId, {String? userId}) async {
    final db = await database;
    String userFilter = userId != null ? 'AND o.user_id = ?' : 'AND o.user_id IS NULL';
    List<Object?> args = userId != null ? [resi, categoryId, userId] : [resi, categoryId];
    final result = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM scans o
      INNER JOIN scan_categories sc ON o.id = sc.scan_id
      WHERE o.resi = ? AND sc.category_id = ? $userFilter
    ''', args);
    return (Sqflite.firstIntValue(result) ?? 0) > 0;
  }

  /// Hitung jumlah order per kategori (return map: categoryId -> count)
  Future<Map<int, int>> getCategoryCounts({String? userId}) async {
    final db = await database;
    String userFilter = userId != null ? 'AND o.user_id = ?' : 'AND o.user_id IS NULL';
    List<Object?> args = userId != null ? [userId, userId] : [];
    final result = await db.rawQuery('''
      SELECT c.id as cat_id, COUNT(sc.scan_id) as cnt
      FROM categories c
      LEFT JOIN scan_categories sc ON c.id = sc.category_id
      LEFT JOIN scans o ON sc.scan_id = o.id
      WHERE c.user_id ${userId != null ? '= ?' : 'IS NULL'} $userFilter
      GROUP BY c.id
    ''', args);
    final counts = <int, int>{};
    for (final row in result) {
      counts[row['cat_id'] as int] = (row['cnt'] as int?) ?? 0;
    }
    return counts;
  }
}
