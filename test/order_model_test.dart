import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/models/scan_record.dart';

void main() {
  group('ScanRecord', () {
    test('fromMap creates correct order', () {
      final map = {
        'id': 1,
        'resi': 'SPX123456789',
        'marketplace': 'Shopee',
        'photo_path': '/path/to/photo.jpg',
        'scanned_at': DateTime(2025, 1, 15, 10, 30).millisecondsSinceEpoch,
        'date': '2025-01-15',
      };
      final order = ScanRecord.fromMap(map);
      expect(order.id, 1);
      expect(order.resi, 'SPX123456789');
      expect(order.marketplace, 'Shopee');
      expect(order.photoPath, '/path/to/photo.jpg');
      expect(order.date, '2025-01-15');
    });

    test('toMap roundtrip', () {
      final order = ScanRecord(
        id: 1,
        resi: 'CM40443408053',
        marketplace: 'JNE',
        photoPath: null,
        scannedAt: DateTime(2025, 1, 15, 10, 30),
        date: '2025-01-15',
      );
      final map = order.toMap();
      expect(map['resi'], 'CM40443408053');
      expect(map['marketplace'], 'JNE');
      expect(map['photo_path'], isNull);
      expect(map['date'], '2025-01-15');
    });

    test('fromMap with null optional fields', () {
      final map = {
        'id': 2,
        'resi': 'JP1234567890',
        'marketplace': 'J&T',
        'photo_path': null,
        'scanned_at': DateTime(2025, 1, 15, 10, 30).millisecondsSinceEpoch,
        'date': '2025-01-15',
      };
      final order = ScanRecord.fromMap(map);
      expect(order.photoPath, isNull);
      expect(order.resi, 'JP1234567890');
    });
  });
}
