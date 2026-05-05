import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/core/supabase/supabase_service.dart';
import 'package:scanorder/models/scan_record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupabaseService', () {
    test('is singleton', () {
      final a = SupabaseService();
      final b = SupabaseService();
      expect(identical(a, b), true);
    });

    test('isOffline defaults to false when not initialized', () {
      final svc = SupabaseService();
      // Before initialize() is called, isOffline is false
      expect(svc.isOffline, false);
    });

    test('url and key are from compile-time env', () {
      final svc = SupabaseService();
      // In test environment, these are empty strings
      expect(svc.url, isA<String>());
      expect(svc.key, isA<String>());
    });

    test('initialize does not throw in test environment', () async {
      final svc = SupabaseService();
      // Should gracefully handle missing config
      await expectLater(svc.initialize(), completes);
    });

    test('currentUser is null in test environment', () {
      final svc = SupabaseService();
      expect(svc.currentUser, isNull);
    });

    test('authStateChanges is a stream', () {
      final svc = SupabaseService();
      expect(svc.authStateChanges, isA<Stream>());
    });

    test('client getter returns null when not configured', () {
      final svc = SupabaseService();
      // _client is private, but we can test behavior through public methods
      // fetchOrders should return empty list when client is null
      expect(svc.fetchOrders(), completion(equals([])));
    });

    test('fetchOrders returns empty when not initialized', () async {
      final svc = SupabaseService();
      final result = await svc.fetchOrders();
      expect(result, isEmpty);
    });

    test('fetchCategories returns empty when not initialized', () async {
      final svc = SupabaseService();
      final result = await svc.fetchCategories();
      expect(result, isEmpty);
    });

    test('insertScan does not throw when not initialized', () async {
      final svc = SupabaseService();
      final record = ScanRecord(
        resi: 'SPX123',
        marketplace: 'Shopee',
        scannedAt: DateTime.now(),
        date: '2026-05-06',
      );
      await expectLater(svc.insertScan(record), completes);
    });

    test('uploadPhoto returns null when not initialized', () async {
      final svc = SupabaseService();
      // Can't create a real File in test, but the method should handle null client
      // The _client getter returns null when not configured
      final result = await svc.uploadPhoto(
        // Use a non-existent file - the null client check happens first
        File('/nonexistent.jpg'),
        'test.jpg',
      );
      expect(result, isNull);
    });
  });

  group('SupabaseService offline mode logic', () {
    test('isOffline can be set to true after failed init', () async {
      final svc = SupabaseService();
      await svc.initialize();
      // In test env without real URL, isOffline should be true after init
      expect(svc.isOffline, true);
    });

    test('methods handle offline gracefully', () async {
      final svc = SupabaseService();
      await svc.initialize();
      // All methods should work without throwing in offline mode
      expect(svc.fetchOrders(), completion(isEmpty));
      expect(svc.fetchCategories(), completion(isEmpty));
    });
  });
}
