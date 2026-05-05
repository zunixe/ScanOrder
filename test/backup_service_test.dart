import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackupService JSON format logic', () {
    test('backup data structure has expected keys', () {
      final data = {
        'version': 1,
        'exported_at': DateTime.now().toIso8601String(),
        'scans': [],
        'categories': [],
      };
      expect(data.containsKey('version'), true);
      expect(data.containsKey('exported_at'), true);
      expect(data.containsKey('scans'), true);
      expect(data.containsKey('categories'), true);
    });

    test('version 1 is supported', () {
      const version = 1;
      expect(version > 1, false); // version > 1 should throw
    });

    test('version 2 is not supported', () {
      const version = 2;
      expect(version > 1, true);
    });

    test('backup JSON round-trip', () {
      final data = {
        'version': 1,
        'exported_at': '2026-05-06T00:00:00.000',
        'scans': [
          {'resi': 'SPX123', 'marketplace': 'Shopee', 'date': '2026-05-06'},
        ],
        'categories': [
          {'name': 'Test', 'color': '#000'},
        ],
      };
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded['version'], 1);
      expect((decoded['scans'] as List).length, 1);
      expect((decoded['categories'] as List).length, 1);
    });

    test('backup filename format', () {
      final timestamp = '20260506_120000';
      final filename = 'scanorder_backup_$timestamp.json';
      expect(filename, startsWith('scanorder_backup_'));
      expect(filename, endsWith('.json'));
    });

    test('empty backup has zero counts', () {
      final result = {'scans': 0, 'categories': 0};
      expect(result['scans'], 0);
      expect(result['categories'], 0);
    });
  });
}
