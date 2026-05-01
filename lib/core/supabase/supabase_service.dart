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
    final user = currentUser;
    try {
      debugPrint('[Supabase] Inserting order: ${order.resi}');
      await client.from('orders').insert({
        'device_id': deviceId ?? 'unknown',
        'user_id': user?.id,
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

  /// Ambil semua orders dari user yang login (berdasarkan user_id)
  Future<List<Map<String, dynamic>>> fetchOrders() async {
    final client = _client;
    if (client == null) return [];
    final user = currentUser;
    if (user == null) return [];
    try {
      final response = await client
          .from('orders')
          .select()
          .eq('user_id', user.id)
          .order('scanned_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[Supabase] fetch orders error: $e');
      return [];
    }
  }

  /// Login dengan Google OAuth (browser redirect)
  /// Secara otomatis link ke akun yang ada jika email sama
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

  /// Manual link identity (Google) ke akun yang ada berdasarkan email
  /// Dipanggil setelah Google login berhasil
  Future<void> linkIdentityIfNeeded() async {
    final client = _client;
    if (client == null) return;
    final user = currentUser;
    if (user == null) return;
    if (user.email == null) return;

    // Cek apakah user sudah punya Google identity
    final hasGoogleIdentity = user.identities?.any((id) => id.provider == 'google') ?? false;
    if (hasGoogleIdentity) return; // sudah ter-link

    debugPrint('[Supabase] User ${user.email} tidak punya Google identity, mencoba manual link...');

    // Cari user lain dengan email yang sama yang punya Google identity
    try {
      // Ini perlu admin key atau server function, tapi untuk sekarang kita skip
      // Karena Supabase tidak menyediakan API public untuk ini
      // Solusi: gunakan server-side function atau enable automatic linking di dashboard
      debugPrint('[Supabase] Manual identity linking memerlukan server function');
    } catch (e) {
      debugPrint('[Supabase] Link identity error: $e');
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

  /// Cari team berdasarkan invite code (via SECURITY DEFINER untuk bypass RLS)
  Future<Team?> getTeamByInviteCode(String code) async {
    final client = _client;
    if (client == null) return null;
    try {
      final response = await client
          .rpc('get_team_by_invite_code', params: {'code': code.trim().toUpperCase()});
      if (response == null || (response as List).isEmpty) return null;
      return Team.fromMap(Map<String, dynamic>.from(response.first));
    } catch (e) {
      debugPrint('[Supabase] Get team by invite error: $e');
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

  /// Keluar dari tim (hapus diri dari team_members)
  Future<bool> leaveTeam() async {
    final client = _client;
    if (client == null) return false;
    final user = currentUser;
    if (user == null) return false;
    try {
      await client
          .from('team_members')
          .delete()
          .eq('user_id', user.id);
      return true;
    } catch (e) {
      debugPrint('[Supabase] Leave team error: $e');
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

  Future<Map<String, dynamic>?> fetchMySubscription() async {
    final client = _client;
    if (client == null) return null;
    final user = currentUser;
    if (user == null) return null;
    try {
      final res = await client
          .from('user_subscriptions')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      if (res == null) return null;
      return Map<String, dynamic>.from(res);
    } catch (e) {
      debugPrint('[Supabase] fetch subscription error: $e');
      return null;
    }
  }

  /// Fetch subscription berdasarkan email (untuk sync saat Google login)
  /// Menggunakan SECURITY DEFINER function untuk bypass RLS
  Future<Map<String, dynamic>?> fetchSubscriptionByEmail(String email) async {
    final client = _client;
    if (client == null) return null;
    try {
      final response = await client
          .rpc('get_subscription_by_email', params: {'lookup_email': email});
      if (response == null || (response as List).isEmpty) return null;
      return Map<String, dynamic>.from(response.first);
    } catch (e) {
      debugPrint('[Supabase] fetch subscription by email error: $e');
      return null;
    }
  }

  Future<void> upsertMySubscription(Map<String, dynamic> payload) async {
    final client = _client;
    if (client == null) return;
    final user = currentUser;
    if (user == null) return;
    try {
      await client.from('user_subscriptions').upsert({
        'user_id': user.id,
        'email': user.email,
        ...payload,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[Supabase] upsert subscription error: $e');
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

  // ── Category sync (Team tier) ──

  Future<void> upsertCategory(int id, String name, String color) async {
    final client = _client;
    if (client == null) return;
    final user = currentUser;
    if (user == null) return;
    try {
      await client.from('categories').upsert({
        'id': id,
        'user_id': user.id,
        'name': name,
        'color': color,
      });
    } catch (e) {
      debugPrint('[Supabase] upsert category error: $e');
    }
  }

  Future<void> deleteCategory(int categoryId) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.from('categories').delete().eq('id', categoryId);
    } catch (e) {
      debugPrint('[Supabase] delete category error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchCategories() async {
    final client = _client;
    if (client == null) return [];
    final user = currentUser;
    if (user == null) return [];
    try {
      final res = await client
          .from('categories')
          .select()
          .eq('user_id', user.id)
          .order('created_at');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('[Supabase] fetch categories error: $e');
      return [];
    }
  }

  Future<void> assignOrderCategory(int orderCategoryId, int orderId, int categoryId) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.from('order_categories').upsert({
        'id': orderCategoryId,
        'order_id': orderId,
        'category_id': categoryId,
      });
    } catch (e) {
      debugPrint('[Supabase] assign order category error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchOrderCategories() async {
    final client = _client;
    if (client == null) return [];
    final user = currentUser;
    if (user == null) return [];
    try {
      // Get category IDs for this user
      final catRes = await client
          .from('categories')
          .select('id')
          .eq('user_id', user.id);
      final catIds = catRes.map((c) => c['id'] as int).toList();
      if (catIds.isEmpty) return [];
      final res = await client
          .from('order_categories')
          .select()
          .inFilter('category_id', catIds);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('[Supabase] fetch order categories error: $e');
      return [];
    }
  }

  /// Fetch semua paket dari tabel packages (publik, tidak perlu login)
  Future<List<Map<String, dynamic>>> fetchPackages() async {
    final client = _client;
    if (client == null) return [];
    try {
      final res = await client
          .from('packages')
          .select()
          .order('sort_order', ascending: true);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('[Supabase] fetch packages error: $e');
      return [];
    }
  }
}
