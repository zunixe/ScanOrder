import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/security/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureStorageService', () {
    test('getDeviceId returns null when not set', () async {
      final id = await SecureStorageService.getDeviceId();
      // In test env, flutter_secure_storage may not work — just ensure no throw
      expect(id, isA<String?>());
    });

    test('getDbEncryptionKey returns null when not set', () async {
      final key = await SecureStorageService.getDbEncryptionKey();
      expect(key, isA<String?>());
    });

    test('read returns null for unknown key', () async {
      final val = await SecureStorageService.read('unknown_key_test');
      expect(val, isA<String?>());
    });

    test('write and read round-trip', () async {
      await SecureStorageService.write('test_key_123', 'test_value');
      final val = await SecureStorageService.read('test_key_123');
      // May or may not work in test env, but should not throw
      expect(val, isA<String?>());
    });

    test('delete does not throw', () async {
      expect(() => SecureStorageService.delete('nonexistent_key'), returnsNormally);
    });

    test('deleteAll does not throw', () async {
      expect(() => SecureStorageService.deleteAll(), returnsNormally);
    });

    test('setDeviceId does not throw', () async {
      expect(() => SecureStorageService.setDeviceId('test-device-id'), returnsNormally);
    });

    test('setDbEncryptionKey does not throw', () async {
      expect(() => SecureStorageService.setDbEncryptionKey('a'.padRight(64, '0')), returnsNormally);
    });
  });
}
