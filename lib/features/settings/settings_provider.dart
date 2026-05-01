import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static const String _soundKey = 'settings_sound';
  static const String _vibrationKey = 'settings_vibration';
  static const String _wakelockKey = 'settings_wakelock';
  static const String _darkModeKey = 'settings_dark_mode'; // 'system', 'light', 'dark'

  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _wakelockEnabled = true;
  String _darkMode = 'system';

  bool get soundEnabled => _soundEnabled;
  bool get vibrationEnabled => _vibrationEnabled;
  bool get wakelockEnabled => _wakelockEnabled;
  String get darkMode => _darkMode;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _soundEnabled = prefs.getBool(_soundKey) ?? true;
    _vibrationEnabled = prefs.getBool(_vibrationKey) ?? true;
    _wakelockEnabled = prefs.getBool(_wakelockKey) ?? true;
    _darkMode = prefs.getString(_darkModeKey) ?? 'system';
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool value) async {
    _soundEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundKey, value);
    notifyListeners();
  }

  Future<void> setVibrationEnabled(bool value) async {
    _vibrationEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vibrationKey, value);
    notifyListeners();
  }

  Future<void> setWakelockEnabled(bool value) async {
    _wakelockEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wakelockKey, value);
    notifyListeners();
  }

  Future<void> setDarkMode(String value) async {
    _darkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_darkModeKey, value);
    notifyListeners();
  }
}
