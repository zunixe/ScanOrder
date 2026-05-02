import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/order.dart';
import '../../models/team.dart';
import '../db/database_helper.dart';

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

  String get url => _supabaseUrl;
  String get key => _supabaseKey;

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

  /// Download foto dari Supabase Storage ke lokal, return local path
  Future<String?> downloadPhoto(String cloudUrl, String localPath) async {
    try {
      final response = await Supabase.instance.client.storage.from('scan-photos').download(cloudUrl);
      final file = File(localPath);
      await file.create(recursive: true);
      await file.writeAsBytes(response);
      return localPath;
    } catch (e) {
      debugPrint('[Supabase] Download photo error: $e');
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
      await client.from('scans').insert({
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
          .from('scans')
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
          .from('scans')
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
      // Cek limit anggota (maks 10)
      final members = await client
          .from('team_members')
          .select('id')
          .eq('team_id', team.id);
      if (members.length >= 10) {
        debugPrint('[Supabase] Team already has 10 members, cannot join');
        return false;
      }
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

  /// Transfer admin role to another member
  Future<bool> transferAdmin(String teamId, String newAdminUserId) async {
    final client = _client;
    if (client == null) return false;
    final user = currentUser;
    if (user == null) return false;
    try {
      // Update team's created_by to new admin
      await client
          .from('teams')
          .update({'created_by': newAdminUserId})
          .eq('id', teamId);
      // Update new member's role to admin
      await client
          .from('team_members')
          .update({'role': 'admin'})
          .eq('team_id', teamId)
          .eq('user_id', newAdminUserId);
      // Remove old admin from team_members
      await client
          .from('team_members')
          .delete()
          .eq('user_id', user.id);
      return true;
    } catch (e) {
      debugPrint('[Supabase] Transfer admin error: $e');
      return false;
    }
  }

  /// Dissolve team (delete team and all members) — admin only, when alone
  Future<bool> dissolveTeam(String teamId) async {
    final client = _client;
    if (client == null) return false;
    try {
      // Delete all team members first
      await client
          .from('team_members')
          .delete()
          .eq('team_id', teamId);
      // Delete the team
      await client
          .from('teams')
          .delete()
          .eq('id', teamId);
      return true;
    } catch (e) {
      debugPrint('[Supabase] Dissolve team error: $e');
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
      await client.from('scans').insert(data);
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
          .from('scans')
          .select('*, scan_categories(categories(*))')
          .eq('team_id', teamId)
          .order('scanned_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  /// Get distinct dates that have team scans (for history date chips)
  Future<List<String>> getTeamDistinctDates(String teamId) async {
    final client = _client;
    if (client == null) { debugPrint('[Supabase] getTeamDistinctDates: no client'); return []; }
    try {
      final response = await client
          .from('scans')
          .select('date')
          .eq('team_id', teamId)
          .order('date', ascending: false);
      debugPrint('[Supabase] getTeamDistinctDates: teamId=$teamId, raw=${(response as List).length} rows');
      final seen = <String>{};
      final dates = <String>[];
      for (final row in response as List) {
        final date = row['date'] as String;
        if (seen.add(date)) dates.add(date);
      }
      debugPrint('[Supabase] getTeamDistinctDates: result=$dates');
      return dates;
    } catch (e) {
      debugPrint('[Supabase] getTeamDistinctDates error: $e');
      return [];
    }
  }

  /// Get team orders by date from Supabase
  Future<List<Map<String, dynamic>>> getTeamOrdersByDate(String teamId, String date) async {
    final client = _client;
    if (client == null) { debugPrint('[Supabase] getTeamOrdersByDate: no client'); return []; }
    try {
      final response = await client
          .from('scans')
          .select('*, scan_categories(categories(*))')
          .eq('team_id', teamId)
          .eq('date', date)
          .order('scanned_at', ascending: false);
      debugPrint('[Supabase] getTeamOrdersByDate: teamId=$teamId, date=$date, rows=${(response as List).length}');
      if ((response as List).isNotEmpty) debugPrint('[Supabase] getTeamOrdersByDate sample: ${response.first}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[Supabase] getTeamOrdersByDate error: $e');
      return [];
    }
  }

  /// Search team orders by resi from Supabase
  Future<List<Map<String, dynamic>>> searchTeamOrders(String teamId, String query) async {
    final client = _client;
    if (client == null) return [];
    try {
      final response = await client
          .from('scans')
          .select('*, scan_categories(categories(*))')
          .eq('team_id', teamId)
          .ilike('resi', '%$query%')
          .order('scanned_at', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[Supabase] searchTeamOrders error: $e');
      return [];
    }
  }

  /// Get total scan count for a team from Supabase
  Future<int> getTeamTotalScans(String teamId) async {
    final client = _client;
    if (client == null) { debugPrint('[Supabase] getTeamTotalScans: no client'); return 0; }
    try {
      final response = await client
          .from('scans')
          .select('id')
          .eq('team_id', teamId);
      final count = (response as List).length;
      debugPrint('[Supabase] getTeamTotalScans: teamId=$teamId, count=$count');
      return count;
    } catch (e) {
      debugPrint('[Supabase] getTeamTotalScans error: $e');
      return 0;
    }
  }

  /// Get scan count today for a team from Supabase
  Future<int> getTeamTodayScans(String teamId) async {
    final client = _client;
    if (client == null) { debugPrint('[Supabase] getTeamTodayScans: no client'); return 0; }
    try {
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final response = await client
          .from('scans')
          .select('id')
          .eq('team_id', teamId)
          .eq('date', dateStr);
      final count = (response as List).length;
      debugPrint('[Supabase] getTeamTodayScans: teamId=$teamId, date=$dateStr, count=$count');
      return count;
    } catch (e) {
      debugPrint('[Supabase] getTeamTodayScans error: $e');
      return 0;
    }
  }

  /// Get daily scan counts for a team (last N days) from Supabase
  Future<Map<String, int>> getTeamDailyStats(String teamId, int days) async {
    final client = _client;
    if (client == null) return {};
    try {
      final now = DateTime.now();
      final startDate = now.subtract(Duration(days: days - 1));
      final startStr = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
      final response = await client
          .from('scans')
          .select('date')
          .eq('team_id', teamId)
          .gte('date', startStr);
      final stats = <String, int>{};
      for (final row in response as List) {
        final date = row['date'] as String;
        stats[date] = (stats[date] ?? 0) + 1;
      }
      return stats;
    } catch (e) {
      debugPrint('[Supabase] getTeamDailyStats error: $e');
      return {};
    }
  }

  /// Get marketplace stats for a team from Supabase
  Future<Map<String, int>> getTeamMarketplaceStats(String teamId) async {
    final client = _client;
    if (client == null) return {};
    try {
      final response = await client
          .from('scans')
          .select('marketplace')
          .eq('team_id', teamId);
      final stats = <String, int>{};
      for (final row in response as List) {
        final mp = row['marketplace'] as String;
        stats[mp] = (stats[mp] ?? 0) + 1;
      }
      // Sort by count descending
      final sorted = Map.fromEntries(stats.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
      return sorted;
    } catch (e) {
      debugPrint('[Supabase] getTeamMarketplaceStats error: $e');
      return {};
    }
  }

  /// Get category stats for a team from Supabase (scan_categories join)
  Future<Map<String, int>> getTeamCategoryStats(String teamId) async {
    final client = _client;
    if (client == null) return {};
    try {
      // Fetch scan_categories joined with scans filtered by team_id
      final response = await client
          .from('scan_categories')
          .select('category_id, scans!inner(team_id), categories!inner(name)')
          .eq('scans.team_id', teamId);
      final stats = <String, int>{};
      for (final row in response as List) {
        final catName = (row['categories'] as Map)['name'] as String;
        stats[catName] = (stats[catName] ?? 0) + 1;
      }
      return stats;
    } catch (e) {
      debugPrint('[Supabase] getTeamCategoryStats error: $e');
      return {};
    }
  }

  /// Repair: re-sync all local scan_categories to Supabase
  /// Called on startup for team users to ensure scan_categories exist in Supabase
  Future<void> repairScanCategories() async {
    final client = _client;
    if (client == null) return;
    try {
      final localRows = await DatabaseHelper.instance.getAllScanCategoriesWithResi();
      if (localRows.isEmpty) {
        debugPrint('[Supabase] repairScanCategories: no local scan_categories to repair');
        return;
      }
      int synced = 0;
      int skipped = 0;
      for (final row in localRows) {
        final resi = row['resi'] as String;
        final catName = row['cat_name'] as String;
        final catUserId = row['cat_user_id'] as String?;
        if (catUserId == null) { skipped++; continue; }

        // Find Supabase scan id by resi
        final scanRows = await client.from('scans').select('id').eq('resi', resi).limit(1) as List<dynamic>;
        if (scanRows.isEmpty) { skipped++; continue; }
        final scanId = scanRows.first['id'];

        // Find Supabase category UUID by name + user_id
        final catRows = await client
            .from('categories')
            .select('id')
            .eq('user_id', catUserId)
            .eq('name', catName)
            .limit(1) as List<dynamic>;
        if (catRows.isEmpty) { skipped++; continue; }
        final catUuid = catRows.first['id'];

        // Upsert scan_categories
        await client.from('scan_categories').upsert({
          'scan_id': scanId,
          'category_id': catUuid,
        });
        synced++;
      }
      debugPrint('[Supabase] repairScanCategories: synced=$synced, skipped=$skipped, total=${localRows.length}');
    } catch (e) {
      debugPrint('[Supabase] repairScanCategories error: $e');
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

  /// Fetch categories created by team admin (for team members to use)
  /// Uses team membership to bypass RLS - fetches categories where user_id = team's created_by
  Future<List<Map<String, dynamic>>> fetchTeamCategories(String adminUserId) async {
    final client = _client;
    if (client == null) return [];
    try {
      // First try direct query (works if RLS policy allows)
      var res = await client
          .from('categories')
          .select()
          .eq('user_id', adminUserId)
          .order('created_at');
      if (res.isNotEmpty) {
        return List<Map<String, dynamic>>.from(res);
      }
      // Fallback: try fetching via RPC or alternative approach
      // If RLS blocks, the result will be empty - log warning
      debugPrint('[Supabase] fetchTeamCategories: no results for adminUserId=$adminUserId (RLS may block)');
      return [];
    } catch (e) {
      debugPrint('[Supabase] fetch team categories error: $e');
      return [];
    }
  }

  Future<void> assignOrderCategory(int orderCategoryId, int localOrderId, int categoryId) async {
    final client = _client;
    if (client == null) return;
    try {
      // Find the Supabase scan_id by looking up the local order's resi
      final order = await DatabaseHelper.instance.getOrderById(localOrderId);
      if (order == null) {
        debugPrint('[Supabase] assignOrderCategory: local order $localOrderId not found');
        return;
      }
      final resi = order.resi;
      final rows = await client.from('scans').select('id').eq('resi', resi).limit(1);
      final rowList = List<Map<String, dynamic>>.from(rows);
      if (rowList.isEmpty) {
        debugPrint('[Supabase] assignOrderCategory: scan not found in Supabase for resi=$resi');
        return;
      }
      final supabaseScanId = rowList.first['id'] as int;
      await client.from('scan_categories').upsert({
        'scan_id': supabaseScanId,
        'category_id': categoryId,
      });
      debugPrint('[Supabase] assignOrderCategory OK: resi=$resi, supabaseScanId=$supabaseScanId, categoryId=$categoryId');
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
          .from('scan_categories')
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
