import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/features/scan/scan_provider.dart';
import 'package:scanorder/features/history/history_provider.dart';
import 'package:scanorder/features/settings/settings_provider.dart';

void main() {
  group('SettingsProvider', () {
    test('default darkMode is system', () {
      final provider = SettingsProvider();
      expect(provider.darkMode, 'system');
    });
  });

  group('ScanProvider', () {
    test('initial state has correct defaults', () {
      final provider = ScanProvider();
      expect(provider.lastResult, isNull);
      expect(provider.savePhoto, isTrue);
    });

    test('quotaDisplay formats correctly', () {
      final provider = ScanProvider();
      expect(provider.quotaDisplay, '0/0');
    });
  });

  group('HistoryProvider', () {
    test('allDatesSentinel is a valid string', () {
      expect(HistoryProvider.allDatesSentinel, isNotEmpty);
    });
  });
}
