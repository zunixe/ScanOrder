import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Storage formatting helpers', () {
    String formatStorageUsed(int usedBytes) {
      if (usedBytes >= 1024 * 1024 * 1024) {
        return '${(usedBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
      } else if (usedBytes >= 1024 * 1024) {
        return '${(usedBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
      } else if (usedBytes >= 1024) {
        return '${(usedBytes / 1024).toStringAsFixed(0)} KB';
      }
      return '$usedBytes B';
    }

    String formatStorageTotal(int totalBytes) {
      if (totalBytes < 0) return '∞';
      if (totalBytes >= 1024 * 1024 * 1024) {
        return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
      } else if (totalBytes >= 1024 * 1024) {
        return '${(totalBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
      }
      return '${(totalBytes / 1024).toStringAsFixed(0)} KB';
    }

    double calculateStorageFraction(int usedBytes, int totalBytes) {
      if (totalBytes <= 0) return 0;
      return (usedBytes / totalBytes).clamp(0.0, 1.0);
    }

    group('storageUsed', () {
      test('formats bytes', () {
        expect(formatStorageUsed(500), '500 B');
      });

      test('formats kilobytes', () {
        expect(formatStorageUsed(2048), '2 KB');
      });

      test('formats megabytes', () {
        expect(formatStorageUsed(5 * 1024 * 1024), '5 MB');
      });

      test('formats gigabytes', () {
        expect(formatStorageUsed(2 * 1024 * 1024 * 1024 + 500 * 1024 * 1024), '2.5 GB');
      });
    });

    group('storageTotal', () {
      test('formats infinity for negative', () {
        expect(formatStorageTotal(-1), '∞');
      });

      test('formats megabytes', () {
        expect(formatStorageTotal(100 * 1024 * 1024), '100 MB');
      });

      test('formats gigabytes', () {
        expect(formatStorageTotal(2 * 1024 * 1024 * 1024), '2 GB');
      });

      test('formats kilobytes', () {
        expect(formatStorageTotal(512 * 1024), '512 KB');
      });
    });

    group('storageFraction', () {
      test('returns 0 when totalBytes is 0', () {
        expect(calculateStorageFraction(50, 0), 0);
      });

      test('returns correct fraction', () {
        expect(calculateStorageFraction(25, 100), 0.25);
      });

      test('clamps to 1.0 when used exceeds total', () {
        expect(calculateStorageFraction(150, 100), 1.0);
      });

      test('clamps to 0.0 when used is negative', () {
        expect(calculateStorageFraction(-10, 100), 0.0);
      });
    });
  });
}
