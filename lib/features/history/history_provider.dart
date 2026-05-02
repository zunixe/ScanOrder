import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../core/db/database_helper.dart';
import '../../core/supabase/supabase_service.dart';
import '../../models/order.dart';
import '../../models/category.dart';
import '../../services/sync_queue.dart';

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

  /// Returns orders filtered by active category (for team mode UI)
  List<ScannedOrder> get filteredOrders {
    if (filterCategoryId == null) return orders;
    // In team mode, categories come from Supabase nested data
    // Match by category name since local id != Supabase UUID
    final filterCat = categories.where((c) => c.id == filterCategoryId).firstOrNull;
    if (filterCat == null) return orders;
    return orders.where((o) =>
      o.categories.any((c) => c.name == filterCat.name && c.userId == filterCat.userId)
    ).toList();
  }

  String? _userId;
  String? _teamId;
  String? _adminUserId;

  void setUserId(String? userId) {
    _userId = userId;
  }

  void setTeamContext(String? teamId, [String? adminUserId]) {
    _teamId = teamId;
    _adminUserId = adminUserId;
  }

  Future<void> loadDates() async {
    if (_teamId != null) {
      debugPrint('[History] loadDates TEAM mode: teamId=$_teamId');
      availableDates = await SupabaseService().getTeamDistinctDates(_teamId!);
      debugPrint('[History] loadDates TEAM result: ${availableDates.length} dates = $availableDates');
    } else {
      debugPrint('[History] loadDates PERSONAL mode: userId=$_userId');
      availableDates = await _db.getDistinctDates(userId: _userId);
      debugPrint('[History] loadDates PERSONAL result: ${availableDates.length} dates');
    }
    notifyListeners();
  }

  Future<void> loadOrders() async {
    if (_teamId != null) {
      // Team mode: query Supabase
      debugPrint('[History] loadOrders TEAM mode: teamId=$_teamId, date=$selectedDate, searching=$isSearching');
      List<Map<String, dynamic>> raw;
      if (isSearching && searchQuery.isNotEmpty) {
        raw = await SupabaseService().searchTeamOrders(_teamId!, searchQuery);
      } else {
        raw = await SupabaseService().getTeamOrdersByDate(_teamId!, selectedDate);
      }
      debugPrint('[History] loadOrders TEAM raw: ${raw.length} rows');
      if (raw.isNotEmpty) debugPrint('[History] loadOrders TEAM sample: ${raw.first}');
      orders = raw.map((m) => ScannedOrder.fromSupabase(m)).toList();
      debugPrint('[History] loadOrders TEAM parsed: ${orders.length} orders');
    } else {
      // Personal mode: query local DB
      if (filterCategoryId != null) {
        orders = await _db.getOrdersByCategory(filterCategoryId!, userId: _userId);
      } else if (isSearching && searchQuery.isNotEmpty) {
        orders = await _db.searchOrders(searchQuery, userId: _userId);
      } else {
        orders = await _db.getOrdersByDate(selectedDate, userId: _userId);
      }
      // Attach categories to orders (local only)
      for (var i = 0; i < orders.length; i++) {
        if (orders[i].id != null) {
          final cats = await _db.getCategoriesForOrder(orders[i].id!);
          orders[i] = orders[i].copyWith(categories: cats);
        }
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
    if (_teamId != null) {
      // Team mode: sync categories from Supabase to local DB first
      await _syncTeamCategories();
      // Load category names from local DB (now synced)
      categories = await _db.getAllCategories(userId: _userId, adminUserId: _adminUserId);
      // Use local DB counts (always accurate) + Supabase counts (cross-device) — take the max
      final localCounts = await _db.getCategoryCounts(userId: _userId);
      final supStats = await SupabaseService().getTeamCategoryStats(_teamId!);
      categoryCounts = {};
      for (final cat in categories) {
        final local = localCounts[cat.id] ?? 0;
        final remote = supStats[cat.name] ?? 0;
        categoryCounts[cat.id!] = local > remote ? local : remote;
      }
    } else {
      categories = await _db.getAllCategories(userId: _userId);
      categoryCounts = await _db.getCategoryCounts(userId: _userId);
    }
    debugPrint('[History] loadCategories: ${categories.length} cats, teamId=$_teamId, counts=$categoryCounts');
    notifyListeners();
  }

  Future<void> _syncTeamCategories() async {
    final sup = SupabaseService();
    final userId = sup.currentUser?.id;
    final effectiveAdminId = (_adminUserId != null && userId != null && _adminUserId != userId) ? _adminUserId : null;
    await sup.syncTeamCategoriesToLocal(adminUserId: effectiveAdminId);
  }

  void setFilterCategory(int? categoryId) async {
    filterCategoryId = categoryId;
    if (_teamId != null && categoryId != null) {
      // Team mode with category: load all team orders from Supabase,
      // then filter by matching resi with local scan_categories
      final allRaw = await SupabaseService().getTeamOrdersByDate(_teamId!, selectedDate);
      final allOrders = allRaw.map((m) => ScannedOrder.fromSupabase(m)).toList();

      // Get local resis that belong to this category
      final localCatOrders = await _db.getOrdersByCategory(categoryId, userId: _userId, teamId: _teamId);
      final localResis = localCatOrders.map((o) => o.resi).toSet();

      // Filter: if Supabase has scan_categories, use those; otherwise use local resis
      final filterCat = categories.where((c) => c.id == categoryId).firstOrNull;
      orders = allOrders.where((o) {
        // Check Supabase nested categories first
        if (o.categories.isNotEmpty) {
          return o.categories.any((c) => c.name == filterCat?.name);
        }
        // Fallback: match by local resi
        return localResis.contains(o.resi);
      }).toList();

      // Attach local categories to orders that don't have them from Supabase
      for (var i = 0; i < orders.length; i++) {
        if (orders[i].categories.isEmpty && filterCat != null) {
          orders[i] = orders[i].copyWith(categories: [filterCat]);
        }
      }
      notifyListeners();
    } else if (_teamId != null && categoryId == null) {
      // Back from category: just clear filter, orders already loaded
      filterCategoryId = null;
      await loadOrders();
    } else {
      await loadOrders();
    }
  }

  Future<void> updatePhoto(int id, String? photoPath) async {
    await _db.updateOrderPhoto(id, photoPath);
    // Update in-memory orders immediately (don't re-fetch from Supabase which may have old photo)
    final idx = orders.indexWhere((o) => o.id == id);
    if (idx >= 0) {
      orders[idx] = orders[idx].copyWith(photoPath: photoPath);
    }
    // Sync photo change to Supabase
    if (photoPath != null && _userId != null) {
      final order = idx >= 0 ? orders[idx] : await _db.getOrderById(id);
      final syncQueue = SyncQueue();
      syncQueue.enqueue(SyncTaskType.uploadPhoto, {
        'local_path': photoPath,
        'user_id': _userId!,
        'resi': order?.resi ?? '',
        'cloud_filename': '$_userId/${DateTime.now().millisecondsSinceEpoch}.jpg',
      });
    } else if (photoPath == null && _userId != null) {
      // Photo removed — update Supabase to null
      try {
        final order = idx >= 0 ? orders[idx] : await _db.getOrderById(id);
        if (order != null) {
          final client = SupabaseService().client;
          if (client != null) {
            await client.from('scans').update({'photo_url': null}).eq('resi', order.resi);
          }
        }
      } catch (e) {
        debugPrint('[History] updatePhoto remove from Supabase error: $e');
      }
    }
    notifyListeners();
  }

  Future<List<ScannedOrder>> getAllForExport() async {
    if (_teamId != null) {
      // Team mode: fetch all from Supabase
      final raw = await SupabaseService().fetchTeamOrders(_teamId!);
      return raw.map((m) => ScannedOrder.fromSupabase(m)).toList();
    }
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
