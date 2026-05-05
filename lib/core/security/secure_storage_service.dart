import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../logging/logger.dart';

/// Secure storage for sensitive data (tokens, device ID, etc.)
/// Uses platform-specific encrypted storage:
/// - Android: EncryptedSharedPreferences (AES-256)
/// - iOS: Keychain
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  // Keys
  static const _deviceIdKey = 'device_id';
  static const _dbEncryptionKey = 'db_encryption_key';

  // ─── Device ID ──────────────────────────────────────────────────────

  static Future<String?> getDeviceId() async {
    try {
      return await _storage.read(key: _deviceIdKey);
    } catch (e) {
      AppLogger.error('SecureStorage', 'Failed to read device ID', exception: e);
      return null;
    }
  }

  static Future<void> setDeviceId(String id) async {
    try {
      await _storage.write(key: _deviceIdKey, value: id);
    } catch (e) {
      AppLogger.error('SecureStorage', 'Failed to write device ID', exception: e);
    }
  }

  // ─── DB Encryption Key ───────────────────────────────────────────────

  static Future<String?> getDbEncryptionKey() async {
    try {
      return await _storage.read(key: _dbEncryptionKey);
    } catch (e) {
      AppLogger.error('SecureStorage', 'Failed to read DB key', exception: e);
      return null;
    }
  }

  static Future<void> setDbEncryptionKey(String key) async {
    try {
      await _storage.write(key: _dbEncryptionKey, value: key);
    } catch (e) {
      AppLogger.error('SecureStorage', 'Failed to write DB key', exception: e);
    }
  }

  // ─── Generic ─────────────────────────────────────────────────────────

  static Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      AppLogger.error('SecureStorage', 'Failed to read $key', exception: e);
      return null;
    }
  }

  static Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      AppLogger.error('SecureStorage', 'Failed to write $key', exception: e);
    }
  }

  static Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      AppLogger.error('SecureStorage', 'Failed to delete $key', exception: e);
    }
  }

  static Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      AppLogger.error('SecureStorage', 'Failed to delete all', exception: e);
    }
  }
}
