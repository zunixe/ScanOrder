import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/admin_gate.dart';
import '../core/theme.dart';
import 'admin_provider.dart';
import 'approvals_screen.dart';
import 'scans_browser_screen.dart';
import 'users_list_screen.dart';

/// Halaman Admin Panel — dashboard statistik + pintu ke browser scans.
///
/// HAPUS ingatan: screen ini hanya bisa dibuka dari build admin
/// (flavor `admin`, entry lib/main_admin.dart) dan hanya saat login
/// sebagai super admin (AdminGate.superAdminEmail).
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Post-frame agar tidak memicu notifyListeners() saat build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final admin = context.read<AdminProvider>();
      admin.fetchStats();
      admin.fetchTeams();
      admin.fetchPendingApprovals();
      // Realtime: pendaftar baru → notifikasi lokal + refresh badge
      admin.startApprovalWatcher();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Panel')),
      body: Consumer<AdminProvider>(
        builder: (_, admin, _) {
          return RefreshIndicator(
            onRefresh: () async {
              final admin = context.read<AdminProvider>();
              await admin.fetchStats();
              await admin.fetchTeams();
              await admin.fetchPendingApprovals();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (admin.statsError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      color: AppTheme.dangerColor.withValues(alpha: 0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          admin.statsError!,
                          style: const TextStyle(
                              color: AppTheme.dangerColor,
                              fontSize: AppTheme.bodySize),
                        ),
                      ),
                    ),
                  ),
                // Kartu approval — hanya tampil jika ada pendaftar menunggu
                if (admin.pendingCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      color: AppTheme.warningColor.withValues(alpha: 0.08),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                            color: AppTheme.warningColor.withValues(alpha: 0.4)),
                      ),
                      child: ListTile(
                        leading: Badge(
                          label: Text('${admin.pendingCount}'),
                          backgroundColor: AppTheme.dangerColor,
                          child: const Icon(Icons.how_to_reg_outlined,
                              color: AppTheme.warningColor, size: 30),
                        ),
                        title: const Text('Persetujuan Pendaftar',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${admin.pendingCount} akun menunggu persetujuan',
                          style: TextStyle(fontSize: AppTheme.captionSize),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ApprovalsScreen()),
                        ),
                      ),
                    ),
                  ),
                if (admin.statsLoading && admin.statsError == null)
                  const Center(
                      child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ))
                else ...[
                  Row(
                    children: [
                      Expanded(
                          child: _StatCard(
                        icon: Icons.qr_code_scanner,
                        color: AppTheme.primaryColor,
                        label: 'Scan Hari Ini',
                        value: admin.stats.scansToday,
                      )),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _StatCard(
                        icon: Icons.inventory_2,
                        color: AppTheme.successColor,
                        label: 'Total Scan',
                        value: admin.stats.totalScans,
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: _StatCard(
                        icon: Icons.people_outline,
                        color: AppTheme.warningColor,
                        label: 'User Terdaftar',
                        value: admin.stats.totalUsers,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const UsersListScreen()),
                        ),
                      )),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _StatCard(
                        icon: Icons.groups_outlined,
                        color: Colors.deepPurple,
                        label: 'Tim Aktif',
                        value: admin.stats.totalTeams,
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _StatCard(
                    icon: Icons.workspace_premium_outlined,
                    color: Colors.teal,
                    label: 'Langganan Berbayar Aktif',
                    value: admin.stats.activeSubscriptions,
                    wide: true,
                  ),
                ],
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.people_outline,
                      color: AppTheme.warningColor),
                  title: const Text('Lihat Daftar User',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Email, tier & aktivitas tiap user',
                      style: TextStyle(fontSize: AppTheme.captionSize)),
                  trailing: const Icon(Icons.chevron_right),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300)),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const UsersListScreen()),
                  ),
                ),
                const SizedBox(height: 4),
                ListTile(
                  leading: const Icon(Icons.list_alt,
                      color: AppTheme.primaryColor),
                  title: const Text('Lihat Semua Scan',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Browser seluruh data scan user',
                      style:
                          TextStyle(fontSize: AppTheme.captionSize)),
                  trailing: const Icon(Icons.chevron_right),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300)),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ScansBrowserScreen()),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Login: ${AdminGate.superAdminEmail}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: AppTheme.microSize, color: Colors.grey),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int value;
  final bool wide;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.wide = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
          child: Column(
            crossAxisAlignment: wide
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 28),
                  if (onTap != null) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        size: 18, color: Colors.grey.shade400),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text('$value',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: AppTheme.captionSize,
                      color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}
