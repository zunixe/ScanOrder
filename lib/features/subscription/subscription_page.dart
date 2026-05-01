import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/supabase/supabase_service.dart';
import '../../services/quota_service.dart';
import '../auth/auth_provider.dart';
import '../auth/login_dialog.dart';
import '../contact/contact_page.dart';
import 'subscription_provider.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final AuthProvider _authProvider;

  String _fmtDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d/$m/$y';
  }

  String _fmtMemberDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d/$m/$y';
  }

  @override
  void initState() {
    super.initState();
    context.read<SubscriptionProvider>().loadStatus();
    context.read<SubscriptionProvider>().initializeIap();
    // Reload subscription status when auth changes (e.g. after login)
    _authProvider = context.read<AuthProvider>();
    _authProvider.addListener(_onAuthChange);
  }

  void _onAuthChange() {
    context.read<SubscriptionProvider>().loadStatus();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SubscriptionProvider>(
      builder: (_, provider, _) {
        final canManageTeam = provider.currentTier == StorageTier.unlimited;
        return Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: const Text('Langganan'),
          leading: canManageTeam
              ? IconButton(
                  icon: const Icon(Icons.groups_rounded),
                  tooltip: 'Menu Tim',
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                )
              : null,
        ),
        drawer: canManageTeam ? _buildTeamDrawer(context) : null,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Status card
              Card(
                color: provider.isPro
                    ? AppTheme.primaryColor
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        provider.isPro
                            ? Icons.workspace_premium
                            : Icons.lock_outline,
                        size: 48,
                        color: provider.isPro ? Colors.amber : Colors.grey,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        provider.tierName.toUpperCase(),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: provider.isPro ? Colors.white : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        provider.cycleAllowance < 0
                            ? 'Scan tanpa batas'
                            : '${provider.cycleUsed} / ${provider.cycleAllowance} scan di periode aktif',
                        style: TextStyle(
                          fontSize: 14,
                          color: provider.isPro ? Colors.white70 : null,
                        ),
                      ),
                      if (provider.activeFrom != null && provider.activeUntil != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Aktif: ${_fmtDate(provider.activeFrom!)} - ${_fmtDate(provider.activeUntil!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: provider.isPro ? Colors.white70 : Colors.grey[600],
                          ),
                        ),
                      ],
                      if (provider.cycleAllowance >= 0) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: provider.cycleAllowance > 0
                              ? (provider.cycleUsed / provider.cycleAllowance).clamp(0.0, 1.0)
                              : 0,
                          backgroundColor: provider.isPro ? Colors.white24 : Colors.grey[300],
                          color: provider.remainingFree > 20
                              ? (provider.isPro ? Colors.white : AppTheme.successColor)
                              : AppTheme.dangerColor,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${provider.remainingFree >= 0 ? provider.remainingFree : 0} scan tersisa di periode ini',
                          style: TextStyle(
                            fontSize: 12,
                            color: provider.isPro ? Colors.white70 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Cloud Sync Status & User Profile
              Consumer<AuthProvider>(
                builder: (_, auth, _) {
                  if (auth.isLoggedIn) {
                    final user = SupabaseService().currentUser;
                    final email = user?.email ?? '-';
                    return Card(
                      color: Colors.green.withAlpha(25),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primaryColor,
                                child: Text(
                                  email.isNotEmpty ? email[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(email, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: const Text('Tersambung ke Cloud'),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                tooltip: 'Edit Profil',
                                onPressed: () => _showProfileDialog(context, auth, email),
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                ),
                                onPressed: () => auth.signOut(),
                                icon: const Icon(Icons.logout, size: 16),
                                label: const Text('Logout'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Card(
                    color: Colors.orange.withAlpha(25),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      leading: const CircleAvatar(
                        backgroundColor: Colors.orange,
                        child: Icon(Icons.cloud_off, color: Colors.white),
                      ),
                      title: const Text('Mode Lokal'),
                      subtitle: const Text('Login untuk backup & sinkronisasi'),
                      trailing: FilledButton(
                        onPressed: () => showLoginDialog(context),
                        child: const Text('Login'),
                      ),
                    ),
                  );
                },
              ),

              // Status tim — visible untuk semua user login
              Consumer<AuthProvider>(
                builder: (_, auth, _) {
                  if (!auth.isLoggedIn) return const SizedBox.shrink();
                  if (auth.hasTeam && provider.currentTier != StorageTier.unlimited) {
                    // Anggota tim biasa (bukan Unlimited): tampilkan info tim + tombol keluar
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Card(
                        color: Colors.blue.withAlpha(20),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const CircleAvatar(
                                  backgroundColor: Colors.blue,
                                  child: Icon(Icons.groups, color: Colors.white),
                                ),
                                title: Text(auth.currentTeam!.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: const Text('Anggota Tim • Scan Unlimited'),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                  ),
                                  onPressed: () => _showLeaveTeamDialog(context, auth),
                                  icon: const Icon(Icons.exit_to_app),
                                  label: const Text('Keluar Tim'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  if (!auth.hasTeam) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showJoinTeamDialog(context, auth),
                          icon: const Icon(Icons.group_add_outlined),
                          label: const Text('Gabung Tim'),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              const SizedBox(height: 24),

              if (provider.purchaseError != null) ...[
                Card(
                  color: Colors.red.withAlpha(20),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            provider.purchaseError!,
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (!provider.isPro) ...[
                const Text(
                  'Pilih Paket',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Dynamic pricing cards from packages table
                ...provider.packages
                    .where((pkg) => pkg.id != 'free')
                    .map((pkg) {
                  final tier = StorageTier.values.firstWhere(
                    (t) => t.name == pkg.id,
                    orElse: () => StorageTier.free,
                  );
                  final subtitle = pkg.scanLimit == 0
                      ? 'Unlimited scan'
                      : '${pkg.scanLimit >= 1000 ? '${pkg.scanLimit ~/ 1000}.${(pkg.scanLimit % 1000).toString().padLeft(3, '0').replaceAll(RegExp(r'0+\$'), '')}' : pkg.scanLimit} scan / bulan';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PricingCard(
                      title: pkg.name,
                      subtitle: subtitle,
                      price: pkg.priceDisplay,
                      period: '/bulan',
                      badge: pkg.scanLimitDisplay,
                      features: pkg.features,
                      onTap: () => _handlePurchase(tier),
                      isPrimary: pkg.isPopular,
                    ),
                  );
                }),

              ] else ...[
                // Info paket aktif
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primaryColor,
                      child: Icon(
                        provider.currentTier == StorageTier.unlimited
                            ? Icons.groups
                            : Icons.workspace_premium,
                        color: Colors.white,
                      ),
                    ),
                    title: Text('Paket ${provider.tierName} Aktif'),
                    subtitle: Text(
                      provider.subscriptionActive
                          ? 'Aktif ${provider.activeFrom != null ? _fmtDate(provider.activeFrom!) : '-'} s/d ${provider.activeUntil != null ? _fmtDate(provider.activeUntil!) : '-'}'
                          : 'Paket tidak aktif (expired). Perpanjang untuk scan lagi.',
                    ),
                  ),
                ),
                // Tombol upgrade untuk Basic dan Pro
                if (provider.currentTier == StorageTier.basic || provider.currentTier == StorageTier.pro) ...[
                  const SizedBox(height: 12),
                  _UpgradeCard(
                    currentTier: provider.currentTier,
                    remainingScans: provider.remainingFree,
                    onUpgrade: _handlePurchase,
                  ),
                ],
                if (canManageTeam) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColor.withAlpha(230),
                          AppTheme.primaryColor.withAlpha(170),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.groups_rounded, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Kelola Tim',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Atur anggota tim dan kode invite dari panel khusus.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.primaryColor,
                          ),
                          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                          icon: const Icon(Icons.menu_open_rounded),
                          label: const Text('Buka Menu Tim'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 24),

              // Hubungi Kami button
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContactPage()),
                  );
                },
                icon: const Icon(Icons.contact_mail),
                label: const Text('Hubungi Kami'),
              ),
            ],
          ),
        ),
      );
      },
    );
  }

  Widget _buildTeamDrawer(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (_, auth, _) => Drawer(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryColor,
                        AppTheme.primaryColor.withAlpha(190),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.white24,
                        child: Icon(Icons.groups_2_rounded, color: Colors.white),
                      ),
                      SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Menu Tim',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Kelola anggota & akses bersama',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (auth.hasTeam) ...[
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Icon(Icons.group, color: Colors.white),
                      ),
                      title: Text(auth.currentTeam!.name),
                      subtitle: Text('Kode invite: ${auth.currentTeam!.inviteCode}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: auth.currentTeam!.inviteCode),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Kode invite disalin')),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: auth.currentTeam!.inviteCode),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Kode invite disalin')),
                      );
                    },
                    icon: const Icon(Icons.share),
                    label: const Text('Salin Kode Invite'),
                  ),
                  const SizedBox(height: 16),
                  // Member list
                  Row(
                    children: [
                      const Icon(Icons.people_outline, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Anggota (${auth.teamMembers.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...auth.teamMembers.map((member) => Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: member.role == 'admin'
                            ? AppTheme.primaryColor
                            : Colors.grey.shade300,
                        radius: 18,
                        child: Icon(
                          member.role == 'admin' ? Icons.star : Icons.person,
                          color: member.role == 'admin' ? Colors.white : Colors.grey.shade700,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        member.email ?? member.userId.substring(0, 8),
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        member.role == 'admin' ? 'Admin' : 'Anggota',
                        style: TextStyle(
                          fontSize: 11,
                          color: member.role == 'admin' ? AppTheme.primaryColor : Colors.grey,
                        ),
                      ),
                      trailing: Text(
                        _fmtMemberDate(member.joinedAt),
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      ),
                    ),
                  )),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        if (!auth.isLoggedIn) {
                          showLoginDialog(context);
                          return;
                        }
                        _showCreateTeamDialog(context, auth);
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Buat Tim Baru'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        if (!auth.isLoggedIn) {
                          showLoginDialog(context);
                          return;
                        }
                        _showJoinTeamDialog(context, auth);
                      },
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('Gabung Tim'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handlePurchase(StorageTier tier) {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      showLoginDialog(context, onSuccess: () => _startPurchase(tier));
      return;
    }
    _startPurchase(tier);
  }

  Future<void> _startPurchase(StorageTier tier) async {
    await context.read<SubscriptionProvider>().purchaseTier(tier);
  }

  void _showCreateTeamDialog(BuildContext ctx, AuthProvider auth) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Buat Tim Baru'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Nama Tim',
            hintText: 'Contoh: Gudang A',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isNotEmpty) {
                await auth.createTeam(nameCtrl.text.trim());
                if (!dialogCtx.mounted) return;
                if (auth.error == null && auth.hasTeam) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Tim berhasil dibuat: ${auth.currentTeam?.name ?? ''}'),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(auth.error ?? 'Gagal membuat tim')),
                  );
                }
              }
            },
            child: const Text('Buat'),
          ),
        ],
      ),
    );
  }

  void _showLeaveTeamDialog(BuildContext ctx, AuthProvider auth) {
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Keluar dari Tim'),
        content: Text(
          'Kamu akan keluar dari tim "${auth.currentTeam?.name ?? ''}". '
          'Quota scan akan kembali ke paket pribadimu. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await auth.leaveTeam();
              if (!dialogCtx.mounted) return;
              Navigator.pop(dialogCtx);
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text(
                    auth.error == null
                        ? 'Berhasil keluar dari tim'
                        : auth.error!,
                  ),
                ),
              );
            },
            child: const Text('Keluar Tim'),
          ),
        ],
      ),
    );
  }

  void _showJoinTeamDialog(BuildContext ctx, AuthProvider auth) {
    final codeCtrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Gabung Tim'),
        content: TextField(
          controller: codeCtrl,
          decoration: const InputDecoration(
            labelText: 'Kode Invite',
            hintText: 'Contoh: ABC123',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              if (codeCtrl.text.trim().isNotEmpty) {
                await auth.joinTeam(codeCtrl.text.trim().toUpperCase());
                if (!dialogCtx.mounted) return;
                if (auth.error == null && auth.hasTeam) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Berhasil gabung tim: ${auth.currentTeam?.name ?? ''}'),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(ctx).showSnackBar(
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

  void _showProfileDialog(BuildContext ctx, AuthProvider auth, String currentEmail) {
    final emailCtrl = TextEditingController(text: currentEmail);
    final passCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Profil Saya'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Email (read-only, dari Supabase Auth)
              TextField(
                controller: emailCtrl,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                  filled: true,
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Ubah Password',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newPassCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password Baru',
                  prefixIcon: Icon(Icons.lock_outline),
                  hintText: 'Min. 6 karakter',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password Lama (verifikasi)',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Tutup'),
          ),
          FilledButton(
            onPressed: () async {
              final newPass = newPassCtrl.text.trim();
              final oldPass = passCtrl.text.trim();
              if (newPass.isEmpty || newPass.length < 6) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Password baru min. 6 karakter')),
                );
                return;
              }
              if (oldPass.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Masukkan password lama untuk verifikasi')),
                );
                return;
              }
              try {
                final client = SupabaseService().client;
                if (client == null) return;
                // Re-authenticate lalu update password
                await client.auth.signInWithPassword(
                  email: currentEmail,
                  password: oldPass,
                );
                await client.auth.updateUser(
                  UserAttributes(password: newPass),
                );
                if (!dialogCtx.mounted) return;
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Password berhasil diubah')),
                );
              } catch (e) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Gagal: ${e.toString()}')),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}


class _PricingCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String price;
  final String period;
  final String? badge;
  final List<String>? features;
  final VoidCallback onTap;
  final bool isPrimary;

  const _PricingCard({
    required this.title,
    this.subtitle,
    required this.price,
    required this.period,
    this.badge,
    this.features,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isPrimary ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPrimary
            ? BorderSide(color: AppTheme.primaryColor, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (badge != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.warningColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  badge!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: isPrimary ? AppTheme.primaryColor : Colors.grey,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    price,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isPrimary ? AppTheme.primaryColor : null,
                    ),
                  ),
                  Text(
                    period,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              if (features != null && features!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                ...features!.map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 14, color: AppTheme.successColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  final StorageTier currentTier;
  final int remainingScans;
  final void Function(StorageTier) onUpgrade;

  const _UpgradeCard({
    required this.currentTier,
    required this.remainingScans,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final isBasic = currentTier == StorageTier.basic;
    final carryInfo = remainingScans > 0
        ? ' + $remainingScans sisa scan terbawa'
        : '';
    final carryNote = remainingScans > 0
        ? 'Sisa $remainingScans scan periode ini akan ditambahkan ke kuota baru.'
        : '';

    // Opsi upgrade berdasarkan tier saat ini
    final options = isBasic
        ? [
            _UpgradeOption(
              tier: StorageTier.pro,
              name: 'Pro',
              price: 'Rp 99.000',
              scans: '5.000 scan/bulan$carryInfo',
            ),
            _UpgradeOption(
              tier: StorageTier.unlimited,
              name: 'Team',
              price: 'Rp 399.000',
              scans: 'Unlimited scan/bulan',
            ),
          ]
        : [
            _UpgradeOption(
              tier: StorageTier.unlimited,
              name: 'Team',
              price: 'Rp 399.000',
              scans: 'Unlimited scan/bulan',
            ),
          ];

    return Card(
      color: Colors.amber.withAlpha(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.shade300, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.arrow_circle_up_rounded, color: Colors.amber),
                const SizedBox(width: 8),
                const Text(
                  'Upgrade Paket',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
            ],
          ),
          if (carryNote.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(carryNote, style: TextStyle(fontSize: 11, color: Colors.amber.shade800)),
          ],
          const SizedBox(height: 10),
          ...options.map((opt) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade700),
                onPressed: () => onUpgrade(opt.tier),
                icon: const Icon(Icons.upgrade),
                label: Text('Upgrade ke ${opt.name} — ${opt.price}'),
              ),
            ),
          )),
          ...options.map((opt) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              opt.scans,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          )),
        ],
      ),
    ),
  );
  }
}

class _UpgradeOption {
  final StorageTier tier;
  final String name;
  final String price;
  final String scans;
  const _UpgradeOption({
    required this.tier,
    required this.name,
    required this.price,
    required this.scans,
  });
}
