import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../core/db/database_helper.dart';
import '../../models/order.dart';

class HistoryProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<ScannedOrder> orders = [];
  String selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  List<String> availableDates = [];
  String searchQuery = '';
  bool isSearching = false;

  Future<void> loadDates() async {
    availableDates = await _db.getDistinctDates();
    notifyListeners();
  }

  Future<void> loadOrders() async {
    if (isSearching && searchQuery.isNotEmpty) {
      orders = await _db.searchOrders(searchQuery);
    } else {
      orders = await _db.getOrdersByDate(selectedDate);
    }
    notifyListeners();
  }

  Future<void> setDate(String date) async {
    selectedDate = date;
    isSearching = false;
    searchQuery = '';
    await loadOrders();
  }

  Future<void> search(String query) async {
    searchQuery = query;
    isSearching = query.isNotEmpty;
    await loadOrders();
  }

  Future<void> deleteOrder(int id) async {
    await _db.deleteOrder(id);
    await loadOrders();
    await loadDates();
  }

  Future<void> refresh() async {
    await loadDates();
    await loadOrders();
  }

  Future<List<ScannedOrder>> getAllForExport() async {
    return await _db.getAllOrders();
  }
}
