import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Storage display helpers', () {
    test('storageUsed formats bytes correctly', () {
      String formatStorageUsed(int bytes) {
        if (bytes >= 1024 * 1024 * 1024) {
          return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
        } else if (bytes >= 1024 * 1024) {
          return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
        } else if (bytes >= 1024) {
          return '${(bytes / 1024).toStringAsFixed(0)} KB';
        }
        return '$bytes B';
      }

      expect(formatStorageUsed(500), '500 B');
      expect(formatStorageUsed(2048), '2 KB');
      expect(formatStorageUsed(5 * 1024 * 1024), '5 MB');
      expect(formatStorageUsed(2 * 1024 * 1024 * 1024), '2.0 GB');
    });

    test('storageTotal formats bytes correctly', () {
      String formatStorageTotal(int bytes) {
        if (bytes < 0) return '∞';
        if (bytes >= 1024 * 1024 * 1024) {
          return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
        } else if (bytes >= 1024 * 1024) {
          return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
        }
        return '${(bytes / 1024).toStringAsFixed(0)} KB';
      }

      expect(formatStorageTotal(500), '0 KB');
      expect(formatStorageTotal(100 * 1024 * 1024), '100 MB');
      expect(formatStorageTotal(2 * 1024 * 1024 * 1024), '2 GB');
      expect(formatStorageTotal(-1), '∞');
    });

    test('storageFraction returns correct ratio', () {
      double calculateFraction(int used, int total) {
        if (total <= 0) return 0;
        return (used / total).clamp(0.0, 1.0);
      }

      expect(calculateFraction(50, 100), 0.5);
      expect(calculateFraction(200, 100), 1.0);
      expect(calculateFraction(-10, 100), 0.0);
      expect(calculateFraction(50, 0), 0.0);
    });
  });
}
