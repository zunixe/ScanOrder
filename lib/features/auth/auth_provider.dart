import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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
  bool get isTeamMember => hasTeam && !isAdmin;
  String? get teamId => _currentTeam?.id;

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

        // Auto-leave team if member's subscription expired (Free tier = no active sub)
        if (isTeamMember) {
          final quota = QuotaService();
          final tier = await quota.getTier();
          final active = await quota.isSubscriptionActive();
          if (tier == StorageTier.free || !active) {
            debugPrint('[AuthProvider] Team member subscription expired, auto-leaving team');
            await leaveTeam();
            return;
          }
        }
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
      // Check minimum Basic subscription
      final quota = QuotaService();
      final tier = await quota.getTier();
      if (tier == StorageTier.free) {
        _error = 'Minimal langganan Basic untuk bisa gabung tim';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final ok = await _supabase.joinTeam(inviteCode);
      if (ok) {
        await _loadTeam();
        // Sync team data (orders + admin categories) to local
        await syncOnLogin();
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
      if (isAdmin) {
        // Admin leaving: transfer or dissolve
        if (_teamMembers.length > 1) {
          // Find oldest non-admin member to transfer to
          final nextAdmin = _teamMembers
              .where((m) => m.role != 'admin')
              .fold<TeamMember?>(null, (best, m) {
            if (best == null || m.joinedAt.isBefore(best.joinedAt)) return m;
            return best;
          });
          if (nextAdmin != null) {
            // Transfer admin role
            final ok = await _supabase.transferAdmin(_currentTeam!.id, nextAdmin.userId);
            if (!ok) {
              _error = 'Gagal transfer admin. Coba lagi.';
              _isLoading = false;
              notifyListeners();
              return;
            }
          }
        } else {
          // Admin is the only member — dissolve team
          final ok = await _supabase.dissolveTeam(_currentTeam!.id);
          if (!ok) {
            _error = 'Gagal membubarkan tim. Coba lagi.';
            _isLoading = false;
            notifyListeners();
            return;
          }
        }
      } else {
        // Regular member leaving
        final ok = await _supabase.leaveTeam();
        if (!ok) {
          _error = 'Gagal keluar dari tim';
          _isLoading = false;
          notifyListeners();
          return;
        }
      }
      _currentTeam = null;
      _teamMembers = [];
      // Clear team data from local DB, keep personal data
      await _clearTeamDataLocally();
    } catch (e) {
      _error = 'Error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _clearTeamDataLocally() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;
      // Delete orders that belong to a team (not user's personal orders)
      await _db.deleteTeamOrders(userId);
      // Delete categories that belong to team admin (not user's personal categories)
      await _db.deleteTeamCategories(userId);
      debugPrint('[AuthProvider] Cleared team data from local DB');
    } catch (e) {
      debugPrint('[AuthProvider] Clear team data error: $e');
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
          final id = await _db.insertOrder(o, userId: userId, teamId: teamId);
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

      // If in a team, update team_id for existing orders that don't have it yet
      if (teamId != null && userId != null) {
        await _db.updateTeamIdForUser(userId, teamId);
      }

      // Sync photos from cloud to local
      await _syncPhotosToLocal(userId: userId);

      // Sync categories from cloud (don't pass Supabase UUID id — let local DB auto-generate)
      final remoteCats = await _supabase.fetchCategories();
      for (final c in remoteCats) {
        try {
          await _db.insertCategory(ScanCategory(
            name: c['name'] as String,
            color: c['color'] as String,
            userId: c['user_id'] as String?,
          ));
        } catch (e) {
          debugPrint('Sync category error: $e');
        }
      }

      // If team member, also sync admin's categories
      if (isTeamMember && _currentTeam != null) {
        final adminCats = await _supabase.fetchTeamCategories(_currentTeam!.createdBy);
        for (final c in adminCats) {
          try {
            await _db.insertCategory(ScanCategory(
              name: c['name'] as String,
              color: c['color'] as String,
              userId: c['user_id'] as String?,
            ));
          } catch (e) {
            debugPrint('Sync admin category error: $e');
          }
        }
      }

      // Sync scan-category relations from Supabase
      // Need to map: Supabase scan_id -> local order by resi, Supabase category UUID -> local category by name+user_id
      if (teamId != null) {
        await _syncTeamScanCategories(teamId);
      } else {
        final remoteOC = await _supabase.fetchOrderCategories();
        for (final oc in remoteOC) {
          try {
            // Personal mode: scan_id and category_id might still be int
            await _db.assignCategoryToOrder(
              oc['scan_id'] as int,
              oc['category_id'] as int,
            );
          } catch (e) {
            debugPrint('Sync order-category error: $e');
          }
        }
      }

      // Repair: push local scan_categories to Supabase (for admin)
      if (teamId != null) {
        await _supabase.repairScanCategories();
      }
    } catch (e) {
      debugPrint('Sync error: $e');
    }
  }

  /// Sync scan_categories from Supabase for team mode
  /// Map Supabase scan_id (BIGINT) to local order id via resi
  /// Map Supabase category UUID to local category id via name+user_id
  Future<void> _syncTeamScanCategories(String teamId) async {
    try {
      final client = _supabase.client;
      if (client == null) return;

      // Fetch all scan_categories for this team from Supabase
      final response = await client
          .from('scan_categories')
          .select('scan_id, category_id, scans!inner(resi, team_id), categories!inner(name, user_id)')
          .eq('scans.team_id', teamId);

      int synced = 0;
      for (final row in response as List) {
        try {
          final scanData = row['scans'] as Map<String, dynamic>;
          final catData = row['categories'] as Map<String, dynamic>;
          final resi = scanData['resi'] as String;
          final catName = catData['name'] as String;
          final catUserId = catData['user_id'] as String;

          // Find local order by resi
          final localOrder = await _db.findByResi(resi, userId: _supabase.currentUser?.id);
          if (localOrder == null || localOrder.id == null) continue;

          // Find local category by name + user_id
          final localCats = await _db.getAllCategories(userId: _supabase.currentUser?.id);
          final localCat = localCats.where((c) => c.name == catName && c.userId == catUserId).firstOrNull;
          if (localCat == null || localCat.id == null) continue;

          await _db.assignCategoryToOrder(localOrder.id!, localCat.id!);
          synced++;
        } catch (e) {
          debugPrint('Sync team scan-category error: $e');
        }
      }
      debugPrint('[AuthProvider] _syncTeamScanCategories: synced=$synced');
    } catch (e) {
      debugPrint('[AuthProvider] _syncTeamScanCategories error: $e');
    }
  }

  Future<void> _syncPhotosToLocal({String? userId}) async {
    try {
      final orders = await _db.getAllOrders(userId: userId);
      final dir = await getApplicationDocumentsDirectory();
      int downloaded = 0;

      for (final o in orders) {
        final photoPath = o.photoPath;
        if (photoPath == null || photoPath.isEmpty) continue;

        // Jika photoPath adalah URL cloud (http) dan file lokal belum ada
        if (photoPath.startsWith('http')) {
          // Extract storage path dari URL
          // URL format: https://xxx.supabase.co/storage/v1/object/public/scan-photos/userId/timestamp.jpg
          final uri = Uri.parse(photoPath);
          final segments = uri.pathSegments;
          // Cari index 'scan-photos' di path segments
          final bucketIndex = segments.indexOf('scan-photos');
          if (bucketIndex >= 0 && bucketIndex + 1 < segments.length) {
            final storagePath = segments.sublist(bucketIndex + 1).join('/');
            final localFile = File('${dir.path}/scan_${o.scannedAt.millisecondsSinceEpoch}.jpg');

            // Hanya download jika file lokal belum ada
            if (!await localFile.exists()) {
              final localPath = await _supabase.downloadPhoto(storagePath, localFile.path);
              if (localPath != null) {
                // Update photo_path di DB lokal ke path lokal
                await _db.updateOrderPhoto(o.id!, localPath);
                downloaded++;
              }
            }
          }
        } else if (!photoPath.startsWith('http') && !File(photoPath).existsSync()) {
          // photoPath adalah path lokal tapi file sudah hilang (reinstall)
          // Cek apakah ada di Supabase scans table dengan cloud URL
          final client = _supabase.client;
          if (client != null && userId != null) {
            final result = await client
                .from('scans')
                .select('photo_url')
                .eq('resi', o.resi)
                .eq('user_id', userId)
                .maybeSingle();
            final cloudUrl = result?['photo_url'] as String?;
            if (cloudUrl != null && cloudUrl.startsWith('http')) {
              final uri = Uri.parse(cloudUrl);
              final segments = uri.pathSegments;
              final bucketIndex = segments.indexOf('scan-photos');
              if (bucketIndex >= 0 && bucketIndex + 1 < segments.length) {
                final storagePath = segments.sublist(bucketIndex + 1).join('/');
                final localFile = File('${dir.path}/scan_${o.scannedAt.millisecondsSinceEpoch}.jpg');
                final localPath = await _supabase.downloadPhoto(storagePath, localFile.path);
                if (localPath != null) {
                  await _db.updateOrderPhoto(o.id!, localPath);
                  downloaded++;
                }
              }
            }
          }
        }
      }
      if (downloaded > 0) {
        debugPrint('[AuthProvider] Synced $downloaded photos from cloud to local');
      }
    } catch (e) {
      debugPrint('[AuthProvider] Sync photos to local error: $e');
    }
  }
}
