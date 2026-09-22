import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/logging/logger.dart';
import '../core/notifications/notification_service.dart';
import '../core/supabase/supabase_service.dart';

/// Statistik ringkas untuk dashboard admin.
/// Diisi dari RPC [admin_stats] di Supabase (guard is_super_admin()).
class AdminStats {
  final int totalScans;
  final int scansToday;
  final int totalUsers;
  final int totalTeams;
  final int activeSubscriptions;

  const AdminStats({
    this.totalScans = 0,
    this.scansToday = 0,
    this.totalUsers = 0,
    this.totalTeams = 0,
    this.activeSubscriptions = 0,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) => AdminStats(
        totalScans: (json['total_scans'] as num?)?.toInt() ?? 0,
        scansToday: (json['scans_today'] as num?)?.toInt() ?? 0,
        totalUsers: (json['total_users'] as num?)?.toInt() ?? 0,
        totalTeams: (json['total_teams'] as num?)?.toInt() ?? 0,
        activeSubscriptions:
            (json['active_subscriptions'] as num?)?.toInt() ?? 0,
      );
}

/// Filter untuk browser scans di panel admin.
class ScanFilter {
  final String? marketplace;
  final String? teamId;
  /// Batas bawah (inklusif) berdasarkan kolom scanned_at (epoch millis).
  final DateTime? from;
  /// Batas atas (eksklusif).
  final DateTime? to;

  const ScanFilter({this.marketplace, this.teamId, this.from, this.to});

  bool get isEmpty =>
      marketplace == null && teamId == null && from == null && to == null;

  String describe() {
    final parts = <String>[];
    if (marketplace != null) parts.add(marketplace!);
    if (teamId != null) parts.add('tim');
    if (from != null || to != null) parts.add('rentang tanggal');
    return parts.isEmpty ? 'Semua scan' : parts.join(' · ');
  }
}

/// Provider data untuk seluruh panel admin.
/// Semua query bergantung pada policy/RPC super admin di sisi Supabase —
/// kalau guard gagal, hasil kosong + error ditampilkan di UI.
class AdminProvider extends ChangeNotifier {
  static const int pageSize = 50;

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  // ── Stats ──
  AdminStats _stats = const AdminStats();
  bool _statsLoading = false;
  String? _statsError;

  AdminStats get stats => _stats;
  bool get statsLoading => _statsLoading;
  String? get statsError => _statsError;

  // ── Scans ──
  List<Map<String, dynamic>> _scans = [];
  bool _scansLoading = false;
  String? _scansError;
  bool _hasMoreScans = true;
  int _scanOffset = 0;
  ScanFilter _filter = const ScanFilter();

  List<Map<String, dynamic>> get scans => _scans;
  bool get scansLoading => _scansLoading;
  String? get scansError => _scansError;
  bool get hasMoreScans => _hasMoreScans;
  ScanFilter get filter => _filter;

  // ── Teams ──
  List<Map<String, dynamic>> _teams = [];

  List<Map<String, dynamic>> get teams => _teams;

  // ── Users (daftar user terdaftar) ──
  List<Map<String, dynamic>> _users = [];
  bool _usersLoading = false;
  String? _usersError;

  List<Map<String, dynamic>> get users => _users;
  bool get usersLoading => _usersLoading;
  String? get usersError => _usersError;

  // ── Approvals (pendaftar menunggu persetujuan) ──
  List<Map<String, dynamic>> _pendingApprovals = [];
  bool _approvalsLoading = false;
  String? _approvalsError;
  RealtimeChannel? _approvalsChannel;

  List<Map<String, dynamic>> get pendingApprovals => _pendingApprovals;
  bool get approvalsLoading => _approvalsLoading;
  String? get approvalsError => _approvalsError;
  int get pendingCount => _pendingApprovals.length;

  /// Mulai listen realtime pendaftar baru + notifikasi lokal.
  /// Dipanggil dari dashboard admin saat dibuka.
  void startApprovalWatcher() {
    _approvalsChannel ??= SupabaseService().subscribeNewApprovals(
      onNewSignup: (email) {
        NotificationService().showNewSignup(email: email);
        fetchPendingApprovals();
        fetchStats();
      },
    );
  }

  void stopApprovalWatcher() {
    _approvalsChannel?.unsubscribe();
    _approvalsChannel = null;
  }

  Future<void> fetchPendingApprovals() async {
    final client = _client;
    if (client == null) return;
    _approvalsLoading = true;
    _approvalsError = null;
    notifyListeners();
    try {
      final res = await SupabaseService().fetchPendingApprovals();
      _pendingApprovals = res;
    } catch (e) {
      AppLogger.info('AdminPanel', 'fetchPendingApprovals error: $e');
      _approvalsError = 'Gagal memuat daftar pendaftar.';
    } finally {
      _approvalsLoading = false;
      notifyListeners();
    }
  }

  /// Setujui / tolak pendaftar. action: 'approved' | 'rejected'.
  /// Return true jika sukses.
  Future<bool> decideApproval(String userId, String action, {String? note}) async {
    final ok = await SupabaseService().decideApproval(userId, action, note: note);
    if (ok) {
      _pendingApprovals.removeWhere((r) => r['user_id'] == userId);
      notifyListeners();
    }
    return ok;
  }

  Future<void> fetchStats() async {
    final client = _client;
    if (client == null) return;
    _statsLoading = true;
    _statsError = null;
    notifyListeners();
    try {
      final res = await client.rpc('admin_stats');
      _stats = AdminStats.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      AppLogger.info('AdminPanel', 'admin_stats error: $e');
      _statsError = 'Gagal memuat statistik. Pastikan SQL super admin sudah dijalankan.';
    } finally {
      _statsLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchTeams() async {
    final client = _client;
    if (client == null) return;
    try {
      final res = await client
          .from('teams')
          .select('id, name')
          .order('name', ascending: true);
      _teams = List<Map<String, dynamic>>.from(res);
      notifyListeners();
    } catch (e) {
      AppLogger.info('AdminPanel', 'fetch teams error: $e');
    }
  }

  /// Daftar user terdaftar dari RPC admin_list_users() — hanya super admin.
  Future<void> fetchUsers() async {
    final client = _client;
    if (client == null) return;
    _usersLoading = true;
    _usersError = null;
    notifyListeners();
    try {
      final res = await client.rpc('admin_list_users');
      _users = List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      AppLogger.info('AdminPanel', 'admin_list_users error: $e');
      _usersError = 'Gagal memuat daftar user.\nDetail: $e';
    } finally {
      _usersLoading = false;
      notifyListeners();
    }
  }

  /// Ganti filter dan muat ulang daftar dari awal.
  Future<void> applyFilter(ScanFilter filter) async {
    _filter = filter;
    _scans = [];
    _scanOffset = 0;
    _hasMoreScans = true;
    await loadMoreScans(reset: true);
  }

  Future<void> loadMoreScans({bool reset = false}) async {
    if (_scansLoading) return;
    final client = _client;
    if (client == null) return;
    _scansLoading = true;
    if (!reset) notifyListeners();
    try {
      // Filter harus dirangkai SEBELUM order()/range() (tipe builder beda).
      PostgrestFilterBuilder query = client.from('scans').select();
      final f = _filter;
      if (f.marketplace != null) query = query.eq('marketplace', f.marketplace!);
      if (f.teamId != null) query = query.eq('team_id', f.teamId!);
      if (f.from != null) {
        query = query.gte('scanned_at', f.from!.millisecondsSinceEpoch);
      }
      if (f.to != null) {
        query = query.lt('scanned_at', f.to!.millisecondsSinceEpoch);
      }
      final res =
          await query.order('scanned_at', ascending: false).range(_scanOffset, _scanOffset + pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(res);
      if (reset) _scans = [];
      _scans.addAll(rows);
      _scanOffset += rows.length;
      _hasMoreScans = rows.length >= pageSize;
      _scansError = null;
    } catch (e) {
      AppLogger.info('AdminPanel', 'fetch scans error: $e');
      _scansError = 'Gagal memuat scan. Pastikan SQL super admin sudah dijalankan.';
    } finally {
      _scansLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopApprovalWatcher();
    super.dispose();
  }
}
