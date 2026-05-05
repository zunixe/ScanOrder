import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scanorder/core/monitoring/analytics_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('AnalyticsService', () {
    test('track increments event count', () async {
      await AnalyticsService.track('test_event');
      final count = await AnalyticsService.getEventCount('test_event');
      expect(count, 1);
    });

    test('track increments multiple times', () async {
      await AnalyticsService.track('multi_event');
      await AnalyticsService.track('multi_event');
      await AnalyticsService.track('multi_event');
      final count = await AnalyticsService.getEventCount('multi_event');
      expect(count, 3);
    });

    test('getEventCount returns 0 for untracked event', () async {
      final count = await AnalyticsService.getEventCount('never_tracked');
      expect(count, 0);
    });

    test('appOpen increments total_opens', () async {
      await AnalyticsService.appOpen();
      await AnalyticsService.appOpen();
      final opens = await AnalyticsService.getTotalOpens();
      expect(opens, 2);
    });

    test('getTotalOpens returns 0 when never called', () async {
      final opens = await AnalyticsService.getTotalOpens();
      expect(opens, 0);
    });

    test('screenView tracks screen_view event', () async {
      await AnalyticsService.screenView('home');
      final count = await AnalyticsService.getEventCount('screen_view');
      expect(count, 1);
    });

    test('scanComplete tracks with properties', () async {
      await AnalyticsService.scanComplete('Shopee', hasPhoto: true);
      final count = await AnalyticsService.getEventCount('scan_complete');
      expect(count, 1);
    });

    test('scanDuplicate tracks with resi prefix', () async {
      await AnalyticsService.scanDuplicate('SPX123456789');
      final count = await AnalyticsService.getEventCount('scan_duplicate');
      expect(count, 1);
    });

    test('login tracks with method', () async {
      await AnalyticsService.login('google');
      final count = await AnalyticsService.getEventCount('login');
      expect(count, 1);
    });

    test('logout tracks event', () async {
      await AnalyticsService.logout();
      final count = await AnalyticsService.getEventCount('logout');
      expect(count, 1);
    });

    test('exportData tracks with format', () async {
      await AnalyticsService.exportData('csv');
      final count = await AnalyticsService.getEventCount('export_data');
      expect(count, 1);
    });

    test('syncComplete tracks with count', () async {
      await AnalyticsService.syncComplete(count: 5);
      final count = await AnalyticsService.getEventCount('sync_complete');
      expect(count, 1);
    });

    test('syncError tracks event', () async {
      await AnalyticsService.syncError('timeout');
      final count = await AnalyticsService.getEventCount('sync_error');
      expect(count, 1);
    });

    test('categoryCreated tracks event', () async {
      await AnalyticsService.categoryCreated('Paket Besar');
      final count = await AnalyticsService.getEventCount('category_created');
      expect(count, 1);
    });

    test('subscriptionView tracks event', () async {
      await AnalyticsService.subscriptionView();
      final count = await AnalyticsService.getEventCount('subscription_view');
      expect(count, 1);
    });

    test('subscriptionPurchase tracks with tier', () async {
      await AnalyticsService.subscriptionPurchase('pro');
      final count = await AnalyticsService.getEventCount('subscription_purchase');
      expect(count, 1);
    });

    test('teamJoin tracks event', () async {
      await AnalyticsService.teamJoin();
      final count = await AnalyticsService.getEventCount('team_join');
      expect(count, 1);
    });

    test('teamCreate tracks event', () async {
      await AnalyticsService.teamCreate();
      final count = await AnalyticsService.getEventCount('team_create');
      expect(count, 1);
    });

    test('different events are tracked independently', () async {
      await AnalyticsService.track('event_a');
      await AnalyticsService.track('event_a');
      await AnalyticsService.track('event_b');
      expect(await AnalyticsService.getEventCount('event_a'), 2);
      expect(await AnalyticsService.getEventCount('event_b'), 1);
    });
  });
}
