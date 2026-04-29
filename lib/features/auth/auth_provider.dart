import 'package:flutter/foundation.dart';
import '../../core/db/database_helper.dart';
import '../../core/supabase/supabase_service.dart';
import '../../models/order.dart';
import '../../models/team.dart';

class AuthProvider extends ChangeNotifier {
  final _supabase = SupabaseService();
  final _db = DatabaseHelper.instance;
  bool _isLoggedIn = false;
  bool _isLoading = false;
  String? _error;

  // Team state
  Team? _currentTeam;
  bool _teamLoading = false;

  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Team? get currentTeam => _currentTeam;
  bool get hasTeam => _currentTeam != null;
  bool get isAdmin => _currentTeam?.createdBy == _supabase.currentUser?.id;

  AuthProvider() {
    _checkAuth();
    _supabase.authStateChanges.listen((state) {
      _isLoggedIn = state.session != null;
      if (_isLoggedIn) {
        _loadTeam();
        syncOnLogin();
      } else {
        _currentTeam = null;
      }
      notifyListeners();
    });
  }

  void _checkAuth() {
    _isLoggedIn = _supabase.currentUser != null;
    if (_isLoggedIn) _loadTeam();
    notifyListeners();
  }

  Future<void> _loadTeam() async {
    _teamLoading = true;
    notifyListeners();
    try {
      _currentTeam = await _supabase.getMyTeam();
    } catch (e) {
      debugPrint('Load team error: $e');
    } finally {
      _teamLoading = false;
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

  Future<void> signUp(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _supabase.client!.auth.signUp(
        email: email,
        password: password,
      );
      _isLoggedIn = true;
    } catch (e) {
      _error = 'Signup gagal: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _supabase.client!.auth.signInWithPassword(
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
      final teamId = _currentTeam?.id;
      final remote = teamId != null
          ? await _supabase.fetchTeamOrders(teamId)
          : await _supabase.fetchOrders();
      for (final m in remote) {
        final o = ScannedOrder(
          resi: m['resi'] as String,
          marketplace: m['marketplace'] as String,
          scannedAt: DateTime.fromMillisecondsSinceEpoch(m['scanned_at'] as int),
          date: m['date'] as String,
          photoPath: m['photo_url'] as String?,
        );
        try { await _db.insertOrder(o); } catch (_) {}
      }
    } catch (e) {
      debugPrint('Sync error: $e');
    }
  }
}
