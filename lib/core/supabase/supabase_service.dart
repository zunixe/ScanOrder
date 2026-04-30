import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/order.dart';
import '../../models/team.dart';

/// Service untuk sinkronisasi data ke Supabase backend.
///
/// Setup:
/// 1. Buat project di https://supabase.com (gratis tier)
/// 2. Buat table `orders` dengan kolom: id, device_id, resi, marketplace, scanned_at, date, photo_url
/// 3. Copy Supabase URL dan anon key ke [supabaseUrl] dan [supabaseKey]
/// 4. Buka Storage di Supabase, buat bucket `scan-photos` (public)
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  // GANTI INI dengan URL dan key dari Supabase project Anda:
  static const String _supabaseUrl = 'https://rnithriviguzbfpvzrwq.supabase.co';
  static const String _supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJuaXRocml2aWd1emJmcHZ6cndxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc0NjQwNDksImV4cCI6MjA5MzA0MDA0OX0.3dMU23uT_9uEGHirs0PieViE7k1M_ezlCJ8wjryf2lc';

  bool _isOffline = false;
  bool get isOffline => _isOffline;

  bool get _isConfigured =>
      !_supabaseUrl.contains('YOUR_PROJECT') && !_supabaseKey.contains('YOUR_ANON_KEY');

  Future<void> initialize() async {
    if (!_isConfigured) {
      debugPrint('[Supabase] URL/key masih placeholder — skip');
      _isOffline = true;
      return;
    }
    // Cek network reachability dulu supaya tidak crash di HP dengan network bermasalah
    final reachable = await _checkReachability();
    if (!reachable) {
      debugPrint('[Supabase] Host tidak bisa di-reach — mode offline aktif');
      _isOffline = true;
      return;
    }
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseKey,
      );
      _isOffline = false;
      debugPrint('[Supabase] Initialized successfully');
    } catch (e) {
      debugPrint('[Supabase] Init error: $e');
      _isOffline = true;
    }
  }

  Future<bool> _checkReachability() async {
    try {
      final uri = Uri.parse(_supabaseUrl);
      final result = await InternetAddress.lookup(uri.host).timeout(const Duration(seconds: 5));
      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  SupabaseClient? get _client {
    if (_isOffline || !_isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Upload foto scan ke Supabase Storage, return public URL
  Future<String?> uploadPhoto(File file, String fileName) async {
    final client = _client;
    if (client == null) return null;
    try {
      await client.storage.from('scan-photos').upload(fileName, file);
      return client.storage.from('scan-photos').getPublicUrl(fileName);
    } catch (e) {
      return null;
    }
  }

  /// Kirim order yang baru di-scan ke Supabase
  Future<void> insertOrder(ScannedOrder order, {String? deviceId}) async {
    final client = _client;
    if (client == null) {
      debugPrint('[Supabase] Client not initialized');
      return;
    }
    try {
      debugPrint('[Supabase] Inserting order: ${order.resi}');
      await client.from('orders').insert({
        'device_id': deviceId ?? 'unknown',
        'resi': order.resi,
        'marketplace': order.marketplace,
        'scanned_at': order.scannedAt.millisecondsSinceEpoch,
        'date': order.date,
        'photo_url': order.photoPath,
      });
      debugPrint('[Supabase] Insert success: ${order.resi}');
    } catch (e, st) {
      debugPrint('[Supabase] Insert error: $e');
      debugPrint('[Supabase] Stack: $st');
    }
  }

  /// Hapus order dari Supabase berdasarkan resi + device_id
  Future<void> deleteOrderByResi(String resi, {String? deviceId}) async {
    final client = _client;
    if (client == null) return;
    try {
      debugPrint('[Supabase] Deleting order: $resi');
      await client
          .from('orders')
          .delete()
          .eq('resi', resi)
          .eq('device_id', deviceId ?? 'unknown');
      debugPrint('[Supabase] Delete success: $resi');
    } catch (e, st) {
      debugPrint('[Supabase] Delete error: $e');
      debugPrint('[Supabase] Stack: $st');
    }
  }

  /// Ambil semua orders dari user yang login (berdasarkan device_id)
  Future<List<Map<String, dynamic>>> fetchOrders({String? deviceId}) async {
    final client = _client;
    if (client == null) return [];
    try {
      var query = client.from('orders').select();
      if (deviceId != null) {
        query = query.eq('device_id', deviceId);
      }
      final response = await query.order('scanned_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Login dengan Google OAuth (browser redirect)
  Future<bool> signInWithGoogle() async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.scanorder.scanorder://login-callback/',
      );
      return true;
    } catch (e) {
      debugPrint('[Supabase] Google OAuth error: $e');
      return false;
    }
  }

  /// Logout
  Future<void> signOut() async {
    final client = _client;
    if (client == null) return;
    try {
      await client.auth.signOut();
    } catch (e) {
      debugPrint('[Supabase] Sign out error: $e');
    }
  }

  /// Cek user yang sedang login
  User? get currentUser {
    final client = _client;
    if (client == null) return null;
    try {
      return client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  // ---- Team Management ----

  /// Buat team baru untuk user yang login
  Future<Team?> createTeam(String name) async {
    final client = _client;
    if (client == null) return null;
    final user = currentUser;
    if (user == null) return null;
    try {
      final inviteCode = _generateInviteCode();
      final response = await client.from('teams').insert({
        'name': name,
        'invite_code': inviteCode,
        'created_by': user.id,
      }).select().single();
      final team = Team.fromMap(response);
      await client.from('team_members').insert({
        'team_id': team.id,
        'user_id': user.id,
        'role': 'admin',
        'email': user.email,
      });
      debugPrint('[Supabase] Team created: ${team.id}');
      return team;
    } catch (e, st) {
      debugPrint('[Supabase] Create team error: $e');
      debugPrint('[Supabase] Stack: $st');
      return null;
    }
  }

  /// Cari team berdasarkan invite code
  Future<Team?> getTeamByInviteCode(String code) async {
    final client = _client;
    if (client == null) return null;
    try {
      final response = await client
          .from('teams')
          .select()
          .eq('invite_code', code.trim())
          .maybeSingle();
      if (response == null) return null;
      return Team.fromMap(response);
    } catch (e) {
      debugPrint('[Supabase] Get team error: $e');
      return null;
    }
  }

  /// Bergabung ke team dengan invite code
  Future<bool> joinTeam(String inviteCode) async {
    final client = _client;
    if (client == null) return false;
    final user = currentUser;
    if (user == null) return false;
    try {
      final team = await getTeamByInviteCode(inviteCode);
      if (team == null) return false;
      // Cek apakah sudah member
      final existing = await client
          .from('team_members')
          .select()
          .eq('team_id', team.id)
          .eq('user_id', user.id)
          .maybeSingle();
      if (existing != null) return true; // sudah member
      await client.from('team_members').insert({
        'team_id': team.id,
        'user_id': user.id,
        'role': 'member',
        'email': user.email,
      });
      debugPrint('[Supabase] Joined team: ${team.id}');
      return true;
    } catch (e, st) {
      debugPrint('[Supabase] Join team error: $e');
      debugPrint('[Supabase] Stack: $st');
      return false;
    }
  }

  /// Ambil team yang user ikuti
  Future<Team?> getMyTeam() async {
    final client = _client;
    if (client == null) return null;
    final user = currentUser;
    if (user == null) return null;
    try {
      final member = await client
          .from('team_members')
          .select()
          .eq('user_id', user.id)
          .order('joined_at', ascending: true)
          .maybeSingle();
      if (member == null) return null;
      final response = await client
          .from('teams')
          .select()
          .eq('id', member['team_id'])
          .single();
      return Team.fromMap(response);
    } catch (e) {
      debugPrint('[Supabase] Get my team error: $e');
      return null;
    }
  }

  /// Ambil semua anggota team
  Future<List<Map<String, dynamic>>> getTeamMembers(String teamId) async {
    final client = _client;
    if (client == null) return [];
    try {
      final response = await client
          .from('team_members')
          .select()
          .eq('team_id', teamId)
          .order('joined_at');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Update order methods to use team_id
  Future<void> insertOrderWithTeam(ScannedOrder order, {String? deviceId, String? teamId}) async {
    final client = _client;
    if (client == null) {
      debugPrint('[Supabase] Client not initialized');
      return;
    }
    final user = currentUser;
    try {
      debugPrint('[Supabase] Inserting order: ${order.resi}');
      final data = {
        'device_id': deviceId ?? 'unknown',
        'resi': order.resi,
        'marketplace': order.marketplace,
        'scanned_at': order.scannedAt.millisecondsSinceEpoch,
        'date': order.date,
        'photo_url': order.photoPath,
        'user_id': user?.id,
      };
      if (teamId != null) data['team_id'] = teamId;
      await client.from('orders').insert(data);
      debugPrint('[Supabase] Insert success: ${order.resi}');
    } catch (e, st) {
      debugPrint('[Supabase] Insert error: $e');
      debugPrint('[Supabase] Stack: $st');
    }
  }

  Future<List<Map<String, dynamic>>> fetchTeamOrders(String teamId) async {
    final client = _client;
    if (client == null) return [];
    try {
      final response = await client
          .from('orders')
          .select()
          .eq('team_id', teamId)
          .order('scanned_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final now = DateTime.now().millisecondsSinceEpoch;
    var code = '';
    var n = now % 1000000;
    for (var i = 0; i < 6; i++) {
      code += chars[(n + i * 7) % chars.length];
    }
    return code;
  }

  /// Stream auth state changes
  SupabaseClient? get client => _client;

  Stream<AuthState> get authStateChanges {
    final client = _client;
    if (client == null) return const Stream.empty();
    return client.auth.onAuthStateChange;
  }
}
