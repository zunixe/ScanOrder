import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../core/db/database_helper.dart';
import '../../core/supabase/supabase_service.dart';
import '../../models/order.dart';
import '../../models/category.dart';

class HistoryProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<ScannedOrder> orders = [];
  String selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  List<String> availableDates = [];
  String searchQuery = '';
  bool isSearching = false;
  int? filterCategoryId;
  List<ScanCategory> categories = [];
  Map<int, int> categoryCounts = {};

  String? _userId;

  void setUserId(String? userId) {
    _userId = userId;
  }

  Future<void> loadDates() async {
    availableDates = await _db.getDistinctDates(userId: _userId);
    notifyListeners();
  }

  Future<void> loadOrders() async {
    if (filterCategoryId != null) {
      orders = await _db.getOrdersByCategory(filterCategoryId!, userId: _userId);
    } else if (isSearching && searchQuery.isNotEmpty) {
      orders = await _db.searchOrders(searchQuery, userId: _userId);
    } else {
      orders = await _db.getOrdersByDate(selectedDate, userId: _userId);
    }
    // Attach categories to orders
    for (var i = 0; i < orders.length; i++) {
      if (orders[i].id != null) {
        final cats = await _db.getCategoriesForOrder(orders[i].id!);
        orders[i] = orders[i].copyWith(categories: cats);
      }
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
    await loadCategories();
  }

  Future<void> loadCategories() async {
    categories = await _db.getAllCategories(userId: _userId);
    categoryCounts = await _db.getCategoryCounts(userId: _userId);
    notifyListeners();
  }

  void setFilterCategory(int? categoryId) {
    filterCategoryId = categoryId;
    loadOrders();
  }

  Future<void> updatePhoto(int id, String? photoPath) async {
    await _db.updateOrderPhoto(id, photoPath);
    await loadOrders();
  }

  Future<List<ScannedOrder>> getAllForExport() async {
    final orders = await _db.getAllOrders(userId: _userId);
    debugPrint('[HistoryProvider] getAllForExport: userId=$_userId, orders=${orders.length}');
    // Attach categories to each order for export
    for (var i = 0; i < orders.length; i++) {
      if (orders[i].id != null) {
        final cats = await _db.getCategoriesForOrder(orders[i].id!);
        orders[i] = orders[i].copyWith(categories: cats);
      }
    }
    return orders;
  }
}
