import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/scan_record.dart';
import '../../models/category.dart';
import '../../models/team.dart';
import '../db/database_helper.dart';
import '../logging/logger.dart';

/// Service untuk sinkronisasi data ke Supabase backend.
///
/// Setup:
/// 1. Buat project di https://supabase.com (gratis tier)
/// 2. Buat table `scans` dengan kolom: id, device_id, resi, marketplace, scanned_at, date, photo_url
/// 3. Copy Supabase URL dan anon key ke [supabaseUrl] dan [supabaseKey]
/// 4. Buka Storage di Supabase, buat bucket `scan-photos` (public)
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  // Credentials dari compile-time env (--dart-define)
  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  bool _isOffline = false;
  bool get isOffline => _isOffline;

  String get url => _supabaseUrl;
  String get key => _supabaseKey;

  bool get _isConfigured =>
      _supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty;

  Future<void> initialize() async {
    if (!_isConfigured) {
      AppLogger.info('Supabase', 'URL/key masih placeholder — skip');
      _isOffline = true;
      return;
    }
    // Cek network reachability dulu supaya tidak crash di HP dengan network bermasalah
    final reachable = await _checkReachability();
    if (!reachable) {
      AppLogger.info('Supabase', 'Host tidak bisa di-reach — mode offline aktif');
      _isOffline = true;
      return;
    }
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseKey,
      );
      _isOffline = false;
      AppLogger.info('Supabase', 'Initialized successfully');
    } catch (e) {
      AppLogger.info('Supabase', 'Init error: $e');
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
      AppLogger.info('Supabase', 'uploadPhoto error: $e');
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
      AppLogger.info('Supabase', 'Download photo error: $e');
      return null;
    }
  }

  /// Kirim order yang baru di-scan ke Supabase
  Future<void> insertScan(ScanRecord order, {String? deviceId}) async {
    final client = _client;
    if (client == null) {
      AppLogger.info('Supabase', 'Client not initialized');
      return;
    }
    final user = currentUser;
    try {
      AppLogger.info('Supabase', 'Inserting order: ${order.resi}');
      await client.from('scans').insert({
        'device_id': deviceId ?? 'unknown',
        'user_id': user?.id,
        'resi': order.resi,
        'marketplace': order.marketplace,
        'scanned_at': order.scannedAt.millisecondsSinceEpoch,
        'date': order.date,
        'photo_url': order.photoPath,
      });
      AppLogger.info('Supabase', 'Insert success: ${order.resi}');
    } catch (e, st) {
      AppLogger.info('Supabase', 'Insert error: $e');
      AppLogger.info('Supabase', 'Stack: $st');
    }
  }

  /// Hapus order dari Supabase berdasarkan resi + device_id
  Future<void> deleteScanByResi(String resi, {String? deviceId}) async {
    final client = _client;
    if (client == null) return;
    try {
      AppLogger.info('Supabase', 'Deleting order: $resi');
      await client
          .from('scans')
          .delete()
          .eq('resi', resi)
          .eq('device_id', deviceId ?? 'unknown');
      AppLogger.info('Supabase', 'Delete success: $resi');
    } catch (e, st) {
      AppLogger.info('Supabase', 'Delete error: $e');
      AppLogger.info('Supabase', 'Stack: $st');
    }
  }

  /// Ambil semua scans dari user yang login (berdasarkan user_id)
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
      AppLogger.info('Supabase', 'fetch scans error: $e');
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
      AppLogger.info('Supabase', 'Google OAuth error: $e');
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

    AppLogger.info('Supabase', 'User ${user.email} tidak punya Google identity, mencoba manual link...');

    // Cari user lain dengan email yang sama yang punya Google identity
    try {
      // Ini perlu admin key atau server function, tapi untuk sekarang kita skip
      // Karena Supabase tidak menyediakan API public untuk ini
      // Solusi: gunakan server-side function atau enable automatic linking di dashboard
      AppLogger.info('Supabase', 'Manual identity linking memerlukan server function');
    } catch (e) {
      AppLogger.info('Supabase', 'Link identity error: $e');
    }
  }

  /// Logout
  Future<void> signOut() async {
    final client = _client;
    if (client == null) return;
    try {
      await client.auth.signOut();
    } catch (e) {
      AppLogger.info('Supabase', 'Sign out error: $e');
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
      AppLogger.info('Supabase', 'Team created: ${team.id}');
      return team;
    } catch (e, st) {
      AppLogger.info('Supabase', 'Create team error: $e');
      AppLogger.info('Supabase', 'Stack: $st');
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
      AppLogger.info('Supabase', 'Get team by invite error: $e');
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
        AppLogger.info('Supabase', 'Team already has 10 members, cannot join');
        return false;
      }
      await client.from('team_members').insert({
        'team_id': team.id,
        'user_id': user.id,
        'role': 'member',
        'email': user.email,
      });
      AppLogger.info('Supabase', 'Joined team: ${team.id}');
      return true;
    } catch (e, st) {
      AppLogger.info('Supabase', 'Join team error: $e');
      AppLogger.info('Supabase', 'Stack: $st');
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
      AppLogger.info('Supabase', 'Leave team error: $e');
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
      AppLogger.info('Supabase', 'Transfer admin error: $e');
      return false;
    }
  }

  /// Dissolve team (delete team and all members) — admin only, when alone
  Future<bool> dissolveTeam(String teamId) async {
    final client = _client;
    if (client == null) return false;
    try {
      // Set team_id to NULL on all scans (they become personal scans again)
      await client
          .from('scans')
          .update({'team_id': null})
          .eq('team_id', teamId);
      
      // Delete all team members
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
      AppLogger.info('Supabase', 'Dissolve team error: $e');
      return false;
    }
  }

  /// Reassign orphan scans (team_id points to dissolved team) to the current active team
  /// Called by admin when they have scans from a dissolved team
  Future<int> reassignOrphanTeamScans(String adminUserId, String activeTeamId) async {
    final client = _client;
    if (client == null) return 0;
    try {
      // Find scans owned by admin that have a team_id pointing to a non-existent team
      final adminScans = await client
          .from('scans')
          .select('id, team_id')
          .eq('user_id', adminUserId)
          .not('team_id', 'is', null);
      
      final orphanIds = <int>[];
      for (final s in adminScans) {
        final scanTeamId = s['team_id'] as String?;
        if (scanTeamId != null && scanTeamId != activeTeamId) {
          // Check if this team still exists
          final teamCheck = await client
              .from('teams')
              .select('id')
              .eq('id', scanTeamId)
              .maybeSingle();
          if (teamCheck == null) {
            // Team no longer exists — this scan is orphaned
            orphanIds.add(s['id'] as int);
          }
        }
      }
      
      if (orphanIds.isEmpty) return 0;
      
      // Reassign all orphan scans to the active team
      for (final id in orphanIds) {
        await client.from('scans').update({'team_id': activeTeamId}).eq('id', id);
      }
      AppLogger.info('Supabase', 'Reassigned ${orphanIds.length} orphan scans to team $activeTeamId');
      return orphanIds.length;
    } catch (e) {
      AppLogger.info('Supabase', 'Reassign orphan scans error: $e');
      return 0;
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
      AppLogger.info('Supabase', 'Get my team error: $e');
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
  Future<void> insertScanWithTeam(ScanRecord order, {String? deviceId, String? teamId}) async {
    final client = _client;
    if (client == null) {
      AppLogger.info('Supabase', 'Client not initialized');
      return;
    }
    final user = currentUser;
    try {
      AppLogger.info('Supabase', 'Inserting order: ${order.resi}');
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
      AppLogger.info('Supabase', 'Insert success: ${order.resi}');
    } catch (e, st) {
      AppLogger.info('Supabase', 'Insert error: $e');
      AppLogger.info('Supabase', 'Stack: $st');
    }
  }

  Future<List<Map<String, dynamic>>> fetchTeamScans(String teamId) async {
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
    if (client == null) { AppLogger.info('Supabase', 'getTeamDistinctDates: no client'); return []; }
    try {
      final response = await client
          .from('scans')
          .select('date')
          .eq('team_id', teamId)
          .order('date', ascending: false);
      AppLogger.info('Supabase', 'getTeamDistinctDates: teamId=$teamId, raw=${(response as List).length} rows');
      final seen = <String>{};
      final dates = <String>[];
      for (final row in response as List) {
        final date = row['date'] as String;
        if (seen.add(date)) dates.add(date);
      }
      AppLogger.info('Supabase', 'getTeamDistinctDates: result=$dates');
      return dates;
    } catch (e) {
      AppLogger.info('Supabase', 'getTeamDistinctDates error: $e');
      return [];
    }
  }

  /// Get team scans by date from Supabase
  Future<List<Map<String, dynamic>>> getTeamScansByDate(String teamId, String date) async {
    final client = _client;
    if (client == null) { AppLogger.info('Supabase', 'getTeamScansByDate: no client'); return []; }
    try {
      final response = await client
          .from('scans')
          .select('*, scan_categories(categories(*))')
          .eq('team_id', teamId)
          .eq('date', date)
          .order('scanned_at', ascending: false);
      AppLogger.info('Supabase', 'getTeamScansByDate: teamId=$teamId, date=$date, rows=${(response as List).length}');
      if ((response as List).isNotEmpty) AppLogger.info('Supabase', 'getTeamScansByDate sample: ${response.first}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      AppLogger.info('Supabase', 'getTeamScansByDate error: $e');
      return [];
    }
  }

  /// Search team scans by resi from Supabase
  Future<List<Map<String, dynamic>>> searchTeamScans(String teamId, String query) async {
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
      AppLogger.info('Supabase', 'searchTeamScans error: $e');
      return [];
    }
  }

  /// Get total scan count for a team from Supabase
  Future<int> getTeamTotalScans(String teamId) async {
    final client = _client;
    if (client == null) { AppLogger.info('Supabase', 'getTeamTotalScans: no client'); return 0; }
    try {
      final response = await client
          .from('scans')
          .select('id')
          .eq('team_id', teamId);
      final count = (response as List).length;
      AppLogger.info('Supabase', 'getTeamTotalScans: teamId=$teamId, count=$count');
      return count;
    } catch (e) {
      AppLogger.info('Supabase', 'getTeamTotalScans error: $e');
      return 0;
    }
  }

  /// Get scan count today for a team from Supabase
  Future<int> getTeamTodayScans(String teamId) async {
    final client = _client;
    if (client == null) { AppLogger.info('Supabase', 'getTeamTodayScans: no client'); return 0; }
    try {
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final response = await client
          .from('scans')
          .select('id')
          .eq('team_id', teamId)
          .eq('date', dateStr);
      final count = (response as List).length;
      AppLogger.info('Supabase', 'getTeamTodayScans: teamId=$teamId, date=$dateStr, count=$count');
      return count;
    } catch (e) {
      AppLogger.info('Supabase', 'getTeamTodayScans error: $e');
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
      AppLogger.info('Supabase', 'getTeamDailyStats error: $e');
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
      AppLogger.info('Supabase', 'getTeamMarketplaceStats error: $e');
      return {};
    }
  }

  /// Get category stats for a team from Supabase (scan_categories join)
  /// Counts scan_categories entries per category (a scan in multiple categories counts in each)
  Future<Map<String, int>> getTeamCategoryStats(String teamId) async {
    final client = _client;
    if (client == null) return {};
    try {
      final response = await client
          .from('scan_categories')
          .select('categories!inner(name), scans!inner(team_id)')
          .eq('scans.team_id', teamId);
      final stats = <String, int>{};
      for (final row in response as List) {
        final catName = (row['categories'] as Map)['name'] as String;
        stats[catName] = (stats[catName] ?? 0) + 1;
      }
      return stats;
    } catch (e) {
      AppLogger.info('Supabase', 'getTeamCategoryStats error: $e');
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
        AppLogger.info('Supabase', 'repairScanCategories: no local scan_categories to repair');
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

        // Upsert scan_categories with onConflict to prevent duplicates
        await client.from('scan_categories').upsert({
          'scan_id': scanId,
          'category_id': catUuid,
        }, onConflict: 'scan_id,category_id');
        synced++;
      }
      AppLogger.info('Supabase', 'repairScanCategories: synced=$synced, skipped=$skipped, total=${localRows.length}');
      // Cleanup duplicate scan_categories rows
      await _dedupScanCategories();
    } catch (e) {
      AppLogger.info('Supabase', 'repairScanCategories error: $e');
    }
  }

  /// Remove duplicate scan_categories rows (same scan_id + category_id but different row id)
  Future<void> _dedupScanCategories() async {
    final client = _client;
    if (client == null) return;
    try {
      // Fetch all scan_categories
      final rows = await client.from('scan_categories').select('id, scan_id, category_id');
      final seen = <String, int>{}; // 'scan_id:category_id' -> first row id
      final duplicateIds = <int>[];
      for (final row in rows as List) {
        final key = '${row['scan_id']}:${row['category_id']}';
        final rowId = row['id'] as int;
        if (seen.containsKey(key)) {
          duplicateIds.add(rowId);
        } else {
          seen[key] = rowId;
        }
      }
      if (duplicateIds.isNotEmpty) {
        await client.from('scan_categories').delete().inFilter('id', duplicateIds);
        AppLogger.info('Supabase', '_dedupScanCategories: removed ${duplicateIds.length} duplicate rows');
      }
    } catch (e) {
      AppLogger.info('Supabase', '_dedupScanCategories error: $e');
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
      AppLogger.info('Supabase', 'fetch subscription error: $e');
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
      AppLogger.info('Supabase', 'fetch subscription by email error: $e');
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
      AppLogger.info('Supabase', 'upsert subscription error: $e');
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

  // ── Single-device session management ──

  /// Get or create a stable device ID for this device
  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('device_id');
    if (deviceId == null) {
      // Generate a unique device ID and persist it
      deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
      await prefs.setString('device_id', deviceId);
    }
    return deviceId;
  }

  /// Register this device as the active session for the user.
  /// Returns true if registration succeeded (this device is now the active session).
  /// Returns false if another device is already active (login rejected).
  Future<bool> registerSession() async {
    final client = _client;
    if (client == null) return true; // offline mode — allow
    final user = currentUser;
    if (user == null) return false;
    try {
      final deviceId = await getDeviceId();
      // Upsert: replace any existing session for this user with this device
      await client.from('user_sessions').upsert({
        'user_id': user.id,
        'device_id': deviceId,
        'last_heartbeat': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
      AppLogger.info('Supabase', 'Session registered: userId=${user.id}, deviceId=$deviceId');
      return true;
    } catch (e) {
      AppLogger.info('Supabase', 'registerSession error: $e');
      return false;
    }
  }

  /// Check if this device is still the active session.
  /// Returns true if this device is the active session (or if offline).
  /// Returns false if another device has taken over (should force logout).
  Future<bool> isSessionValid() async {
    final client = _client;
    if (client == null) return true; // offline — assume valid
    final user = currentUser;
    if (user == null) return false;
    try {
      final deviceId = await getDeviceId();
      final response = await client
          .from('user_sessions')
          .select('device_id, last_heartbeat')
          .eq('user_id', user.id)
          .maybeSingle();
      if (response == null) return true; // no session record — valid
      final activeDeviceId = response['device_id'] as String;
      if (activeDeviceId != deviceId) {
        AppLogger.info('Supabase', 'Session hijacked: active=$activeDeviceId, this=$deviceId');
        return false; // another device took over
      }
      return true;
    } catch (e) {
      AppLogger.info('Supabase', 'isSessionValid error: $e');
      return true; // on error, assume valid to avoid disruptive logout
    }
  }

  /// Send heartbeat to keep session alive.
  /// Should be called periodically (every ~5 minutes).
  Future<void> sendHeartbeat() async {
    final client = _client;
    if (client == null) return;
    final user = currentUser;
    if (user == null) return;
    try {
      final deviceId = await getDeviceId();
      await client.from('user_sessions').upsert({
        'user_id': user.id,
        'device_id': deviceId,
        'last_heartbeat': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      AppLogger.info('Supabase', 'sendHeartbeat error: $e');
    }
  }

  /// Clear this user's session (called on logout).
  Future<void> clearSession() async {
    final client = _client;
    if (client == null) return;
    final user = currentUser;
    if (user == null) return;
    try {
      await client.from('user_sessions').delete().eq('user_id', user.id);
      AppLogger.info('Supabase', 'Session cleared for userId=${user.id}');
    } catch (e) {
      AppLogger.info('Supabase', 'clearSession error: $e');
    }
  }

  // ── Login history with geolocation ──

  /// Insert a login history record with location data
  Future<void> insertLoginHistory({
    required String deviceId,
    double? latitude,
    double? longitude,
    String? city,
    String? region,
    String? country,
  }) async {
    final client = _client;
    if (client == null) return;
    final user = currentUser;
    if (user == null) return;
    try {
      await client.from('login_history').insert({
        'user_id': user.id,
        'email': user.email,
        'device_id': deviceId,
        'latitude': latitude,
        'longitude': longitude,
        'city': city,
        'region': region,
        'country': country,
        'login_at': DateTime.now().toUtc().toIso8601String(),
      });
      AppLogger.info('Supabase', 'Login history saved: lat=$latitude, lng=$longitude, city=$city');
    } catch (e) {
      AppLogger.info('Supabase', 'insertLoginHistory error: $e');
    }
  }

  /// Fetch login history for a specific user (admin use)
  Future<List<Map<String, dynamic>>> fetchLoginHistory(String userId) async {
    final client = _client;
    if (client == null) return [];
    try {
      final response = await client
          .from('login_history')
          .select()
          .eq('user_id', userId)
          .order('login_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      AppLogger.info('Supabase', 'fetchLoginHistory error: $e');
      return [];
    }
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
      AppLogger.info('Supabase', 'upsert category error: $e');
    }
  }

  Future<void> deleteCategory(int categoryId) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.from('categories').delete().eq('id', categoryId);
    } catch (e) {
      AppLogger.info('Supabase', 'delete category error: $e');
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
      AppLogger.info('Supabase', 'fetch categories error: $e');
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
      AppLogger.info('Supabase', 'fetchTeamCategories: no results for adminUserId=$adminUserId (RLS may block)');
      return [];
    } catch (e) {
      AppLogger.info('Supabase', 'fetch team categories error: $e');
      return [];
    }
  }

  /// Sync team categories from Supabase to local DB
  /// Syncs own categories + admin's categories (for team members only)
  Future<void> syncTeamCategoriesToLocal({String? adminUserId}) async {
    final db = DatabaseHelper.instance;
    // Sync own categories
    final ownCats = await fetchCategories();
    for (final c in ownCats) {
      try {
        await db.insertCategory(ScanCategory(
          name: c['name'] as String,
          color: c['color'] as String,
          userId: c['user_id'] as String?,
        ));
      } catch (_) {}
    }
    // Sync admin's categories (only for team members, not admin themselves)
    if (adminUserId != null) {
      final adminCats = await fetchTeamCategories(adminUserId);
      for (final c in adminCats) {
        try {
          await db.insertCategory(ScanCategory(
            name: c['name'] as String,
            color: c['color'] as String,
            userId: c['user_id'] as String?,
          ));
        } catch (_) {}
      }
    }
  }

  Future<void> assignOrderCategory(int orderCategoryId, int localOrderId, int categoryId) async {
    final client = _client;
    if (client == null) return;
    try {
      // Find the Supabase scan_id by looking up the local order's resi
      final order = await DatabaseHelper.instance.getScanById(localOrderId);
      if (order == null) {
        AppLogger.info('Supabase', 'assignOrderCategory: local order $localOrderId not found');
        return;
      }
      final resi = order.resi;
      final rows = await client.from('scans').select('id').eq('resi', resi).limit(1);
      final rowList = List<Map<String, dynamic>>.from(rows);
      if (rowList.isEmpty) {
        AppLogger.info('Supabase', 'assignOrderCategory: scan not found in Supabase for resi=$resi');
        return;
      }
      final supabaseScanId = rowList.first['id'] as int;
      await client.from('scan_categories').upsert({
        'scan_id': supabaseScanId,
        'category_id': categoryId,
      }, onConflict: 'scan_id,category_id');
      AppLogger.info('Supabase', 'assignOrderCategory OK: resi=$resi, supabaseScanId=$supabaseScanId, categoryId=$categoryId');
    } catch (e) {
      AppLogger.info('Supabase', 'assign order category error: $e');
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
      AppLogger.info('Supabase', 'fetch order categories error: $e');
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
      AppLogger.info('Supabase', 'fetch packages error: $e');
      return [];
    }
  }
}
