import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../core/db/database_helper.dart';
import '../../core/supabase/supabase_service.dart';
import '../../models/order.dart';
import '../../models/team.dart';
import '../../services/sync_queue.dart';

class StatsProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final SyncQueue _syncQueue = SyncQueue();

  Map<String, int> dailyStats = {};
  Map<String, int> marketplaceStats = {};
  Map<String, int> categoryStats = {};
  int totalScans = 0;
  int periodDays = 7;

  // Storage stats
  int dbSizeBytes = 0;
  int photoSizeBytes = 0;
  int photoCount = 0;

  // Cloud storage stats
  int cloudDbSizeBytes = 0;
  int cloudPhotoSizeBytes = 0;

  // Sync stats
  int syncedScans = 0;
  int unsyncedScans = 0;
  int syncedPhotos = 0;
  int unsyncedPhotos = 0;
  int pendingQueueCount = 0;

  // Category sync stats
  int syncedCategories = 0;
  int unsyncedCategories = 0;

  // Unsynced photo resi list
  List<String> unsyncedPhotoResis = [];

  // Team stats
  Map<String, int> memberScanStats = {}; // email -> scan count
  List<TeamMember> teamMembers = [];

  String? _teamId;
  String? _adminUserId;

  void setTeamContext(String? teamId, String? adminUserId) {
    _teamId = teamId;
    _adminUserId = adminUserId;
  }

  Future<void> loadStats() async {
    final supabase = SupabaseService();
    final userId = supabase.currentUser?.id;
    final teamId = _teamId;

    if (teamId != null) {
      // Team mode: query Supabase for real-time cross-device team stats
      dailyStats = await supabase.getTeamDailyStats(teamId, periodDays);
      marketplaceStats = await supabase.getTeamMarketplaceStats(teamId);
      totalScans = await supabase.getTeamTotalScans(teamId);
      categoryStats = await supabase.getTeamCategoryStats(teamId);
    } else {
      // Personal mode: query local DB
      dailyStats = await _db.getDailyStats(periodDays, userId: userId);
      marketplaceStats = await _db.getMarketplaceStats(userId: userId);
      totalScans = await _db.getTotalOrderCount(userId: userId);
      categoryStats = await _db.getCategoryStats(userId: userId);
    }
    await _loadStorageStats();
    await _loadSyncStats(userId: userId, teamId: teamId);
    await _loadCategorySyncStats(userId: userId, teamId: teamId);
    await _loadTeamStats();
    notifyListeners();
  }

  Future<void> _loadStorageStats() async {
    try {
      dbSizeBytes = 0;
      photoSizeBytes = 0;
      photoCount = 0;

      final userId = SupabaseService().currentUser?.id;
      final teamId = _teamId;

      // Database size (always full DB, but we'll proportion it later)
      final dbPath = await getDatabasesPath();
      final dbFile = File(join(dbPath, 'scanorder.db'));
      if (await dbFile.exists()) {
        if (teamId != null) {
          // Team mode: full DB size
          dbSizeBytes = await dbFile.length();
        } else {
          // Personal mode: proportion DB size by personal scan count vs total
          final totalScansCount = await _db.getTotalOrderCount();
          final personalScansCount = userId != null ? await _db.getTotalOrderCount(userId: userId) : 0;
          final fullDbSize = await dbFile.length();
          if (totalScansCount > 0) {
            dbSizeBytes = (fullDbSize * personalScansCount) ~/ totalScansCount;
          } else {
            dbSizeBytes = fullDbSize;
          }
        }
      }

      // Photos size: only count photos belonging to user's own scans
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory(docsDir.path);
      if (await dir.exists()) {
        // Get list of photo paths from personal scans
        final personalOrders = userId != null
            ? await _db.getAllOrders(userId: userId)
            : <ScannedOrder>[];
        final personalPhotoPaths = personalOrders
            .where((o) => o.photoPath != null && !o.photoPath!.startsWith('http'))
            .map((o) => o.photoPath!)
            .toSet();

        await for (final entity in dir.list()) {
          if (entity is File && entity.path.contains('scan_') && entity.path.endsWith('.jpg')) {
            if (teamId != null || personalPhotoPaths.contains(entity.path)) {
              photoCount++;
              photoSizeBytes += await entity.length();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Storage stats error: $e');
    }
  }

  Future<void> _loadSyncStats({String? userId, String? teamId}) async {
    try {
      final total = totalScans;
      if (total == 0 || userId == null) {
        syncedScans = 0;
        unsyncedScans = 0;
        syncedPhotos = 0;
        unsyncedPhotos = 0;
        pendingQueueCount = 0;
        return;
      }

      // Count scans synced to Supabase
      final supabase = SupabaseService();
      final client = supabase.client;
      if (client == null) return;

      final response = teamId != null
          ? await client
              .from('scans')
              .select('id, photo_url, resi')
              .eq('team_id', teamId)
          : await client
              .from('scans')
              .select('id, photo_url, resi')
              .eq('user_id', userId);
      syncedScans = response.length;
      unsyncedScans = total - syncedScans;

      // Count photos from Supabase (cloud URL = synced)
      int cloudPhotos = 0;
      int localOnlyPhotos = 0;
      int cloudPhotoBytes = 0;
      final cloudPhotoResis = <String>{};
      for (final row in response) {
        final photoUrl = row['photo_url'] as String?;
        if (photoUrl != null && photoUrl.isNotEmpty) {
          if (photoUrl.startsWith('http')) {
            cloudPhotos++;
          } else {
            // photo_url di cloud masih path lokal = belum upload fotonya
            localOnlyPhotos++;
          }
        }
      }

      // Hitung ukuran foto yang sudah di cloud dari file lokal
      final orders = await _db.getAllOrders(userId: userId);
      for (final o in orders) {
        if (o.photoPath != null && o.photoPath!.isNotEmpty) {
          // Foto lokal yang belum ada di cloud (order belum sync ke cloud)
          if (!o.photoPath!.startsWith('http') && !cloudPhotoResis.contains(o.resi)) {
            // Sudah dihitung di localOnlyPhotos atau order belum ada di cloud
          }
          // Hitung ukuran foto yang sudah sync ke cloud
          if (o.photoPath!.startsWith('http')) {
            // Foto di cloud — cek apakah file lokal masih ada untuk ukuran
          } else {
            final f = File(o.photoPath!);
            if (f.existsSync()) {
              // Jika foto ini ada di cloud (cloudPhotos count), tambah ukurannya
              // Kita estimasi: proporsi foto lokal yang sync = cloudPhotos / totalPhotos
            }
          }
        }
      }

      // Estimasi ukuran foto cloud: rata-rata ukuran foto lokal × jumlah foto cloud
      if (photoCount > 0 && cloudPhotos > 0) {
        final avgPhotoSize = photoSizeBytes ~/ photoCount;
        cloudPhotoBytes = avgPhotoSize * cloudPhotos;
      }
      cloudPhotoSizeBytes = cloudPhotoBytes;

      // Estimasi ukuran DB cloud: proporsi data sync × ukuran DB lokal
      if (total > 0 && syncedScans > 0) {
        cloudDbSizeBytes = (dbSizeBytes * syncedScans) ~/ total;
      }

      syncedPhotos = cloudPhotos;
      unsyncedPhotos = localOnlyPhotos + unsyncedScans; // foto di cloud masih path + foto yang order belum sync

      // Collect unsynced photo resi list
      final unsyncedResis = <String>[];
      // Orders not synced to cloud at all
      if (unsyncedScans > 0) {
        final localOrders = await _db.getAllOrders(userId: userId);
        final cloudResis = (response as List).map((r) => r['resi'] as String?).where((r) => r != null).toSet();
        for (final o in localOrders) {
          if (!cloudResis.contains(o.resi) && o.photoPath != null && o.photoPath!.isNotEmpty) {
            unsyncedResis.add(o.resi);
          }
        }
      }
      // Orders in cloud but photo not uploaded (photo_url is local path)
      for (final row in response) {
        final photoUrl = row['photo_url'] as String?;
        final resi = row['resi'] as String?;
        if (photoUrl != null && photoUrl.isNotEmpty && !photoUrl.startsWith('http') && resi != null) {
          unsyncedResis.add(resi);
        }
      }
      unsyncedPhotoResis = unsyncedResis;

      // Pending queue count
      pendingQueueCount = await _syncQueue.pendingCount;
    } catch (e) {
      debugPrint('Sync stats error: $e');
    }
  }

  Future<void> _loadCategorySyncStats({String? userId, String? teamId}) async {
    try {
      if (userId == null) {
        syncedCategories = 0;
        unsyncedCategories = 0;
        return;
      }

      final supabase = SupabaseService();
      final client = supabase.client;
      if (client == null) return;

      // Get local categories
      final localCats = await _db.getAllCategories(userId: userId);
      
      // Get Supabase categories for current user
      final remoteCats = await supabase.fetchCategories();
      final remoteCatKeys = <String>{}; // name|userId
      
      for (final c in remoteCats) {
        final name = c['name'] as String;
        final ownerId = c['user_id'] as String?;
        if (ownerId != null) {
          remoteCatKeys.add('$name|$ownerId');
        }
      }

      // For team members, also fetch admin's categories from Supabase
      if (teamId != null && _adminUserId != null) {
          final adminCats = await supabase.fetchTeamCategories(_adminUserId!);
          for (final c in adminCats) {
            final name = c['name'] as String;
            final ownerId = c['user_id'] as String?;
            if (ownerId != null) {
              remoteCatKeys.add('$name|$ownerId');
            }
          }
      }

      // Compare local with remote
      int synced = 0;
      for (final cat in localCats) {
        final key = '${cat.name}|${cat.userId}';
        if (remoteCatKeys.contains(key)) {
          synced++;
        }
      }

      syncedCategories = synced;
      unsyncedCategories = localCats.length - synced;
      debugPrint('[Stats] category sync: total=${localCats.length}, synced=$synced, unsynced=${localCats.length - synced}, remoteKeys=$remoteCatKeys');
    } catch (e) {
      debugPrint('Category sync stats error: $e');
    }
  }

  Future<void> _loadTeamStats() async {
    try {
      final supabase = SupabaseService();
      final client = supabase.client;
      if (client == null) {
        memberScanStats = {};
        teamMembers = [];
        return;
      }

      // Get current user's team
      final team = await supabase.getMyTeam();
      if (team == null) {
        memberScanStats = {};
        teamMembers = [];
        return;
      }

      // Get team members
      final membersData = await supabase.getTeamMembers(team.id);
      teamMembers = membersData.map((m) => TeamMember.fromMap(m)).toList();

      // Get scan counts per user_id from scans table for this team
      final response = await client
          .from('scans')
          .select('user_id')
          .eq('team_id', team.id);

      // Count scans per user_id
      final userCounts = <String, int>{};
      for (final row in response) {
        final uid = row['user_id'] as String?;
        if (uid != null) {
          userCounts[uid] = (userCounts[uid] ?? 0) + 1;
        }
      }

      // Map user_id -> email
      final memberScanMap = <String, int>{};
      for (final m in teamMembers) {
        final email = m.email ?? m.userId.substring(0, 8);
        memberScanMap[email] = userCounts[m.userId] ?? 0;
      }

      memberScanStats = memberScanMap;
    } catch (e) {
      debugPrint('Team stats error: $e');
      memberScanStats = {};
      teamMembers = [];
    }
  }

  Future<void> setPeriod(int days) async {
    periodDays = days;
    await loadStats();
  }

  String get formattedDbSize => _formatBytes(dbSizeBytes);
  String get formattedPhotoSize => _formatBytes(photoSizeBytes);
  String get formattedTotalSize => _formatBytes(dbSizeBytes + photoSizeBytes);
  String get formattedCloudDbSize => _formatBytes(cloudDbSizeBytes);
  String get formattedCloudPhotoSize => _formatBytes(cloudPhotoSizeBytes);
  String get formattedCloudTotalSize => _formatBytes(cloudDbSizeBytes + cloudPhotoSizeBytes);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
