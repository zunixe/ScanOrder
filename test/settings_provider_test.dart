import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scanorder/features/settings/settings_provider.dart';

void main() {
  late SettingsProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = SettingsProvider();
  });

  group('SettingsProvider', () {
    test('default values', () {
      expect(provider.soundEnabled, true);
      expect(provider.vibrationEnabled, true);
      expect(provider.wakelockEnabled, true);
      expect(provider.darkMode, 'system');
      expect(provider.compressPhoto, true);
      expect(provider.locale, isNull);
    });

    test('loadSettings reads from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'settings_sound': false,
        'settings_vibration': false,
        'settings_wakelock': false,
        'settings_dark_mode': 'dark',
        'settings_compress_photo': false,
        'settings_locale': 'en',
      });
      await provider.loadSettings();
      expect(provider.soundEnabled, false);
      expect(provider.vibrationEnabled, false);
      expect(provider.wakelockEnabled, false);
      expect(provider.darkMode, 'dark');
      expect(provider.compressPhoto, false);
      expect(provider.locale, 'en');
    });

    test('setSoundEnabled updates value and notifies', () async {
      var notified = false;
      provider.addListener(() => notified = true);
      await provider.setSoundEnabled(false);
      expect(provider.soundEnabled, false);
      expect(notified, true);
    });

    test('setVibrationEnabled updates value and notifies', () async {
      var notified = false;
      provider.addListener(() => notified = true);
      await provider.setVibrationEnabled(false);
      expect(provider.vibrationEnabled, false);
      expect(notified, true);
    });

    test('setWakelockEnabled updates value and notifies', () async {
      var notified = false;
      provider.addListener(() => notified = true);
      await provider.setWakelockEnabled(false);
      expect(provider.wakelockEnabled, false);
      expect(notified, true);
    });

    test('setDarkMode updates value and notifies', () async {
      var notified = false;
      provider.addListener(() => notified = true);
      await provider.setDarkMode('light');
      expect(provider.darkMode, 'light');
      expect(notified, true);
    });

    test('setCompressPhoto updates value and notifies', () async {
      var notified = false;
      provider.addListener(() => notified = true);
      await provider.setCompressPhoto(false);
      expect(provider.compressPhoto, false);
      expect(notified, true);
    });

    test('setLocale updates value and notifies', () async {
      var notified = false;
      provider.addListener(() => notified = true);
      await provider.setLocale('id');
      expect(provider.locale, 'id');
      expect(notified, true);
    });

    test('setLocale to null removes locale', () async {
      await provider.setLocale('en');
      expect(provider.locale, 'en');
      await provider.setLocale(null);
      expect(provider.locale, isNull);
    });

    test('settings persist after reload', () async {
      await provider.setSoundEnabled(false);
      await provider.setDarkMode('dark');
      await provider.setLocale('id');

      final newProvider = SettingsProvider();
      await newProvider.loadSettings();
      expect(newProvider.soundEnabled, false);
      expect(newProvider.darkMode, 'dark');
      expect(newProvider.locale, 'id');
    });
  });
}
