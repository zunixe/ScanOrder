import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/models/scan_record.dart';
import 'package:scanorder/models/category.dart';

void main() {
  group('ScanRecord', () {
    final now = DateTime(2026, 1, 15, 10, 30);
    final record = ScanRecord(
      id: 1,
      resi: 'SPX123456789',
      marketplace: 'Shopee',
      scannedAt: now,
      date: '2026-01-15',
      photoPath: '/photos/scan.jpg',
      categories: const [],
      syncStatus: 'pending',
    );

    test('toMap round-trip', () {
      final map = record.toMap();
      expect(map['id'], 1);
      expect(map['resi'], 'SPX123456789');
      expect(map['marketplace'], 'Shopee');
      expect(map['scanned_at'], now.millisecondsSinceEpoch);
      expect(map['date'], '2026-01-15');
      expect(map['photo_path'], '/photos/scan.jpg');
      expect(map['sync_status'], 'pending');
    });

    test('fromMap reconstructs correctly', () {
      final map = record.toMap();
      final reconstructed = ScanRecord.fromMap(map);
      expect(reconstructed.id, record.id);
      expect(reconstructed.resi, record.resi);
      expect(reconstructed.marketplace, record.marketplace);
      expect(reconstructed.scannedAt, record.scannedAt);
      expect(reconstructed.date, record.date);
      expect(reconstructed.photoPath, record.photoPath);
      expect(reconstructed.syncStatus, record.syncStatus);
    });

    test('fromMap defaults syncStatus to synced when null', () {
      final map = {
        'id': 2,
        'resi': 'JP123',
        'marketplace': 'J&T',
        'scanned_at': now.millisecondsSinceEpoch,
        'date': '2026-01-15',
        'photo_path': null,
      };
      final r = ScanRecord.fromMap(map);
      expect(r.syncStatus, 'synced');
    });

    test('fromSupabase parses nested categories', () {
      final supabaseMap = {
        'id': 10,
        'resi': 'SPX999',
        'marketplace': 'Shopee',
        'scanned_at': now.millisecondsSinceEpoch,
        'date': '2026-01-15',
        'photo_url': 'https://cdn.example.com/photo.jpg',
        'scan_categories': [
          {
            'categories': {'name': 'Pakaian', 'color': '#FF5722', 'user_id': 'u1'},
          },
          {
            'categories': {'name': 'Elektronik', 'color': '#2196F3', 'user_id': 'u1'},
          },
        ],
      };
      final r = ScanRecord.fromSupabase(supabaseMap);
      expect(r.resi, 'SPX999');
      expect(r.photoPath, 'https://cdn.example.com/photo.jpg');
      expect(r.syncStatus, 'synced');
      expect(r.categories.length, 2);
      expect(r.categories[0].name, 'Pakaian');
      expect(r.categories[1].color, '#2196F3');
    });

    test('fromSupabase handles null scan_categories', () {
      final supabaseMap = {
        'id': 11,
        'resi': 'JP111',
        'marketplace': 'J&T',
        'scanned_at': now.millisecondsSinceEpoch,
        'date': '2026-01-15',
        'photo_url': null,
      };
      final r = ScanRecord.fromSupabase(supabaseMap);
      expect(r.categories, isEmpty);
      expect(r.photoPath, isNull);
    });

    test('copyWith works correctly', () {
      final copy = record.copyWith(
        photoPath: '/new/photo.jpg',
        syncStatus: 'synced',
      );
      expect(copy.photoPath, '/new/photo.jpg');
      expect(copy.syncStatus, 'synced');
      expect(copy.resi, record.resi); // unchanged
      expect(copy.id, record.id); // unchanged
    });

    test('copyWith preserves original when no args', () {
      final copy = record.copyWith();
      expect(copy.resi, record.resi);
      expect(copy.photoPath, record.photoPath);
    });

    test('default syncStatus is pending', () {
      final r = ScanRecord(
        resi: 'TEST',
        marketplace: 'Lainnya',
        scannedAt: now,
        date: '2026-01-15',
      );
      expect(r.syncStatus, 'pending');
    });
  });

  group('ScanCategory', () {
    test('toMap round-trip', () {
      final now = DateTime(2026, 3, 1);
      final cat = ScanCategory(id: 5, name: 'Pakaian', color: '#FF5722', userId: 'u1', createdAt: now);
      final map = cat.toMap();
      expect(map['id'], 5);
      expect(map['name'], 'Pakaian');
      expect(map['color'], '#FF5722');
      expect(map['user_id'], 'u1');
      expect(map['created_at'], now.millisecondsSinceEpoch);
    });

    test('fromMap reconstructs correctly', () {
      final now = DateTime(2026, 3, 1);
      final map = {'id': 5, 'name': 'Pakaian', 'color': '#FF5722', 'user_id': 'u1', 'created_at': now.millisecondsSinceEpoch};
      final cat = ScanCategory.fromMap(map);
      expect(cat.id, 5);
      expect(cat.name, 'Pakaian');
      expect(cat.color, '#FF5722');
      expect(cat.userId, 'u1');
    });

    test('fromMap defaults createdAt when null', () {
      final map = {'id': 1, 'name': 'Test', 'color': '#000', 'user_id': null, 'created_at': null};
      final cat = ScanCategory.fromMap(map);
      expect(cat.createdAt, isNotNull);
    });

    test('copyWith works', () {
      final cat = ScanCategory(id: 1, name: 'Old', color: '#000');
      final copy = cat.copyWith(name: 'New', color: '#FFF');
      expect(copy.name, 'New');
      expect(copy.color, '#FFF');
      expect(copy.id, 1);
    });

    test('equality by id', () {
      final a = ScanCategory(id: 1, name: 'A', color: '#000');
      final b = ScanCategory(id: 1, name: 'B', color: '#FFF');
      final c = ScanCategory(id: 2, name: 'A', color: '#000');
      expect(a == b, isTrue); // same id
      expect(a == c, isFalse); // different id
    });

    test('default createdAt is now', () {
      final before = DateTime.now();
      final cat = ScanCategory(name: 'Test', color: '#000');
      final after = DateTime.now();
      expect(cat.createdAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(cat.createdAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });
  });
}
