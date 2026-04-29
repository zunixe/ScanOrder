import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/order.dart';

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
      version: 2,
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
        photo_path TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_date ON orders(date)');
    await db.execute('CREATE INDEX idx_marketplace ON orders(marketplace)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE orders ADD COLUMN photo_path TEXT');
    }
  }

  Future<int> insertOrder(ScannedOrder order) async {
    final db = await database;
    return await db.insert(
      'orders',
      order.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
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

  Future<List<ScannedOrder>> getOrdersByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'orders',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'scanned_at DESC',
    );
    return maps.map((m) => ScannedOrder.fromMap(m)).toList();
  }

  Future<List<ScannedOrder>> searchOrders(String query) async {
    final db = await database;
    final maps = await db.query(
      'orders',
      where: 'resi LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'scanned_at DESC',
      limit: 100,
    );
    return maps.map((m) => ScannedOrder.fromMap(m)).toList();
  }

  Future<int> getTotalOrderCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM orders');
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

  Future<List<ScannedOrder>> getAllOrders() async {
    final db = await database;
    final maps = await db.query('orders', orderBy: 'scanned_at DESC');
    return maps.map((m) => ScannedOrder.fromMap(m)).toList();
  }

  Future<int> deleteOrder(int id) async {
    final db = await database;
    return await db.delete('orders', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> getDistinctDates() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT date FROM orders ORDER BY date DESC',
    );
    return result.map((r) => r['date'] as String).toList();
  }
}
