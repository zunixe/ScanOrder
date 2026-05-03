import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../core/db/database_helper.dart';
import '../../core/supabase/supabase_service.dart';
import '../../models/scan_record.dart';
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
  Map<String, String> unsyncedPhotoPaths = {}; // resi -> photoPath

  // Team stats
  Map<String, int> memberScanStats = {}; // email -> scan count
  List<TeamMember> teamMembers = [];

  String? _teamId;
  String? _adminUserId;
  String? get teamId => _teamId;

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
    debugPrint('[Stats] photoSizeBytes=$photoSizeBytes, cloudPhotoSizeBytes=$cloudPhotoSizeBytes, dbSizeBytes=$dbSizeBytes, cloudDbSizeBytes=$cloudDbSizeBytes');
    notifyListeners();
  }

  Future<void> _loadStorageStats() async {
    try {
      dbSizeBytes = 0;
      photoSizeBytes = 0;
      photoCount = 0;

      final userId = SupabaseService().currentUser?.id;
      final teamId = _teamId;

      // Database size — proportional to user's data in personal mode
      final dbPath = await getDatabasesPath();
      final dbFile = File(join(dbPath, 'scanorder.db'));
      if (await dbFile.exists()) {
        if (teamId != null) {
          // Team mode: full DB size
          dbSizeBytes = await dbFile.length();
        } else {
          // Personal mode: proportion by user's scan count
          final totalScansCount = await _db.getTotalOrderCount();
          final personalScansCount = userId != null ? await _db.getTotalOrderCount(userId: userId) : 0;
          if (personalScansCount == 0) {
            dbSizeBytes = 0;
          } else {
            final fullDbSize = await dbFile.length();
            dbSizeBytes = totalScansCount > 0
                ? (fullDbSize * personalScansCount) ~/ totalScansCount
                : fullDbSize;
          }
        }
      }

      // Photos size: count actual photo files on disk
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory(docsDir.path);
      if (await dir.exists()) {
        if (teamId != null) {
          // Team mode: count all scan_*.jpg files
          await for (final entity in dir.list()) {
            if (entity is File && entity.path.contains('scan_') && entity.path.endsWith('.jpg')) {
              photoCount++;
              photoSizeBytes += await entity.length();
            }
          }
        } else {
          // Personal mode: only count photos for personal scans
          // Build set of local file paths from scans (both local paths and cloud URLs that have local files)
          final personalOrders = userId != null
              ? await _db.getAllScans(userId: userId)
              : <ScanRecord>[];
          final localPhotoPaths = <String>{};
          for (final o in personalOrders) {
            if (o.photoPath != null && o.photoPath!.isNotEmpty) {
              if (!o.photoPath!.startsWith('http')) {
                // Local path — check if file exists
                if (File(o.photoPath!).existsSync()) {
                  localPhotoPaths.add(o.photoPath!);
                }
              } else {
                // Cloud URL — check if local file exists (downloaded from cloud)
                final localFile = File('${docsDir.path}/scan_${o.scannedAt.millisecondsSinceEpoch}.jpg');
                if (await localFile.exists()) {
                  localPhotoPaths.add(localFile.path);
                }
              }
            }
          }
          for (final path in localPhotoPaths) {
            photoCount++;
            photoSizeBytes += await File(path).length();
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
              .select('id, photo_url, resi, user_id')
              .eq('team_id', teamId)
          : await client
              .from('scans')
              .select('id, photo_url, resi, user_id')
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
            cloudPhotoResis.add(row['resi'] as String? ?? '');
          } else {
            // photo_url di cloud masih path lokal = belum upload fotonya
            localOnlyPhotos++;
          }
        }
      }

      // For team mode: count unsynced photos also from Supabase (not local DB)
      // because local DB filters team_id IS NULL and won't include team scans
      if (teamId != null) {
        // Team scans with photo_url that is NOT http = photo not uploaded
        // Orders not in Supabase at all but have photos locally
        final localTeamOrders = await _db.getTeamScans();
        final cloudResiSet = (response as List).map((r) => r['resi'] as String?).where((r) => r != null).toSet();
        int extraUnsyncedPhotos = 0;
        for (final o in localTeamOrders) {
          if (!cloudResiSet.contains(o.resi) && o.photoPath != null && o.photoPath!.isNotEmpty) {
            extraUnsyncedPhotos++;
          }
        }

        // Estimasi ukuran foto cloud
        if (photoCount > 0 && cloudPhotos > 0) {
          final avgPhotoSize = photoSizeBytes ~/ photoCount;
          cloudPhotoBytes = avgPhotoSize * cloudPhotos;
        }
        cloudPhotoSizeBytes = cloudPhotoBytes;

        // Estimasi ukuran DB cloud
        if (dbSizeBytes > 0 && total > 0 && syncedScans > 0) {
          cloudDbSizeBytes = (dbSizeBytes * syncedScans) ~/ total;
        } else {
          cloudDbSizeBytes = 0;
        }

        syncedPhotos = cloudPhotos;
        unsyncedPhotos = localOnlyPhotos + extraUnsyncedPhotos;

        // Collect unsynced photo resi list
        final unsyncedResis = <String>[];
        final unsyncedPaths = <String, String>{};
        // Orders in cloud but photo not uploaded (photo_url is local path)
        for (final row in response) {
          final photoUrl = row['photo_url'] as String?;
          final resi = row['resi'] as String?;
          if (photoUrl != null && photoUrl.isNotEmpty && !photoUrl.startsWith('http') && resi != null) {
            unsyncedResis.add(resi);
            unsyncedPaths[resi] = photoUrl;
            debugPrint('[Stats] unsynced photo: resi=$resi, photo_url=$photoUrl');
          }
        }
        // Local team scans not synced to cloud at all
        for (final o in localTeamOrders) {
          if (!cloudResiSet.contains(o.resi) && o.photoPath != null && o.photoPath!.isNotEmpty) {
            unsyncedResis.add(o.resi);
            unsyncedPaths[o.resi] = o.photoPath!;
            debugPrint('[Stats] unsynced photo (local only): resi=${o.resi}, photoPath=${o.photoPath}');
          }
        }
        unsyncedPhotoResis = unsyncedResis;
        unsyncedPhotoPaths = unsyncedPaths;
      } else {
        // Personal mode: use local DB for photo stats
        final scans = await _db.getAllScans(userId: userId);

        // Estimasi ukuran foto cloud
        if (photoCount > 0 && cloudPhotos > 0) {
          final avgPhotoSize = photoSizeBytes ~/ photoCount;
          cloudPhotoBytes = avgPhotoSize * cloudPhotos;
        }
        cloudPhotoSizeBytes = cloudPhotoBytes;

        // Estimasi ukuran DB cloud
        if (dbSizeBytes > 0 && total > 0 && syncedScans > 0) {
          cloudDbSizeBytes = (dbSizeBytes * syncedScans) ~/ total;
        } else {
          cloudDbSizeBytes = 0;
        }

        syncedPhotos = cloudPhotos;
        unsyncedPhotos = localOnlyPhotos + unsyncedScans;

        // Collect unsynced photo resi list
        final unsyncedResis = <String>[];
        final unsyncedPaths = <String, String>{};
        // Orders not synced to cloud at all
        if (unsyncedScans > 0) {
          final cloudResis = (response as List).map((r) => r['resi'] as String?).where((r) => r != null).toSet();
          for (final o in scans) {
            if (!cloudResis.contains(o.resi) && o.photoPath != null && o.photoPath!.isNotEmpty) {
              unsyncedResis.add(o.resi);
              unsyncedPaths[o.resi] = o.photoPath!;
            }
          }
        }
        // Orders in cloud but photo not uploaded (photo_url is local path)
        for (final row in response) {
          final photoUrl = row['photo_url'] as String?;
          final resi = row['resi'] as String?;
          if (photoUrl != null && photoUrl.isNotEmpty && !photoUrl.startsWith('http') && resi != null) {
            unsyncedResis.add(resi);
            unsyncedPaths[resi] = photoUrl;
          }
        }
        unsyncedPhotoResis = unsyncedResis;
        unsyncedPhotoPaths = unsyncedPaths;
      }

      // Pending queue count
      pendingQueueCount = await _syncQueue.pendingCount;

      debugPrint('[Stats] sync stats: total=$total, syncedScans=$syncedScans, unsyncedScans=$unsyncedScans, cloudPhotos=$cloudPhotos, localOnlyPhotos=$localOnlyPhotos, syncedPhotos=$syncedPhotos, unsyncedPhotos=$unsyncedPhotos, pendingQueue=$pendingQueueCount, teamId=$teamId');
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

      // Get scan counts per scanned_by from scans table for this team
      final response = await client
          .from('scans')
          .select('scanned_by, user_id')
          .eq('team_id', team.id);

      // Count scans per scanned_by (who actually scanned)
      final scannerCounts = <String, int>{};
      for (final row in response) {
        final scanner = (row['scanned_by'] as String?) ?? (row['user_id'] as String?) ?? '';
        if (scanner.isNotEmpty) {
          scannerCounts[scanner] = (scannerCounts[scanner] ?? 0) + 1;
        }
      }

      // Map user_id -> email
      final memberScanMap = <String, int>{};
      for (final m in teamMembers) {
        final email = m.email ?? m.userId.substring(0, 8);
        memberScanMap[email] = scannerCounts[m.userId] ?? 0;
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
