import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../auth/auth_provider.dart';
import '../auth/login_dialog.dart';
import 'subscription_provider.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    context.read<SubscriptionProvider>().loadStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SubscriptionProvider>(
      builder: (_, provider, __) => Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: const Text('Langganan'),
          actions: [
            if (provider.isPro)
              IconButton(
                icon: const Icon(Icons.menu),
                tooltip: 'Menu Tim',
                onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              ),
          ],
        ),
        endDrawer: provider.isPro ? _buildTeamDrawer(context) : null,
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
                        provider.isPro ? 'PRO AKTIF' : 'GRATIS',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: provider.isPro ? Colors.white : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!provider.isPro) ...[
                        Text(
                          '${provider.storageUsed} / ${provider.storageTotal} terpakai',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: provider.storageFraction,
                          backgroundColor: Colors.grey[300],
                          color: provider.storageFraction < 0.7
                              ? AppTheme.successColor
                              : AppTheme.dangerColor,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${provider.remainingFree > 0 ? provider.remainingFree : 0} scan tersisa',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ] else
                        const Text(
                          'Scan tanpa batas!',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Cloud Sync Status
              Consumer<AuthProvider>(
                builder: (_, auth, __) {
                  if (auth.isLoggedIn) {
                    return Card(
                      color: Colors.green.withAlpha(25),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.green,
                          child: Icon(Icons.cloud_done, color: Colors.white),
                        ),
                        title: const Text('Tersambung ke Cloud'),
                        subtitle: const Text('Data scan tersimpan di Supabase'),
                        trailing: TextButton(
                          onPressed: () => auth.signOut(),
                          child: const Text('Logout'),
                        ),
                      ),
                    );
                  }
                  return Card(
                    color: Colors.orange.withAlpha(25),
                    child: ListTile(
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

              const SizedBox(height: 24),

              if (!provider.isPro) ...[
                // Pro features
                const Text(
                  'Upgrade ke Pro',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                const _FeatureRow(
                  icon: Icons.all_inclusive,
                  text: 'Scan resi unlimited',
                ),
                const _FeatureRow(
                  icon: Icons.cloud_sync,
                  text: 'Sinkronisasi Cloud',
                ),
                const _FeatureRow(
                  icon: Icons.download,
                  text: 'Export CSV',
                ),
                const _FeatureRow(
                  icon: Icons.backup,
                  text: 'Backup & restore',
                ),
                const _FeatureRow(
                  icon: Icons.devices,
                  text: 'Akses multi perangkat',
                ),
                const _FeatureRow(
                  icon: Icons.block,
                  text: 'Tanpa iklan',
                ),

                const SizedBox(height: 24),

                // Pricing Cards - Storage tiers
                _PricingCard(
                  title: 'Basic',
                  price: 'Rp 15.000',
                  period: '/bulan',
                  badge: '2 GB',
                  onTap: () => _handlePurchase(provider),
                  isPrimary: false,
                ),
                const SizedBox(height: 12),
                _PricingCard(
                  title: 'Pro',
                  price: 'Rp 25.000',
                  period: '/bulan',
                  badge: '10 GB',
                  onTap: () => _handlePurchase(provider),
                  isPrimary: true,
                ),
                const SizedBox(height: 12),
                _PricingCard(
                  title: 'Unlimited',
                  price: 'Rp 50.000',
                  period: '/bulan',
                  badge: '∞',
                  onTap: () => _handlePurchase(provider),
                  isPrimary: false,
                ),

                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => provider.restorePurchase(),
                  child: const Text('Restore Purchase'),
                ),
              ],

              // Debug toggle (remove in production)
              const SizedBox(height: 32),
              const Divider(),
              TextButton.icon(
                onPressed: () => provider.toggleProDebug(),
                icon: const Icon(Icons.bug_report, size: 16),
                label: Text(
                  provider.isPro ? 'Debug: Set Free' : 'Debug: Set Pro',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeamDrawer(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (_, auth, __) => Drawer(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tim',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
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
                ] else ...[
                  FilledButton(
                    onPressed: () => _showCreateTeamDialog(context, auth),
                    child: const Text('Buat Tim Baru'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _showJoinTeamDialog(context, auth),
                    child: const Text('Gabung Tim'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handlePurchase(SubscriptionProvider provider) {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      showLoginDialog(context, onSuccess: () => _showPurchaseDialog());
      return;
    }
    _showPurchaseDialog();
  }

  void _showPurchaseDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pembelian'),
        content: const Text(
          'Fitur In-App Purchase akan tersedia setelah setup di Google Play Console / App Store Connect.\n\nUntuk testing, gunakan tombol Debug di bawah.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
                Navigator.pop(dialogCtx);
              }
            },
            child: const Text('Buat'),
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
                Navigator.pop(dialogCtx);
              }
            },
            child: const Text('Gabung'),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.successColor, size: 22),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  final String title;
  final String price;
  final String period;
  final String? badge;
  final VoidCallback onTap;
  final bool isPrimary;

  const _PricingCard({
    required this.title,
    required this.price,
    required this.period,
    this.badge,
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
          padding: const EdgeInsets.all(16),
          child: Row(
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
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          price,
                          style: TextStyle(
                            fontSize: 20,
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
        ),
      ),
    );
  }
}
