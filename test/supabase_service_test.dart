import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;
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

  group('SupabaseService guard-first methods (client == null)', () {
    late SupabaseService svc;

    setUp(() async {
      svc = SupabaseService();
      svc.resetTestOverrides();
      await svc.initialize(); // unconfigured → offline
    });

    tearDown(() => svc.resetTestOverrides());

    test('currentUser null when override cleared', () {
      expect(svc.currentUser, isNull);
    });

    test('authStateChanges is empty stream when offline', () {
      expect(svc.authStateChanges, isA<Stream<AuthState>>());
    });

    test('team reads return null/empty offline', () async {
      expect(await svc.getMyTeam(), isNull);
      expect(await svc.getTeamByInviteCode('ABC'), isNull);
      expect(await svc.createTeam('Tim Saya'), isNull);
      expect(await svc.getTeamTodayScans('t1'), 0);
      expect(await svc.getTeamTotalScans('t1'), 0);
      expect(await svc.getTeamDistinctDates('t1'), isEmpty);
      expect(await svc.fetchTeamScans('t1'), isEmpty);
      expect(await svc.getTeamScansByDate('t1', '2026-01-01'), isEmpty);
      expect(await svc.searchTeamScans('t1', 'SPX'), isEmpty);
    });

    test('category ops are safe offline', () async {
      expect(await svc.fetchCategories(), isEmpty);
      await expectLater(svc.deleteCategory(1), completes);
      await expectLater(svc.upsertCategory(1, 'A', '#000'), completes);
      await expectLater(svc.syncTeamCategoriesToLocal(), completes);
    });

    test('scan writes are safe offline', () async {
      await expectLater(svc.deleteScanByResi('SPX1'), completes);
      await expectLater(
        svc.insertScanWithTeam(
          ScanRecord(
            resi: 'SPX1',
            marketplace: 'Shopee',
            scannedAt: DateTime.now(),
            date: '2026-01-01',
          ),
          teamId: 't1',
        ),
        completes,
      );
    });

    test('photo upload/download return null offline', () async {
      expect(await svc.downloadPhoto('path', '/tmp/x.jpg'), isNull);
      expect(await svc.uploadPhoto(File('/nonexistent.jpg'), 'f.jpg'), isNull);
    });

    test('auth actions are safe offline', () async {
      expect(await svc.signInWithGoogle(), isFalse);
      await expectLater(svc.signOut(), completes);
      // Offline → assume session valid (avoids disruptive logout).
      expect(await svc.isSessionValid(), isTrue);
      await expectLater(svc.clearSession(), completes);
    });

    test('subscription helpers safe offline', () async {
      expect(await svc.fetchMySubscription(), isNull);
      await expectLater(
        svc.upsertMySubscription({'tier': 'pro'}),
        completes,
      );
      await expectLater(svc.claimSubscriptionByEmail(), completes);
    });

    test('login history safe offline', () async {
      expect(await svc.fetchLoginHistory('u1'), isEmpty);
      await expectLater(svc.insertLoginHistory(deviceId: 'd1'), completes);
    });

    test('approval helpers safe offline', () async {
      expect(await svc.getMyApprovalStatus(), isNull);
    });
  });
}
