import 'package:flutter/foundation.dart';
import '../../core/db/database_helper.dart';
import '../../core/supabase/supabase_service.dart';
import '../../models/order.dart';
import '../../models/team.dart';
import '../../models/category.dart';
import '../../services/quota_service.dart';

class AuthProvider extends ChangeNotifier {
  final _supabase = SupabaseService();
  final _db = DatabaseHelper.instance;
  bool _isLoggedIn = false;
  bool _isLoading = false;
  String? _error;

  // Team state
  Team? _currentTeam;
  List<TeamMember> _teamMembers = [];

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Team? get currentTeam => _currentTeam;
  List<TeamMember> get teamMembers => _teamMembers;
  bool get hasTeam => _currentTeam != null;
  bool get isAdmin => _currentTeam?.createdBy == _supabase.currentUser?.id;

  AuthProvider() {
    _checkAuth();
    if (!_supabase.isOffline) {
      _supabase.authStateChanges.listen((state) async {
        _isLoggedIn = state.session != null;
        if (_isLoggedIn) {
          notifyListeners();
          await _checkAdminPro();
          await _loadTeam();
          await syncOnLogin();
        } else {
          _currentTeam = null;
        }
        notifyListeners();
      });
    }
  }

  void _checkAuth() {
    _isLoggedIn = _supabase.currentUser != null;
    notifyListeners();
    if (_isLoggedIn) {
      _checkAdminPro();
      _loadTeam();
    }
  }

  Future<void> _checkAdminPro() async {
    // Admin tier bypass dihapus untuk release.
    // Gunakan Supabase dashboard atau server-side function untuk set tier admin.
  }

  Future<void> _loadTeam() async {
    try {
      _currentTeam = await _supabase.getMyTeam();
      if (_currentTeam != null) {
        final members = await _supabase.getTeamMembers(_currentTeam!.id);
        _teamMembers = members.map((m) => TeamMember.fromMap(m)).toList();
      } else {
        _teamMembers = [];
      }
    } catch (e) {
      debugPrint('Load team error: $e');
    } finally {
      notifyListeners();
    }
  }

  Future<void> createTeam(String name) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final team = await _supabase.createTeam(name);
      if (team != null) {
        _currentTeam = team;
      } else {
        _error = 'Gagal membuat team';
      }
    } catch (e) {
      _error = 'Error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> joinTeam(String inviteCode) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final ok = await _supabase.joinTeam(inviteCode);
      if (ok) {
        await _loadTeam();
      } else {
        _error = 'Kode invite tidak valid';
      }
    } catch (e) {
      _error = 'Error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> leaveTeam() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final ok = await _supabase.leaveTeam();
      if (ok) {
        _currentTeam = null;
      } else {
        _error = 'Gagal keluar dari tim';
      }
    } catch (e) {
      _error = 'Error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signUp(String email, String password, {StorageTier tier = StorageTier.free}) async {
    if (_supabase.isOffline) {
      _error = 'Tidak ada koneksi ke server. Pastikan internet aktif atau server Supabase tersedia.';
      notifyListeners();
      return;
    }
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final client = _supabase.client;
      if (client == null) {
        _error = 'Koneksi ke server belum tersedia. Coba lagi nanti.';
        return;
      }
      await client.auth.signUp(
        email: email,
        password: password,
      );
      _isLoggedIn = true;
      // Apply tier yang dipilih saat daftar
      if (tier != StorageTier.free) {
        await QuotaService().purchaseOrChangeTier(tier, carryOver: false);
        debugPrint('[AuthProvider] Tier $tier applied on signup for $email');
      }
    } catch (e) {
      _error = 'Signup gagal: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    if (_supabase.isOffline) {
      _error = 'Tidak ada koneksi ke server. Pastikan internet aktif atau server Supabase tersedia.';
      notifyListeners();
      return;
    }
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final client = _supabase.client;
      if (client == null) {
        _error = 'Koneksi ke server belum tersedia. Coba lagi nanti.';
        return;
      }
      await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      _isLoggedIn = true;
    } catch (e) {
      _error = 'Login gagal: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final ok = await _supabase.signInWithGoogle();
      if (!ok) {
        _error = 'Google login gagal. Pastikan Google provider diaktifkan di Supabase dan Client ID benar.';
      }
    } catch (e) {
      _error = 'Google login error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _supabase.signOut();
      await QuotaService().purchaseOrChangeTier(StorageTier.free, carryOver: false);
      _isLoggedIn = false;
      _currentTeam = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> syncOnLogin() async {
    try {
      final userId = _supabase.currentUser?.id;
      final teamId = _currentTeam?.id;
      final remote = teamId != null
          ? await _supabase.fetchTeamOrders(teamId)
          : await _supabase.fetchOrders();
      debugPrint('[AuthProvider] syncOnLogin: userId=$userId, teamId=$teamId, remoteOrders=${remote.length}');
      int synced = 0;
      for (final m in remote) {
        try {
          final o = ScannedOrder(
            resi: (m['resi'] ?? '') as String,
            marketplace: (m['marketplace'] ?? '') as String,
            scannedAt: m['scanned_at'] != null
                ? DateTime.fromMillisecondsSinceEpoch(m['scanned_at'] as int)
                : DateTime.now(),
            date: (m['date'] ?? DateTime.now().toIso8601String().substring(0, 10)) as String,
            photoPath: m['photo_url'] as String?,
          );
          final id = await _db.insertOrder(o, userId: userId);
          if (id > 0) {
            synced++;
          } else {
            debugPrint('[AuthProvider] syncOnLogin: insertOrder ignored (duplicate?) resi=${o.resi}');
          }
        } catch (e) {
          debugPrint('Sync row error: $e');
        }
      }
      debugPrint('[AuthProvider] syncOnLogin: synced=$synced orders');

      // Sync categories from cloud
      final remoteCats = await _supabase.fetchCategories();
      for (final c in remoteCats) {
        try {
          await _db.insertCategory(ScanCategory(
            id: c['id'] as int?,
            name: c['name'] as String,
            color: c['color'] as String,
            userId: c['user_id'] as String?,
            createdAt: c['created_at'] != null
                ? DateTime.parse(c['created_at'] as String)
                : DateTime.now(),
          ));
        } catch (e) {
          debugPrint('Sync category error: $e');
        }
      }

      // Sync order-category relations from cloud
      final remoteOC = await _supabase.fetchOrderCategories();
      for (final oc in remoteOC) {
        try {
          await _db.assignCategoryToOrder(
            oc['scan_id'] as int,
            oc['category_id'] as int,
          );
        } catch (e) {
          debugPrint('Sync order-category error: $e');
        }
      }
    } catch (e) {
      debugPrint('Sync error: $e');
    }
  }
}
