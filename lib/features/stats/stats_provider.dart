import 'package:flutter/foundation.dart';
import '../../core/db/database_helper.dart';

class StatsProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Map<String, int> dailyStats = {};
  Map<String, int> marketplaceStats = {};
  int totalOrders = 0;
  int periodDays = 7;

  Future<void> loadStats() async {
    dailyStats = await _db.getDailyStats(periodDays);
    marketplaceStats = await _db.getMarketplaceStats();
    totalOrders = await _db.getTotalOrderCount();
    notifyListeners();
  }

  Future<void> setPeriod(int days) async {
    periodDays = days;
    await loadStats();
  }
}
