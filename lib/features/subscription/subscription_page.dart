import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/quota_service.dart';
import '../auth/auth_provider.dart';
import '../auth/login_dialog.dart';
import 'subscription_provider.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  late final AuthProvider _authProvider;

  String _fmtDate(DateTime dt) {
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
        return Scaffold(
        appBar: AppBar(
          title: const Text('Langganan'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Status card
              Consumer<AuthProvider>(
                builder: (_, auth, _) {
                  final isTeam = provider.currentTier == StorageTier.unlimited;
                  final isPaid = provider.isPro || isTeam;
                  final iconColor = isPaid ? Colors.amber : Colors.grey;
                  final textColor = isPaid ? Colors.white : null;
                  final subColor = isPaid ? Colors.white70 : null;

                  // Shared content for both paid and free cards
                  final cardContent = Column(
                    children: [
                      Icon(
                        isTeam ? Icons.groups : provider.isPro ? Icons.workspace_premium : Icons.lock_outline,
                        size: 48,
                        color: iconColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isTeam ? 'TEAM' : provider.tierName.toUpperCase(),
                        style: TextStyle(
                          fontSize: AppTheme.sectionTitleSize,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (isPaid && !provider.subscriptionActive) ...[
                        Text(
                          'Paket tidak aktif (expired)',
                          style: TextStyle(
                            fontSize: AppTheme.cardTitleSize,
                            fontWeight: FontWeight.w600,
                            color: isPaid ? Colors.orangeAccent : Colors.red,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Perpanjang untuk scan lagi',
                          style: TextStyle(
                            fontSize: AppTheme.captionSize,
                            color: isPaid ? Colors.white70 : Colors.grey[600],
                          ),
                        ),
                      ] else if (isTeam && auth.hasTeam) ...[
                        Text(
                          auth.currentTeam!.name,
                          style: const TextStyle(
                            fontSize: AppTheme.cardTitleSize,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${auth.teamMembers.length} anggota • Scan tanpa batas',
                          style: TextStyle(fontSize: AppTheme.captionSize, color: subColor),
                        ),
                      ] else ...[
                        Text(
                          provider.cycleAllowance < 0
                              ? 'Scan tanpa batas'
                              : '${provider.cycleUsed} / ${provider.cycleAllowance} scan di periode aktif',
                          style: TextStyle(fontSize: AppTheme.captionSize, color: subColor),
                        ),
                      ],
                      if (provider.activeFrom != null && provider.activeUntil != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Aktif: ${_fmtDate(provider.activeFrom!)} - ${_fmtDate(provider.activeUntil!)}',
                          style: TextStyle(
                            fontSize: AppTheme.captionSize,
                            color: isPaid ? Colors.white70 : Colors.grey[600],
                          ),
                        ),
                      ],
                      if (isTeam) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: 1,
                          backgroundColor: Colors.white24,
                          color: Colors.white,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Unlimited scan tersisa di periode ini',
                          style: TextStyle(
                            fontSize: AppTheme.microSize,
                            color: Colors.white70,
                          ),
                        ),
                      ] else if (provider.cycleAllowance >= 0) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: provider.cycleAllowance > 0
                              ? (provider.cycleUsed / provider.cycleAllowance).clamp(0.0, 1.0)
                              : 0,
                          backgroundColor: isPaid ? Colors.white24 : Colors.grey[300],
                          color: provider.remainingFree > 20
                              ? (isPaid ? Colors.white : AppTheme.successColor)
                              : AppTheme.dangerColor,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${provider.remainingFree >= 0 ? provider.remainingFree : 0} scan tersisa di periode ini',
                          style: TextStyle(
                            fontSize: AppTheme.microSize,
                            color: isPaid ? Colors.white70 : Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  );

                  return SizedBox(
                    width: double.infinity,
                    child: Card(
                      color: isPaid
                          ? AppTheme.primaryColor
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: cardContent,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              if (provider.currentTier == StorageTier.pro) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.workspace_premium, color: Colors.amber),
                            SizedBox(width: 8),
                            Text(
                              'Fitur Paket Pro',
                              style: TextStyle(
                                fontSize: AppTheme.sectionTitleSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _FeatureRow(
                          icon: Icons.qr_code_scanner,
                          title: '5.000 Scan / Bulan',
                          subtitle: 'Kuota scan besar untuk kebutuhan profesional.',
                        ),
                        _FeatureRow(
                          icon: Icons.group_add_outlined,
                          title: 'Gabung Tim',
                          subtitle: 'Bisa bergabung ke tim yang sudah ada via kode invite.',
                        ),
                        _FeatureRow(
                          icon: Icons.cloud_sync_outlined,
                          title: 'Backup & Sync Cloud',
                          subtitle: 'Data scan tersimpan lokal dan bisa disinkronkan ke cloud.',
                        ),
                        _FeatureRow(
                          icon: Icons.file_download_outlined,
                          title: 'Export Riwayat',
                          subtitle: 'Export data scan ke XLSX/CSV untuk kebutuhan laporan.',
                        ),
                        _FeatureRow(
                          icon: Icons.copy_all_outlined,
                          title: 'Copy Resi Cepat',
                          subtitle: 'Nomor resi di riwayat bisa disalin dengan mudah.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (provider.currentTier == StorageTier.basic) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.bolt, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              'Fitur Paket Basic',
                              style: TextStyle(
                                fontSize: AppTheme.sectionTitleSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _FeatureRow(
                          icon: Icons.qr_code_scanner,
                          title: '1.000 Scan / Bulan',
                          subtitle: 'Kuota scan untuk kebutuhan harian.',
                        ),
                        _FeatureRow(
                          icon: Icons.group_add_outlined,
                          title: 'Gabung Tim',
                          subtitle: 'Bisa bergabung ke tim yang sudah ada via kode invite.',
                        ),
                        _FeatureRow(
                          icon: Icons.cloud_sync_outlined,
                          title: 'Backup & Sync Cloud',
                          subtitle: 'Data scan tersimpan lokal dan bisa disinkronkan ke cloud.',
                        ),
                        _FeatureRow(
                          icon: Icons.file_download_outlined,
                          title: 'Export Riwayat',
                          subtitle: 'Export data scan ke XLSX/CSV untuk kebutuhan laporan.',
                        ),
                        _FeatureRow(
                          icon: Icons.copy_all_outlined,
                          title: 'Copy Resi Cepat',
                          subtitle: 'Nomor resi di riwayat bisa disalin dengan mudah.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (provider.currentTier == StorageTier.unlimited) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.groups_rounded, color: AppTheme.primaryColor),
                            SizedBox(width: 8),
                            Text(
                              'Fitur Paket Team',
                              style: TextStyle(
                                fontSize: AppTheme.sectionTitleSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _FeatureRow(
                          icon: Icons.all_inclusive,
                          title: 'Unlimited Scan',
                          subtitle: 'Scan resi tanpa batas kuota bulanan.',
                        ),
                        _FeatureRow(
                          icon: Icons.group_add_outlined,
                          title: 'Kelola Anggota Tim',
                          subtitle: 'Buat tim, bagikan kode invite, dan lihat daftar anggota.',
                        ),
                        _FeatureRow(
                          icon: Icons.category_outlined,
                          title: 'Kategori Wajib',
                          subtitle: 'Scan tersimpan rapi per kategori untuk memisahkan alur kerja.',
                        ),
                        _FeatureRow(
                          icon: Icons.cloud_sync_outlined,
                          title: 'Backup & Sync Cloud',
                          subtitle: 'Data scan tersimpan lokal dan bisa disinkronkan ke cloud.',
                        ),
                        _FeatureRow(
                          icon: Icons.file_download_outlined,
                          title: 'Export Riwayat',
                          subtitle: 'Export data scan ke XLSX/CSV untuk kebutuhan laporan.',
                        ),
                        _FeatureRow(
                          icon: Icons.copy_all_outlined,
                          title: 'Copy Resi Cepat',
                          subtitle: 'Nomor resi di riwayat bisa disalin dengan mudah.',
                        ),
                        _FeatureRow(
                          icon: Icons.support_agent,
                          title: 'Dukungan Prioritas',
                          subtitle: 'Mendapat prioritas dalam bantuan dan pemecahan masalah.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],


              const SizedBox(height: 24),

              if (provider.purchaseError != null &&
                  !provider.purchaseError!.contains('Produk tidak ditemukan')) ...[
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
                            style: const TextStyle(color: Colors.red, fontSize: AppTheme.microSize),
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
                    fontSize: AppTheme.heroSize,
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
                // Tombol upgrade untuk Basic dan Pro
                if (provider.currentTier == StorageTier.basic || provider.currentTier == StorageTier.pro) ...[
                  const SizedBox(height: 12),
                  _UpgradeCard(
                    currentTier: provider.currentTier,
                    remainingScans: provider.remainingFree,
                    onUpgrade: _handlePurchase,
                  ),
                ],
              ],

              const SizedBox(height: 24),
            ],
          ),
        ),
      );
      },
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
                                fontSize: AppTheme.cardTitleSize,
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
                                    fontSize: AppTheme.microSize,
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
                              fontSize: AppTheme.microSize,
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
                      fontSize: AppTheme.heroSize,
                      fontWeight: FontWeight.bold,
                      color: isPrimary ? AppTheme.primaryColor : null,
                    ),
                  ),
                  Text(
                    period,
                    style: const TextStyle(
                      fontSize: AppTheme.microSize,
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
                          style: const TextStyle(fontSize: AppTheme.microSize),
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

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppTheme.primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppTheme.cardTitleSize),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: AppTheme.microSize, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTheme.cardTitleSize),
                ),
            ],
          ),
          if (carryNote.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(carryNote, style: TextStyle(fontSize: AppTheme.microSize, color: Colors.amber.shade800)),
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
              style: TextStyle(fontSize: AppTheme.captionSize, color: Colors.grey[700]),
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
