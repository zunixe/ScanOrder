import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User, AuthState;
import 'package:scanorder/core/supabase/supabase_service.dart';
import 'package:scanorder/models/scan_record.dart';

import 'helpers/fake_supabase.dart';
import 'helpers/fake_supabase_client.dart';

class MockUser extends Mock implements User {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SupabaseService svc;
  late FakeSupabaseClient client;
  late MockUser user;

  setUp(() {
    svc = SupabaseService();
    client = FakeSupabaseClient();
    user = MockUser();
    when(() => user.id).thenReturn('u1');
    when(() => user.email).thenReturn('u1@example.com');
    svc.overrideClient = client;
    svc.overrideCurrentUser = user;
  });

  tearDown(() => svc.resetTestOverrides());

  group('team RPCs', () {
    test('getTeamByInviteCode returns null for empty', () async {
      client.setRpc('get_team_by_invite_code', response: []);
      expect(await svc.getTeamByInviteCode('ABC'), isNull);
    });

    test('getTeamByInviteCode parses team row', () async {
      client.setRpc('get_team_by_invite_code', response: [
        {
          'id': 't1',
          'name': 'Tim',
          'invite_code': 'ABC',
          'created_by': 'u1',
          'created_at': DateTime.now().toIso8601String(),
        },
      ]);
      final team = await svc.getTeamByInviteCode('abc');
      expect(team, isNotNull);
      expect(team!.id, 't1');
    });

    test('getTeamByInviteCode swallows errors', () async {
      client.setRpc('get_team_by_invite_code', error: Exception('boom'));
      expect(await svc.getTeamByInviteCode('ABC'), isNull);
    });
  });

  group('team queries', () {
    test('leaveTeam deletes membership and returns true', () async {
      final builder = FakeTableBuilder(response: 1);
      client.tables['team_members'] = builder;
      expect(await svc.leaveTeam('t1'), isTrue);
      expect(builder.calls, contains('delete'));
      expect(builder.calls.where((c) => c.startsWith('eq')), hasLength(2));
    });

    test('getMyTeam returns null when no membership row', () async {
      client.tables['team_members'] = FakeTableBuilder(response: null);
      expect(await svc.getMyTeam(), isNull);
    });

    test('getMyTeam returns null on client error', () async {
      client.tables['team_members'] = FakeTableBuilder(error: Exception('boom'));
      expect(await svc.getMyTeam(), isNull);
    });
  });

  group('scan queries', () {
    test('fetchOrders returns mapped rows', () async {
      client.tables['scans'] = FakeTableBuilder(response: [
        {'res_id': 'x'},
      ]);
      final rows = await svc.fetchOrders();
      expect(rows, hasLength(1));
    });

    test('fetchOrders returns empty on error', () async {
      client.tables['scans'] = FakeTableBuilder(error: Exception('boom'));
      expect(await svc.fetchOrders(), isEmpty);
    });

    test('fetchCategories returns rows', () async {
      client.tables['categories'] = FakeTableBuilder(response: [
        {'id': 1, 'name': 'A'},
      ]);
      expect(await svc.fetchCategories(), hasLength(1));
    });

    test('insertScan writes and completes', () async {
      client.tables['scans'] = FakeTableBuilder(response: const []);
      await expectLater(
        svc.insertScan(ScanRecord(
          resi: 'SPX1',
          marketplace: 'Shopee',
          scannedAt: DateTime.now(),
          date: '2026-01-01',
        )),
        completes,
      );
    });

    test('deleteScanByResi completes', () async {
      client.tables['scans'] = FakeTableBuilder(response: 1);
      await expectLater(svc.deleteScanByResi('SPX1'), completes);
    });
  });

  group('subscription & packages', () {
    test('fetchMySubscription returns null on error', () async {
      client.tables['user_subscriptions'] =
          FakeTableBuilder(error: Exception('boom'));
      expect(await svc.fetchMySubscription(), isNull);
    });

    test('upsertMySubscription completes', () async {
      client.tables['user_subscriptions'] = FakeTableBuilder(response: 1);
      await expectLater(
        svc.upsertMySubscription({'tier': 'pro'}),
        completes,
      );
    });

    test('fetchPackages returns rows', () async {
      client.tables['packages'] = FakeTableBuilder(response: [
        {'id': 'free', 'scan_limit': 200},
      ]);
      final pkgs = await svc.fetchPackages();
      expect(pkgs, hasLength(1));
    });

    test('fetchPackages returns empty on error', () async {
      client.tables['packages'] = FakeTableBuilder(error: Exception('x'));
      expect(await svc.fetchPackages(), isEmpty);
    });
  });

  group('approvals & sessions', () {
    test('fetchPendingApprovals returns rows', () async {
      client.setRpc('admin_list_pending_approvals', response: [
        {'id': '1'},
      ]);
      expect(await svc.fetchPendingApprovals(), hasLength(1));
    });

    test('fetchLoginHistory returns rows', () async {
      client.tables['login_history'] = FakeTableBuilder(response: [
        {'id': '1'},
      ]);
      expect(await svc.fetchLoginHistory('u1'), hasLength(1));
    });

    test('insertLoginHistory completes', () async {
      client.tables['login_history'] = FakeTableBuilder(response: 1);
      await expectLater(svc.insertLoginHistory(deviceId: 'd1'), completes);
    });
  });

  group('category sync', () {
    test('upsertCategory completes', () async {
      client.tables['categories'] = FakeTableBuilder(response: 1);
      await expectLater(svc.upsertCategory(1, 'A', '#000'), completes);
    });

    test('deleteCategory completes', () async {
      client.tables['categories'] = FakeTableBuilder(response: 1);
      await expectLater(svc.deleteCategory(1), completes);
    });

    test('syncTeamCategoriesToLocal completes', () async {
      client.tables['categories'] = FakeTableBuilder(response: const []);
      await expectLater(svc.syncTeamCategoriesToLocal(), completes);
    });
  });

  group('team reads', () {
    test('fetchTeamScans returns rows', () async {
      client.tables['scans'] = FakeTableBuilder(response: [
        {'id': 1, 'resi': 'SPX1'},
      ]);
      expect(await svc.fetchTeamScans('t1'), hasLength(1));
    });

    test('fetchTeamScans returns empty on error', () async {
      client.tables['scans'] = FakeTableBuilder(error: Exception('x'));
      expect(await svc.fetchTeamScans('t1'), isEmpty);
    });

    test('getTeamDistinctDates deduplicates dates', () async {
      client.tables['scans'] = FakeTableBuilder(response: [
        {'date': '2026-01-01'},
        {'date': '2026-01-01'},
        {'date': '2026-01-02'},
      ]);
      final dates = await svc.getTeamDistinctDates('t1');
      expect(dates, ['2026-01-01', '2026-01-02']);
    });

    test('getTeamScansByDate returns rows', () async {
      client.tables['scans'] = FakeTableBuilder(response: [
        {'id': 1, 'resi': 'SPX1', 'date': '2026-01-01'},
      ]);
      expect(await svc.getTeamScansByDate('t1', '2026-01-01'), hasLength(1));
    });

    test('searchTeamScans returns rows', () async {
      client.tables['scans'] = FakeTableBuilder(response: [
        {'id': 1, 'resi': 'SPX1'},
      ]);
      expect(await svc.searchTeamScans('t1', 'SPX'), hasLength(1));
    });

    test('getTeamTotalScans counts rows', () async {
      client.tables['scans'] = FakeTableBuilder(response: [
        {'id': 1},
        {'id': 2},
      ]);
      expect(await svc.getTeamTotalScans('t1'), 2);
    });

    test('getTeamTodayScans counts rows', () async {
      client.tables['scans'] = FakeTableBuilder(response: [
        {'id': 1},
      ]);
      expect(await svc.getTeamTodayScans('t1'), 1);
    });

    test('getTeamDailyStats aggregates by date', () async {
      client.tables['scans'] = FakeTableBuilder(response: [
        {'date': '2026-01-01'},
        {'date': '2026-01-01'},
      ]);
      final stats = await svc.getTeamDailyStats('t1', 7);
      expect(stats['2026-01-01'], 2);
    });

    test('getTeamMarketplaceStats counts and sorts', () async {
      client.tables['scans'] = FakeTableBuilder(response: [
        {'marketplace': 'Shopee'},
        {'marketplace': 'Shopee'},
        {'marketplace': 'JNE'},
      ]);
      final stats = await svc.getTeamMarketplaceStats('t1');
      expect(stats['Shopee'], 2);
      expect(stats.keys.first, 'Shopee'); // sorted desc
    });

    test('getTeamCategoryStats aggregates by category name', () async {
      client.tables['scan_categories'] = FakeTableBuilder(response: [
        {
          'categories': {'name': 'Keranjang'},
        },
        {
          'categories': {'name': 'Keranjang'},
        },
      ]);
      final stats = await svc.getTeamCategoryStats('t1');
      expect(stats['Keranjang'], 2);
    });
  });

  group('uploadPhoto guard', () {
    test('uploadPhoto returns null when storage throws', () async {
      final result = await svc.uploadPhoto(File('/tmp/x.jpg'), 'f.jpg');
      expect(result, isNull);
    });
  });

  group('authStateChanges', () {
    test('returns a stream when client present', () {
      expect(svc.authStateChanges, isA<Stream<AuthState>>());
    });
  });
}
