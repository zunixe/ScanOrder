import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart' as pinfo;
import '../../core/theme.dart';
import '../../core/supabase/supabase_service.dart';
import '../../core/db/database_helper.dart';
import '../../services/quota_service.dart';
import '../../services/sync_queue.dart';
import '../auth/auth_provider.dart';
import '../auth/login_dialog.dart';
import '../contact/contact_page.dart';
import '../history/history_provider.dart';
import '../scan/scan_provider.dart';
import '../stats/stats_provider.dart';
import '../subscription/subscription_provider.dart';
import 'settings_provider.dart';

const _settingsTitleStyle = TextStyle(fontSize: AppTheme.cardTitleSize, fontWeight: FontWeight.w600);
const _settingsSubtitleStyle = TextStyle(fontSize: AppTheme.captionSize, color: Colors.grey);
const _settingsSectionStyle = TextStyle(fontSize: AppTheme.bodySize, fontWeight: FontWeight.w600, color: Colors.grey);
const _settingsTilePadding = EdgeInsets.symmetric(horizontal: 16, vertical: 2);

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await pinfo.PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _appVersion = '${info.version} (${info.buildNumber})');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: Consumer2<AuthProvider, SubscriptionProvider>(
        builder: (_, auth, sub, _) {
          final isTeam = sub.currentTier == StorageTier.unlimited;
          return ListView(
            children: [
              // ── 1. Profil User ──
              _ProfileSection(auth: auth, tier: sub.currentTier),
              const Divider(height: 1),

              // ── 2. Kelola Team ──
              if (auth.isLoggedIn) ...[
                _TeamSection(auth: auth, isTeamAdmin: isTeam),
                const Divider(height: 1),
              ],

              // ── 3. Pengaturan ──
              const _SettingsSection(),
              const Divider(height: 1),

              // ── 4. Backup & Sync ──
              _SyncSection(auth: auth),
              const Divider(height: 1),

              // ── 5. Hubungi Kami ──
              ListTile(
                dense: true,
                contentPadding: _settingsTilePadding,
                leading: const Icon(Icons.contact_mail_outlined),
                title: const Text('Hubungi Kami', style: _settingsTitleStyle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ContactPage()),
                ),
              ),
              const Divider(height: 1),

              // ── 6. Tentang ──
              ListTile(
                dense: true,
                contentPadding: _settingsTilePadding,
                leading: const Icon(Icons.info_outline),
                title: const Text('Tentang Aplikasi', style: _settingsTitleStyle),
                subtitle: Text('v$_appVersion', style: _settingsSubtitleStyle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showAboutDialog(),
              ),
              ListTile(
                dense: true,
                contentPadding: _settingsTilePadding,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Kebijakan Privasi', style: _settingsTitleStyle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showDocument('Kebijakan Privasi', 'PRIVACY_POLICY.md'),
              ),
              ListTile(
                dense: true,
                contentPadding: _settingsTilePadding,
                leading: const Icon(Icons.description_outlined),
                title: const Text('Syarat & Ketentuan', style: _settingsTitleStyle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showDocument('Syarat & Ketentuan', 'TERMS_OF_SERVICE.md'),
              ),
              const Divider(height: 1),

              // ── 7. Logout ──
              if (auth.isLoggedIn)
                ListTile(
                  dense: true,
                  contentPadding: _settingsTilePadding,
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Logout', style: TextStyle(fontSize: AppTheme.cardTitleSize, fontWeight: FontWeight.w600, color: Colors.red)),
                  onTap: () => _showLogoutDialog(auth),
                ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.qr_code_scanner, size: 32, color: AppTheme.primaryColor),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('ScanOrder', style: TextStyle(fontSize: AppTheme.cardTitleSize, fontWeight: FontWeight.bold)),
                Text('v$_appVersion', style: TextStyle(fontSize: AppTheme.captionSize, color: Colors.grey[600])),
              ],
            ),
          ],
        ),
        content: const Text('Aplikasi scan & kelola nomor resi pengiriman.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showDocument(String title, String asset) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: asset == 'PRIVACY_POLICY.md'
              ? const _PrivacyPolicyContent()
              : const _TermsContent(),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  void _showLogoutDialog(AuthProvider auth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Yakin ingin logout? Data lokal tetap tersimpan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              auth.signOut();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

class _DocumentItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DocumentItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppTheme.primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _settingsTitleStyle),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: _settingsSubtitleStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyPolicyContent extends StatelessWidget {
  const _PrivacyPolicyContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DocumentItem(
          icon: Icons.storage_outlined,
          title: 'Data yang Disimpan',
          subtitle: 'Email akun, data scan/resi, foto bukti scan, kategori, riwayat, informasi tim, dan preferensi aplikasi.',
        ),
        _DocumentItem(
          icon: Icons.sync_outlined,
          title: 'Penggunaan Data',
          subtitle: 'Data digunakan untuk scan, riwayat, kategori, export, team, backup, dan sinkronisasi.',
        ),
        _DocumentItem(
          icon: Icons.verified_user_outlined,
          title: 'Keamanan',
          subtitle: 'Data cloud disimpan dengan enkripsi dan aturan akses pengguna. Data tidak dijual ke pihak lain.',
        ),
        _DocumentItem(
          icon: Icons.phone_android_outlined,
          title: 'Data Lokal',
          subtitle: 'Data yang dihapus dari cloud belum tentu langsung hilang dari perangkat jika belum sync ulang.',
        ),
      ],
    );
  }
}

class _TermsContent extends StatelessWidget {
  const _TermsContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DocumentItem(
          icon: Icons.qr_code_scanner_outlined,
          title: 'Penggunaan Aplikasi',
          subtitle: 'ScanOrder membantu scan, menyimpan, mengelompokkan, menyalin, export, dan sync nomor resi.',
        ),
        _DocumentItem(
          icon: Icons.workspace_premium_outlined,
          title: 'Akun dan Paket',
          subtitle: 'Fitur tertentu memerlukan login dan paket aktif. Free, Basic, Pro, dan Team memiliki fitur berbeda.',
        ),
        _DocumentItem(
          icon: Icons.groups_outlined,
          title: 'Paket Team',
          subtitle: 'Admin dan anggota bertanggung jawab atas invite code, data scan, kategori, dan akses tim.',
        ),
        _DocumentItem(
          icon: Icons.cloud_sync_outlined,
          title: 'Data dan Sinkronisasi',
          subtitle: 'Data dapat tersimpan lokal dan cloud. Perbedaan data bisa terjadi jika perangkat belum tersinkronisasi.',
        ),
        _DocumentItem(
          icon: Icons.payments_outlined,
          title: 'Pembayaran',
          subtitle: 'Pembelian paket mengikuti aturan platform pembayaran yang digunakan.',
        ),
        _DocumentItem(
          icon: Icons.rule_outlined,
          title: 'Tanggung Jawab Pengguna',
          subtitle: 'Pengguna wajib memastikan data resi, kategori, dan export digunakan sesuai kebutuhan operasional.',
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// 1. PROFILE SECTION
// ────────────────────────────────────────────────────────────

class _ProfileSection extends StatelessWidget {
  final AuthProvider auth;
  final StorageTier tier;
  const _ProfileSection({required this.auth, required this.tier});

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService().currentUser;
    final email = user?.email ?? 'Belum login';
    final initials = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
            child: Text(
              initials,
              style: const TextStyle(fontSize: AppTheme.heroSize, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(email, style: _settingsTitleStyle),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _tierColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _tierLabel,
                        style: TextStyle(fontSize: AppTheme.captionSize, fontWeight: FontWeight.w600, color: _tierColor),
                      ),
                    ),
                    if (!auth.isLoggedIn) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => showLoginDialog(context),
                        child: const Text('Login'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color get _tierColor {
    // Team member (non-admin) uses purple to indicate team affiliation
    if (auth.isTeamMember) return Colors.purple;
    switch (tier) {
      case StorageTier.unlimited:
        return Colors.purple;
      case StorageTier.pro:
        return Colors.blue;
      case StorageTier.basic:
        return Colors.teal;
      case StorageTier.free:
        return Colors.grey;
    }
  }

  String get _tierLabel {
    // Show 'Anggota Tim' when user is a team member (not admin)
    if (auth.isTeamMember) return 'Anggota Tim';
    switch (tier) {
      case StorageTier.unlimited:
        return 'Team';
      case StorageTier.pro:
        return 'Pro';
      case StorageTier.basic:
        return 'Basic';
      case StorageTier.free:
        return 'Free';
    }
  }
}

// ────────────────────────────────────────────────────────────
// 2. TEAM SECTION
// ────────────────────────────────────────────────────────────

class _TeamSection extends StatelessWidget {
  final AuthProvider auth;
  final bool isTeamAdmin;
  const _TeamSection({required this.auth, required this.isTeamAdmin});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Text('Kelola Tim', style: _settingsSectionStyle),
        ),
        if (auth.hasTeam) ...[
          ListTile(
            dense: true,
            contentPadding: _settingsTilePadding,
            leading: const CircleAvatar(
              backgroundColor: Colors.purple,
              child: Icon(Icons.groups, color: Colors.white),
            ),
            title: Text(auth.currentTeam!.name, style: _settingsTitleStyle),
            subtitle: isTeamAdmin ? Text('Kode invite: ${auth.currentTeam!.inviteCode}', style: _settingsSubtitleStyle) : null,
            trailing: isTeamAdmin ? IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Salin kode invite',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: auth.currentTeam!.inviteCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Kode invite disalin'), duration: Duration(seconds: 1)),
                );
              },
            ) : null,
          ),
          // Anggota tim
          if (auth.teamMembers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.people_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text('Anggota (${auth.teamMembers.length})', style: _settingsSectionStyle),
                ],
              ),
            ),
          ...auth.teamMembers.map((member) => ListTile(
            dense: true,
            contentPadding: _settingsTilePadding,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: member.role == 'admin' ? Colors.orange : Colors.blue,
              child: Icon(member.role == 'admin' ? Icons.star : Icons.person, color: Colors.white, size: 14),
            ),
            title: Text(member.email ?? member.userId, style: _settingsTitleStyle),
            subtitle: Text(member.role == 'admin' ? 'Admin' : 'Anggota', style: _settingsSubtitleStyle),
          )),
          // Keluar tim
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: OutlinedButton.icon(
              onPressed: () => _showLeaveTeamDialog(context, auth),
              icon: const Icon(Icons.exit_to_app, size: 16),
              label: const Text('Keluar Tim'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
            ),
          ),
        ] else ...[
          // Belum punya tim
          if (isTeamAdmin)
            ListTile(
              dense: true,
              contentPadding: _settingsTilePadding,
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Buat Tim Baru', style: _settingsTitleStyle),
              onTap: () => _showCreateTeamDialog(context, auth),
            ),
          ListTile(
            dense: true,
            contentPadding: _settingsTilePadding,
            leading: const Icon(Icons.group_add_outlined),
            title: const Text('Gabung Tim', style: _settingsTitleStyle),
            subtitle: const Text('Masukkan kode invite', style: _settingsSubtitleStyle),
            onTap: () => _showJoinTeamDialog(context, auth),
          ),
        ],
      ],
    );
  }

  void _showCreateTeamDialog(BuildContext context, AuthProvider auth) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buat Tim Baru'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Nama Tim', hintText: 'Contoh: Tim Gudang'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isNotEmpty) {
                await auth.createTeam(nameCtrl.text.trim());
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Tim berhasil dibuat: ${auth.currentTeam?.name ?? ''}')),
                );
              }
            },
            child: const Text('Buat'),
          ),
        ],
      ),
    );
  }

  void _showJoinTeamDialog(BuildContext context, AuthProvider auth) {
    final codeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gabung Tim'),
        content: TextField(
          controller: codeCtrl,
          decoration: const InputDecoration(labelText: 'Kode Invite', hintText: 'Contoh: ABC123'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () async {
              if (codeCtrl.text.trim().isNotEmpty) {
                await auth.joinTeam(codeCtrl.text.trim().toUpperCase());
                if (!ctx.mounted) return;
                if (auth.error == null && auth.hasTeam) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Berhasil gabung tim: ${auth.currentTeam?.name ?? ''}')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(auth.error ?? 'Gagal gabung tim')),
                  );
                }
              }
            },
            child: const Text('Gabung'),
          ),
        ],
      ),
    );
  }

  void _showLeaveTeamDialog(BuildContext context, AuthProvider auth) {
    final isAdmin = auth.isAdmin;
    final memberCount = auth.teamMembers.where((m) => m.role != 'admin').length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar dari Tim'),
        content: Text(isAdmin
            ? (memberCount > 0
                ? 'Keluarkan semua anggota tim terlebih dahulu sebelum keluar.'
                : 'Tim akan dibubarkan karena kamu satu-satunya anggota. Lanjutkan?')
            : 'Kamu akan keluar dari tim "${auth.currentTeam?.name ?? ''}". Tampilan akan kembali ke data pribadimu. Lanjutkan?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await auth.leaveTeam();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(auth.error == null
                    ? (isAdmin && memberCount == 0 ? 'Tim berhasil dibubarkan' : 'Berhasil keluar dari tim')
                    : auth.error!)),
              );
            },
            child: const Text('Keluar Tim'),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 3. SETTINGS SECTION (toggles)
// ────────────────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  const _SettingsSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (_, settings, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 2),
              child: Text('Pengaturan', style: _settingsSectionStyle),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: _settingsTilePadding,
              secondary: const Icon(Icons.volume_up_outlined),
              title: const Text('Suara Scan', style: _settingsTitleStyle),
              subtitle: const Text('Putar suara saat scan berhasil', style: _settingsSubtitleStyle),
              value: settings.soundEnabled,
              onChanged: (v) => settings.setSoundEnabled(v),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: _settingsTilePadding,
              secondary: const Icon(Icons.vibration_outlined),
              title: const Text('Getar', style: _settingsTitleStyle),
              subtitle: const Text('Getaran saat scan', style: _settingsSubtitleStyle),
              value: settings.vibrationEnabled,
              onChanged: (v) => settings.setVibrationEnabled(v),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: _settingsTilePadding,
              secondary: const Icon(Icons.screen_lock_portrait_outlined),
              title: const Text('Layar Tetap Nyala', style: _settingsTitleStyle),
              subtitle: const Text('Cegah layar mati saat di halaman scan', style: _settingsSubtitleStyle),
              value: settings.wakelockEnabled,
              onChanged: (v) => settings.setWakelockEnabled(v),
            ),
            ListTile(
              dense: true,
              contentPadding: _settingsTilePadding,
              leading: const Icon(Icons.dark_mode_outlined),
              title: const Text('Tema', style: _settingsTitleStyle),
              subtitle: Text(_darkModeLabel(settings.darkMode), style: _settingsSubtitleStyle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showDarkModePicker(context, settings),
            ),
            // Photo compression toggle (membership only)
            Consumer2<AuthProvider, SubscriptionProvider>(
              builder: (_, auth, sub, _) {
                final isMember = sub.currentTier != StorageTier.free || auth.isTeamMember;
                if (!isMember) return const SizedBox.shrink();
                return SwitchListTile(
                  dense: true,
                  contentPadding: _settingsTilePadding,
                  secondary: const Icon(Icons.compress_outlined),
                  title: const Text('Kompres Foto', style: _settingsTitleStyle),
                  subtitle: const Text('Perkecil ukuran foto saat scan & update', style: _settingsSubtitleStyle),
                  value: settings.compressPhoto,
                  onChanged: (v) => settings.setCompressPhoto(v),
                );
              },
            ),
          ],
        );
      },
    );
  }

  String _darkModeLabel(String mode) {
    switch (mode) {
      case 'light':
        return 'Terang';
      case 'dark':
        return 'Gelap';
      default:
        return 'Ikuti Sistem';
    }
  }

  void _showDarkModePicker(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pilih Tema'),
        children: [
          SimpleDialogOption(
            onPressed: () { settings.setDarkMode('system'); Navigator.pop(ctx); },
            child: Row(
              children: [
                Icon(settings.darkMode == 'system' ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: AppTheme.primaryColor),
                const SizedBox(width: 12),
                const Text('Ikuti Sistem'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () { settings.setDarkMode('light'); Navigator.pop(ctx); },
            child: Row(
              children: [
                Icon(settings.darkMode == 'light' ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: AppTheme.primaryColor),
                const SizedBox(width: 12),
                const Text('Terang'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () { settings.setDarkMode('dark'); Navigator.pop(ctx); },
            child: Row(
              children: [
                Icon(settings.darkMode == 'dark' ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: AppTheme.primaryColor),
                const SizedBox(width: 12),
                const Text('Gelap'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// 4. SYNC SECTION
// ────────────────────────────────────────────────────────────

class _SyncSection extends StatelessWidget {
  final AuthProvider auth;
  const _SyncSection({required this.auth});

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = auth.isLoggedIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Text('Backup & Sync', style: _settingsSectionStyle),
        ),
        ListTile(
          dense: true,
          contentPadding: _settingsTilePadding,
          leading: Icon(
            isLoggedIn ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            color: isLoggedIn ? Colors.green : Colors.grey,
          ),
          title: Text(isLoggedIn ? 'Terkoneksi ke Cloud' : 'Belum Login', style: _settingsTitleStyle),
          subtitle: Text(isLoggedIn
              ? 'Data tersinkronisasi ke cloud'
              : 'Login untuk backup & sync otomatis', style: _settingsSubtitleStyle),
        ),
        if (isLoggedIn) ...[
          ListTile(
            dense: true,
            contentPadding: _settingsTilePadding,
            leading: const Icon(Icons.upload_outlined),
            title: const Text('Push Data & Foto ke Cloud', style: _settingsTitleStyle),
            subtitle: const Text('Upload data scan dan foto yang belum sync', style: _settingsSubtitleStyle),
            onTap: () async {
              try {
                // Re-enqueue foto yang belum sync (local path, bukan cloud URL)
                final db = DatabaseHelper.instance;
                final userId = SupabaseService().currentUser?.id;
                final syncQueue = SyncQueue();
                if (userId != null) {
                  final scans = await db.getAllScans(userId: userId);
                  int reEnqueued = 0;
                  for (final o in scans) {
                    if (o.photoPath != null &&
                        o.photoPath!.isNotEmpty &&
                        !o.photoPath!.startsWith('http') &&
                        File(o.photoPath!).existsSync()) {
                      syncQueue.enqueue(SyncTaskType.uploadPhoto, {
                        'local_path': o.photoPath,
                        'user_id': userId,
                        'resi': o.resi,
                        'cloud_filename': '$userId/${o.scannedAt.millisecondsSinceEpoch}.jpg',
                      });
                      reEnqueued++;
                    }
                  }
                  // Also fix scans in Supabase where photo_url is still a local path
                  try {
                    final client = SupabaseService().client;
                    if (client != null) {
                      final badScans = await client
                          .from('scans')
                          .select('resi,photo_url')
                          .eq('user_id', userId)
                          .like('photo_url', '/%');
                      for (final s in badScans) {
                        final resi = s['resi'] as String;
                        // Find matching local order with cloud URL
                        final match = scans.where((o) => o.resi == resi && o.photoPath != null && o.photoPath!.startsWith('http')).firstOrNull;
                        if (match != null) {
                          await client.from('scans').update({'photo_url': match.photoPath}).eq('resi', resi);
                          reEnqueued++;
                        }
                      }
                    }
                  } catch (e) {
                    debugPrint('[Settings] Fix Supabase photo_url error: $e');
                  }
                  if (reEnqueued > 0) {
                    debugPrint('[Settings] Re-enqueued $reEnqueued photos for upload');
                  }
                }
                await syncQueue.processPending();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Push data & foto selesai'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal push: $e')),
                  );
                }
              }
            },
          ),
          ListTile(
            dense: true,
            contentPadding: _settingsTilePadding,
            leading: const Icon(Icons.download_outlined),
            title: const Text('Pull Data dari Cloud', style: _settingsTitleStyle),
            subtitle: const Text('Download data scan & foto dari cloud ke lokal', style: _settingsSubtitleStyle),
            onTap: () async {
              try {
                await context.read<AuthProvider>().syncOnLogin();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pull data selesai'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal pull: $e')),
                  );
                }
              }
            },
          ),
          const Divider(height: 32),
          // Debug: Clear all data
          ListTile(
            dense: true,
            contentPadding: _settingsTilePadding,
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Kosongkan Semua Data (Debug)', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            subtitle: const Text('Hapus semua data scan lokal & cloud', style: _settingsSubtitleStyle),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Hapus Semua Data?'),
                  content: const Text('Semua data scan (lokal & cloud) akan dihapus permanen. Tidak bisa dikembalikan!'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (confirmed != true) return;
              try {
                final userId = SupabaseService().currentUser?.id;
                // Clear local DB
                final db = DatabaseHelper.instance;
                await db.deleteAllScans();
                // Clear Supabase
                final client = SupabaseService().client;
                if (client != null && userId != null) {
                  // 1. Get all photo URLs for this user before deleting scans
                  final userScans = await client.from('scans').select('id, photo_url').eq('user_id', userId);
                  
                  // 2. Delete scan_categories
                  for (final s in userScans) {
                    await client.from('scan_categories').delete().eq('scan_id', s['id']);
                  }
                  
                  // 3. Delete scans
                  await client.from('scans').delete().eq('user_id', userId);
                  
                  // 4. Delete photos from Storage
                  try {
                    final storage = client.storage.from('scan-photos');
                    // List all files in user's folder
                    final files = await storage.list(path: userId);
                    if (files.isNotEmpty) {
                      final filePaths = files.map((f) => '$userId/${f.name}').toList();
                      await storage.remove(filePaths);
                      debugPrint('[Settings] Deleted ${filePaths.length} photos from storage for user $userId');
                    }
                  } catch (e) {
                    debugPrint('[Settings] Failed to delete storage photos: $e');
                  }
                  
                  await client.from('user_subscriptions').update({'cycle_used': 0}).eq('user_id', userId);
                }
                // Refresh providers
                if (context.mounted) {
                  context.read<HistoryProvider>().refresh();
                  context.read<ScanProvider>().loadCounts();
                  context.read<StatsProvider>().loadStats();
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Semua data berhasil dihapus'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal hapus: $e')),
                  );
                }
              }
            },
          ),
        ],
      ],
    );
  }
}
