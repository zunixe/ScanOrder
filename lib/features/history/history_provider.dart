import 'package:flutter/foundation.dart';
import '../../core/logging/logger.dart';
import 'package:intl/intl.dart';
import '../../core/db/database_helper.dart';
import '../../core/state/async_state.dart';
import '../../core/supabase/supabase_service.dart';
import '../../models/scan_record.dart';
import '../../models/category.dart';
import '../../services/sync_queue.dart';

class HistoryProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<ScanRecord> scans = [];
  String selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  static const String allDatesSentinel = '__ALL__';
  List<String> availableDates = [];
  String searchQuery = '';
  bool isSearching = false;
  int? filterCategoryId;
  List<ScanCategory> categories = [];
  Map<int, int> categoryCounts = {};

  // Async states for UI
  AsyncState<void> scansState = const AsyncState.idle();
  AsyncState<void> datesState = const AsyncState.idle();
  AsyncState<void> categoriesLoadState = const AsyncState.idle();

  /// Returns scans filtered by active category (for team mode UI)
  List<ScanRecord> get filteredScans {
    if (filterCategoryId == null) return scans;
    // In team mode, categories come from Supabase nested data
    // Match by category name since local id != Supabase UUID
    final filterCat = categories.where((c) => c.id == filterCategoryId).firstOrNull;
    if (filterCat == null) return scans;
    return scans.where((o) =>
      o.categories.any((c) => c.name == filterCat.name && c.userId == filterCat.userId)
    ).toList();
  }

  String? _userId;
  String? _teamId;
  String? _adminUserId;
  String? get teamId => _teamId;

  void setUserId(String? userId) {
    _userId = userId;
  }

  void setTeamContext(String? teamId, [String? adminUserId]) {
    _teamId = teamId;
    _adminUserId = adminUserId;
  }

  Future<void> loadDates() async {
    datesState = const AsyncState.loading();
    notifyListeners();
    try {
      if (_teamId != null) {
        AppLogger.info('History', 'loadDates TEAM mode: teamId=$_teamId');
        availableDates = await SupabaseService().getTeamDistinctDates(_teamId!);
        AppLogger.info('History', 'loadDates TEAM result: ${availableDates.length} dates = $availableDates');
      } else {
        AppLogger.info('History', 'loadDates PERSONAL mode: userId=$_userId');
        availableDates = await _db.getDistinctDates(userId: _userId);
        AppLogger.info('History', 'loadDates PERSONAL result: ${availableDates.length} dates');
      }
      // Auto-select first available date if today has no scans (but not if user chose "Semua")
      if (selectedDate != allDatesSentinel && availableDates.isNotEmpty && !availableDates.contains(selectedDate)) {
        selectedDate = availableDates.first;
        AppLogger.info('History', 'loadDates: auto-selected date=$selectedDate');
      }
      datesState = const AsyncState.data(null);
      notifyListeners();
    } catch (e, stack) {
      AppLogger.info('History', 'loadDates error: $e');
      datesState = AsyncState.error(e.toString(), stackTrace: stack, retry: loadDates);
      notifyListeners();
    }
  }

  Future<void> loadScans() async {
    scansState = const AsyncState.loading(previousData: null);
    notifyListeners();
    try {
      if (_teamId != null) {
        // Team mode: query Supabase
        AppLogger.info('History', 'loadScans TEAM mode: teamId=$_teamId, date=$selectedDate, searching=$isSearching');
        List<Map<String, dynamic>> raw;
        if (isSearching && searchQuery.isNotEmpty) {
          raw = await SupabaseService().searchTeamScans(_teamId!, searchQuery);
        } else if (selectedDate == allDatesSentinel) {
          raw = await SupabaseService().fetchTeamScans(_teamId!);
        } else {
          raw = await SupabaseService().getTeamScansByDate(_teamId!, selectedDate);
        }
        AppLogger.info('History', 'loadScans TEAM raw: ${raw.length} rows');
        if (raw.isNotEmpty) AppLogger.info('History', 'loadScans TEAM sample: ${raw.first}');
        scans = raw.map((m) => ScanRecord.fromSupabase(m)).toList();
        AppLogger.info('History', 'loadScans TEAM parsed: ${scans.length} scans');
      } else {
        // Personal mode: query local DB
        if (filterCategoryId != null) {
          scans = await _db.getScansByCategory(filterCategoryId!, userId: _userId);
        } else if (isSearching && searchQuery.isNotEmpty) {
          scans = await _db.searchScans(searchQuery, userId: _userId);
        } else if (selectedDate == allDatesSentinel) {
          scans = await _db.getAllScans(userId: _userId);
        } else {
          scans = await _db.getScansByDate(selectedDate, userId: _userId);
        }
        // Attach categories to scans (local only)
        for (var i = 0; i < scans.length; i++) {
          if (scans[i].id != null) {
            final cats = await _db.getCategoriesForOrder(scans[i].id!);
            scans[i] = scans[i].copyWith(categories: cats);
          }
        }
      }
      scansState = const AsyncState.data(null);
      notifyListeners();
    } catch (e, stack) {
      AppLogger.info('History', 'loadScans error: $e');
      scansState = AsyncState.error(e.toString(), stackTrace: stack, retry: loadScans);
      notifyListeners();
    }
  }

  Future<void> setDate(String date) async {
    selectedDate = date;
    isSearching = false;
    searchQuery = '';
    await loadScans();
  }

  Future<void> search(String query) async {
    searchQuery = query;
    isSearching = query.isNotEmpty;
    await loadScans();
  }

  Future<void> deleteScan(int id) async {
    // Ambil order untuk dapat resi sebelum delete
    final all = await _db.getAllScans();
    final order = all.firstWhere((o) => o.id == id, orElse: () => ScanRecord(
      resi: '', marketplace: '', scannedAt: DateTime.now(), date: ''
    ));
    // Delete dari local DB
    await _db.deleteScan(id);
    // Sync delete ke Supabase
    if (order.resi.isNotEmpty) {
      SupabaseService().deleteScanByResi(order.resi);
    }
    await loadScans();
    await loadDates();
  }

  Future<void> refresh() async {
    await loadDates();
    await loadScans();
    await loadCategories();
  }

  Future<void> loadCategories() async {
    categoriesLoadState = const AsyncState.loading();
    notifyListeners();
    try {
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
      AppLogger.info('History', 'loadCategories: ${categories.length} cats, teamId=$_teamId, counts=$categoryCounts');
      categoriesLoadState = const AsyncState.data(null);
      notifyListeners();
    } catch (e, stack) {
      AppLogger.info('History', 'loadCategories error: $e');
      categoriesLoadState = AsyncState.error(e.toString(), stackTrace: stack, retry: loadCategories);
      notifyListeners();
    }
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
      // Team mode with category: load all team scans from Supabase,
      // then filter by matching resi with local scan_categories
      final allRaw = selectedDate == allDatesSentinel
          ? await SupabaseService().fetchTeamScans(_teamId!)
          : await SupabaseService().getTeamScansByDate(_teamId!, selectedDate);
      final allOrders = allRaw.map((m) => ScanRecord.fromSupabase(m)).toList();

      // Get local resis that belong to this category
      final localCatOrders = await _db.getScansByCategory(categoryId, userId: _userId, teamId: _teamId);
      final localResis = localCatOrders.map((o) => o.resi).toSet();

      // Filter: if Supabase has scan_categories, use those; otherwise use local resis
      final filterCat = categories.where((c) => c.id == categoryId).firstOrNull;
      scans = allOrders.where((o) {
        // Check Supabase nested categories first
        if (o.categories.isNotEmpty) {
          return o.categories.any((c) => c.name == filterCat?.name);
        }
        // Fallback: match by local resi
        return localResis.contains(o.resi);
      }).toList();

      // Attach local categories to scans that don't have them from Supabase
      for (var i = 0; i < scans.length; i++) {
        if (scans[i].categories.isEmpty && filterCat != null) {
          scans[i] = scans[i].copyWith(categories: [filterCat]);
        }
      }
      notifyListeners();
    } else if (_teamId != null && categoryId == null) {
      // Back from category: just clear filter, scans already loaded
      filterCategoryId = null;
      await loadScans();
    } else {
      await loadScans();
    }
  }

  Future<void> updatePhoto(int id, String? photoPath) async {
    await _db.updateScanPhoto(id, photoPath);
    // Update in-memory scans immediately (don't re-fetch from Supabase which may have old photo)
    final idx = scans.indexWhere((o) => o.id == id);
    if (idx >= 0) {
      scans[idx] = scans[idx].copyWith(photoPath: photoPath);
    }
    // Sync photo change to Supabase
    if (photoPath != null && _userId != null) {
      final order = idx >= 0 ? scans[idx] : await _db.getScanById(id);
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
        final order = idx >= 0 ? scans[idx] : await _db.getScanById(id);
        if (order != null) {
          final client = SupabaseService().client;
          if (client != null) {
            await client.from('scans').update({'photo_url': null}).eq('resi', order.resi);
          }
        }
      } catch (e) {
        AppLogger.info('History', 'updatePhoto remove from Supabase error: $e');
      }
    }
    notifyListeners();
  }

  /// Update in-memory photoPath to local cached path (no DB/Supabase write)
  void updatePhotoLocal(int id, String localPath) {
    final idx = scans.indexWhere((o) => o.id == id);
    if (idx >= 0) {
      scans[idx] = scans[idx].copyWith(photoPath: localPath);
    }
    notifyListeners();
  }

  Future<List<ScanRecord>> getAllForExport() async {
    if (_teamId != null) {
      // Team mode: fetch all from Supabase
      final raw = await SupabaseService().fetchTeamScans(_teamId!);
      return raw.map((m) => ScanRecord.fromSupabase(m)).toList();
    }
    final scans = await _db.getAllScans(userId: _userId);
    AppLogger.info('HistoryProvider', 'getAllForExport: userId=$_userId, scans=${scans.length}');
    // Attach categories to each order for export
    for (var i = 0; i < scans.length; i++) {
      if (scans[i].id != null) {
        final cats = await _db.getCategoriesForOrder(scans[i].id!);
        scans[i] = scans[i].copyWith(categories: cats);
      }
    }
    return scans;
  }
}
