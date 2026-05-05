import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/models/category.dart';

void main() {
  group('ScanCategory', () {
    test('creates with required fields', () {
      final cat = ScanCategory(name: 'Keranjang', color: '#2196F3');
      expect(cat.name, 'Keranjang');
      expect(cat.color, '#2196F3');
      expect(cat.id, isNull);
      expect(cat.userId, isNull);
      expect(cat.createdAt, isNotNull);
    });

    test('creates with all fields', () {
      final now = DateTime(2026, 5, 1);
      final cat = ScanCategory(
        id: 1,
        name: 'Paket Besar',
        color: '#FF5722',
        userId: 'user-1',
        createdAt: now,
      );
      expect(cat.id, 1);
      expect(cat.name, 'Paket Besar');
      expect(cat.color, '#FF5722');
      expect(cat.userId, 'user-1');
      expect(cat.createdAt, now);
    });

    test('copyWith updates specified fields', () {
      final cat = ScanCategory(name: 'Old', color: '#000000');
      final updated = cat.copyWith(name: 'New', color: '#FFFFFF');
      expect(updated.name, 'New');
      expect(updated.color, '#FFFFFF');
      expect(updated.createdAt, cat.createdAt);
    });

    test('copyWith preserves unspecified fields', () {
      final cat = ScanCategory(id: 5, name: 'Cat', color: '#111', userId: 'u1');
      final updated = cat.copyWith(name: 'Updated');
      expect(updated.id, 5);
      expect(updated.color, '#111');
      expect(updated.userId, 'u1');
    });

    test('equality based on id', () {
      final cat1 = ScanCategory(id: 1, name: 'A', color: '#000');
      final cat2 = ScanCategory(id: 1, name: 'B', color: '#111');
      expect(cat1, cat2);
    });

    test('inequality for different ids', () {
      final cat1 = ScanCategory(id: 1, name: 'A', color: '#000');
      final cat2 = ScanCategory(id: 2, name: 'A', color: '#000');
      expect(cat1, isNot(equals(cat2)));
    });

    test('hashCode based on id', () {
      final cat1 = ScanCategory(id: 1, name: 'A', color: '#000');
      final cat2 = ScanCategory(id: 1, name: 'B', color: '#111');
      expect(cat1.hashCode, cat2.hashCode);
    });

    test('toMap and fromMap round-trip', () {
      final now = DateTime(2026, 5, 1);
      final cat = ScanCategory(
        id: 1,
        name: 'Test',
        color: '#2196F3',
        userId: 'user-1',
        createdAt: now,
      );
      final map = cat.toMap();
      final restored = ScanCategory.fromMap(map);
      expect(restored.id, cat.id);
      expect(restored.name, cat.name);
      expect(restored.color, cat.color);
      expect(restored.userId, cat.userId);
    });

    test('fromSupabase works same as fromMap', () {
      final cat = ScanCategory(name: 'Test', color: '#000');
      final map = cat.toMap();
      final restored = ScanCategory.fromSupabase(map);
      expect(restored.name, 'Test');
    });
  });
}
