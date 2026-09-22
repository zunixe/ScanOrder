import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:scanorder/core/db/database_helper.dart';

/// Shared test utilities for DB/SharedPreferences-backed unit tests.
///
/// Usage:
/// ```dart
/// setUpAll(setupTestDatabase);
/// tearDownAll(teardownTestDatabase);
/// setUp(clearTestData);
/// ```
void setupTestDatabase() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactoryOrNull = databaseFactoryFfi;
  DatabaseHelper.setTestMode(true);
  // Unique DB file per test file → parallel files don't share/lock one DB.
  DatabaseHelper.testDatabasePath =
      '${inMemoryDatabasePath}_${DateTime.now().microsecondsSinceEpoch}';
}

/// Close the cached DB and clear the per-file path override.
Future<void> teardownTestDatabase() async {
  await DatabaseHelper.resetForTests();
}

/// Reset in-memory shared preferences and clear local DB tables.
///
/// Retries briefly on `database is locked` because sqflite_common_ffi can hold
/// the shared connection while background work from a prior test settles.
Future<void> clearTestData() async {
  SharedPreferences.setMockInitialValues({});
  final db = DatabaseHelper.instance;
  final database = await db.database;
  for (final table in [
    'scan_categories',
    'categories',
    'scans',
    'sync_queue',
  ]) {
    await _deleteWithRetry(database, table);
  }
}

Future<void> _deleteWithRetry(Database database, String table) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    try {
      await database.delete(table);
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

/// Fresh `SharedPreferences` mock with the given values.
void mockPrefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
}
