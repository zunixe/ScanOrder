import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../core/db/database_helper.dart';
import '../../core/supabase/supabase_service.dart';
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
    // Ambil order untuk dapat resi sebelum delete
    final all = await _db.getAllOrders();
    final order = all.firstWhere((o) => o.id == id, orElse: () => ScannedOrder(
      resi: '', marketplace: '', scannedAt: DateTime.now(), date: ''
    ));
    // Delete dari local DB
    await _db.deleteOrder(id);
    // Sync delete ke Supabase
    if (order.resi.isNotEmpty) {
      SupabaseService().deleteOrderByResi(order.resi);
    }
    await loadOrders();
    await loadDates();
  }

  Future<void> refresh() async {
    await loadDates();
    await loadOrders();
  }

  Future<void> updatePhoto(int id, String? photoPath) async {
    await _db.updateOrderPhoto(id, photoPath);
    await loadOrders();
  }

  Future<List<ScannedOrder>> getAllForExport() async {
    return await _db.getAllOrders();
  }
}
