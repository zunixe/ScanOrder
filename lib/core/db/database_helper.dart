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
      version: 7,
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
        user_id TEXT,
        team_id TEXT
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
    if (oldVersion < 7) {
      // Add team_id column to scans for team data filtering
      await db.execute('ALTER TABLE scans ADD COLUMN team_id TEXT');
      await db.execute('CREATE INDEX idx_team_id ON scans(team_id)');
    }
  }

  Future<int> insertOrder(ScannedOrder order, {String? userId, String? teamId}) async {
    final db = await database;
    final map = order.toMap();
    if (userId != null) map['user_id'] = userId;
    if (teamId != null) map['team_id'] = teamId;
    return await db.insert(
      'scans',
      map,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<ScannedOrder?> getOrderById(int id) async {
    final db = await database;
    final maps = await db.query('scans', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return ScannedOrder.fromMap(maps.first);
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

  Future<List<ScannedOrder>> getOrdersByDate(String date, {String? userId, String? teamId}) async {
    final db = await database;
    if (teamId != null) {
      final maps = await db.query('scans', where: 'date = ? AND team_id = ?', whereArgs: [date, teamId], orderBy: 'scanned_at DESC');
      return maps.map((m) => ScannedOrder.fromMap(m)).toList();
    }
    if (userId != null) {
      final maps = await db.query('scans', where: 'date = ? AND user_id = ?', whereArgs: [date, userId], orderBy: 'scanned_at DESC');
      return maps.map((m) => ScannedOrder.fromMap(m)).toList();
    }
    final maps = await db.query('scans', where: 'date = ? AND user_id IS NULL', whereArgs: [date], orderBy: 'scanned_at DESC');
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

  Future<List<ScannedOrder>> searchOrders(String query, {String? userId, String? teamId}) async {
    final db = await database;
    if (teamId != null) {
      final maps = await db.query('scans', where: 'resi LIKE ? AND team_id = ?', whereArgs: ['%$query%', teamId], orderBy: 'scanned_at DESC', limit: 100);
      return maps.map((m) => ScannedOrder.fromMap(m)).toList();
    }
    if (userId != null) {
      final maps = await db.query('scans', where: 'resi LIKE ? AND user_id = ?', whereArgs: ['%$query%', userId], orderBy: 'scanned_at DESC', limit: 100);
      return maps.map((m) => ScannedOrder.fromMap(m)).toList();
    }
    final maps = await db.query('scans', where: 'resi LIKE ? AND user_id IS NULL', whereArgs: ['%$query%'], orderBy: 'scanned_at DESC', limit: 100);
    return maps.map((m) => ScannedOrder.fromMap(m)).toList();
  }

  Future<int> getTotalOrderCount({String? userId, String? teamId}) async {
    final db = await database;
    if (teamId != null) {
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM scans WHERE team_id = ?', [teamId]);
      return Sqflite.firstIntValue(result) ?? 0;
    }
    if (userId != null) {
      // Personal mode: only count scans without team_id
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM scans WHERE user_id = ? AND team_id IS NULL', [userId]);
      return Sqflite.firstIntValue(result) ?? 0;
    }
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM scans WHERE user_id IS NULL AND team_id IS NULL');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getOrderCountByDate(String date, {String? userId, String? teamId}) async {
    final db = await database;
    if (teamId != null) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM scans WHERE date = ? AND team_id = ?',
        [date, teamId],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    }
    if (userId != null) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM scans WHERE date = ? AND user_id = ? AND team_id IS NULL',
        [date, userId],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM scans WHERE date = ? AND user_id IS NULL AND team_id IS NULL',
      [date],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<String, int>> getDailyStats(int days, {String? userId, String? teamId}) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startStr =
        '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';

    String query = 'SELECT date, COUNT(*) as count FROM scans WHERE date >= ?';
    List<Object?> args = [startStr];
    if (teamId != null) {
      query += ' AND team_id = ?';
      args.add(teamId);
    } else if (userId != null) {
      query += ' AND user_id = ? AND team_id IS NULL';
      args.add(userId);
    } else {
      query += ' AND user_id IS NULL AND team_id IS NULL';
    }
    query += ' GROUP BY date ORDER BY date ASC';

    final result = await db.rawQuery(query, args);

    final stats = <String, int>{};
    for (final row in result) {
      stats[row['date'] as String] = row['count'] as int;
    }
    return stats;
  }

  Future<Map<String, int>> getMarketplaceStats({String? date, String? userId, String? teamId}) async {
    final db = await database;
    String query =
        'SELECT marketplace, COUNT(*) as count FROM scans';
    List<Object?> args = [];

    final List<String> conditions = [];
    if (date != null) {
      conditions.add('date = ?');
      args.add(date);
    }
    if (teamId != null) {
      conditions.add('team_id = ?');
      args.add(teamId);
    } else if (userId != null) {
      conditions.add('user_id = ?');
      args.add(userId);
      conditions.add('team_id IS NULL');
    } else {
      conditions.add('user_id IS NULL');
      conditions.add('team_id IS NULL');
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
      maps = await db.query('scans', where: 'user_id = ? AND team_id IS NULL', whereArgs: [userId], orderBy: 'scanned_at DESC');
    } else {
      maps = await db.query('scans', where: 'user_id IS NULL AND team_id IS NULL', orderBy: 'scanned_at DESC');
    }
    return maps.map((m) => ScannedOrder.fromMap(m)).toList();
  }

  Future<int> deleteOrder(int id) async {
    final db = await database;
    return await db.delete('scans', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> getDistinctDates({String? userId, String? teamId}) async {
    final db = await database;
    if (teamId != null) {
      final result = await db.rawQuery('SELECT DISTINCT date FROM scans WHERE team_id = ? ORDER BY date DESC', [teamId]);
      return result.map((r) => r['date'] as String).toList();
    }
    if (userId != null) {
      final result = await db.rawQuery('SELECT DISTINCT date FROM scans WHERE user_id = ? ORDER BY date DESC', [userId]);
      return result.map((r) => r['date'] as String).toList();
    }
    final result = await db.rawQuery('SELECT DISTINCT date FROM scans WHERE user_id IS NULL ORDER BY date DESC');
    return result.map((r) => r['date'] as String).toList();
  }

  // ── Category CRUD ──

  Future<int> insertCategory(ScanCategory category) async {
    final db = await database;
    // Check if category with same name+user_id already exists (prevent duplicates from sync)
    final existing = await db.query(
      'categories',
      where: 'name = ? AND (user_id = ? OR (? IS NULL AND user_id IS NULL))',
      whereArgs: [category.name, category.userId, category.userId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      // Already exists, return existing id
      return existing.first['id'] as int;
    }
    return await db.insert('categories', category.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<ScanCategory?> getCategoryById(int id) async {
    final db = await database;
    final maps = await db.query('categories', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return ScanCategory.fromMap(maps.first);
  }

  Future<List<ScanCategory>> getAllCategories({String? userId, String? adminUserId}) async {
    final db = await database;
    List<Map<String, Object?>> maps;
    if (userId != null && adminUserId != null) {
      // Team member: load own + admin's categories
      maps = await db.query('categories', where: 'user_id = ? OR user_id = ?', whereArgs: [userId, adminUserId], orderBy: 'created_at ASC');
    } else if (userId != null) {
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

  Future<List<ScannedOrder>> getOrdersByCategory(int categoryId, {String? userId, String? teamId}) async {
    final db = await database;
    String filter = teamId != null ? 'AND o.team_id = ?' : (userId != null ? 'AND o.user_id = ?' : 'AND o.user_id IS NULL');
    List<Object?> args = teamId != null ? [categoryId, teamId] : (userId != null ? [categoryId, userId] : [categoryId]);
    final result = await db.rawQuery('''
      SELECT o.* FROM scans o
      INNER JOIN scan_categories sc ON o.id = sc.scan_id
      WHERE sc.category_id = ? $filter
      ORDER BY o.scanned_at DESC
    ''', args);
    return result.map((m) => ScannedOrder.fromMap(m)).toList();
  }

  Future<Map<String, int>> getCategoryStats({String? userId, String? teamId}) async {
    final db = await database;
    List<Object?> args;
    String catFilter;
    String scanFilter;
    if (teamId != null) {
      catFilter = 'c.user_id IS NOT NULL';
      scanFilter = 'AND o.team_id = ?';
      args = [teamId];
    } else if (userId != null) {
      catFilter = 'c.user_id = ?';
      scanFilter = 'AND o.user_id = ? AND o.team_id IS NULL';
      args = [userId, userId];
    } else {
      catFilter = 'c.user_id IS NULL';
      scanFilter = 'AND o.user_id IS NULL AND o.team_id IS NULL';
      args = [];
    }
    final result = await db.rawQuery('''
      SELECT c.name, COUNT(sc.scan_id) as count
      FROM categories c
      LEFT JOIN scan_categories sc ON c.id = sc.category_id
      LEFT JOIN scans o ON sc.scan_id = o.id
      WHERE $catFilter $scanFilter
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

  /// Get all scan_categories with resi for repair sync to Supabase
  Future<List<Map<String, dynamic>>> getAllScanCategoriesWithResi() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT sc.scan_id, sc.category_id, o.resi, c.name as cat_name, c.user_id as cat_user_id
      FROM scan_categories sc
      INNER JOIN scans o ON sc.scan_id = o.id
      INNER JOIN categories c ON sc.category_id = c.id
    ''');
  }

  /// Delete orders that were synced from a team (not personal orders)
  /// Team orders have team_id set — all belong to admin
  Future<void> deleteTeamOrders(String userId) async {
    final db = await database;
    // Delete scan_categories for all team orders first (foreign key)
    await db.delete('scan_categories', where: 'scan_id IN (SELECT id FROM scans WHERE team_id IS NOT NULL)');
    // Delete all team scans (they belong to admin, not personal)
    await db.delete('scans', where: 'team_id IS NOT NULL');
  }

  /// Get all team orders (for photo cleanup on leave)
  Future<List<ScannedOrder>> getTeamOrders() async {
    final db = await database;
    final maps = await db.query('scans', where: 'team_id IS NOT NULL');
    return maps.map((m) => ScannedOrder.fromMap(m)).toList();
  }

  /// Delete categories that belong to team admin (not personal categories)
  Future<void> deleteTeamCategories(String userId) async {
    final db = await database;
    // Delete scan_categories references first
    await db.delete('scan_categories', where: 'category_id IN (SELECT id FROM categories WHERE user_id != ?)', whereArgs: [userId]);
    // Delete categories from other users (team admin)
    await db.delete('categories', where: 'user_id != ?', whereArgs: [userId]);
  }

  /// Delete all scans and scan_categories (debug)
  Future<void> deleteAllScans() async {
    final db = await database;
    await db.delete('scan_categories');
    await db.delete('scans');
  }

  /// Update team_id for existing orders that don't have one yet (backfill on team join)
  Future<void> updateTeamIdForUser(String userId, String teamId) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE scans SET team_id = ? WHERE user_id = ? AND team_id IS NULL',
      [teamId, userId],
    );
  }
}
