import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../services/quota_service.dart';
import 'subscription_provider.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  @override
  void initState() {
    super.initState();
    context.read<SubscriptionProvider>().loadStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Langganan'),
      ),
      body: Consumer<SubscriptionProvider>(
        builder: (_, provider, _) => SingleChildScrollView(
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
                          '${provider.remainingFree} dari ${QuotaService.freeQuota} scan tersisa',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: provider.totalScanned / QuotaService.freeQuota,
                          backgroundColor: Colors.grey[300],
                          color: provider.remainingFree > 10
                              ? AppTheme.successColor
                              : AppTheme.dangerColor,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
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
                  text: 'Scan tanpa batas',
                ),
                const _FeatureRow(
                  icon: Icons.file_download_outlined,
                  text: 'Export CSV',
                ),
                const _FeatureRow(
                  icon: Icons.bar_chart,
                  text: 'Statistik lengkap',
                ),
                const _FeatureRow(
                  icon: Icons.support_agent,
                  text: 'Prioritas support',
                ),

                const SizedBox(height: 24),

                // Pricing cards
                _PricingCard(
                  title: 'Bulanan',
                  price: 'Rp 25.000',
                  period: '/bulan',
                  onTap: () => _handlePurchase(provider),
                  isPrimary: false,
                ),
                const SizedBox(height: 12),
                _PricingCard(
                  title: 'Tahunan',
                  price: 'Rp 200.000',
                  period: '/tahun',
                  badge: 'Hemat 33%',
                  onTap: () => _handlePurchase(provider),
                  isPrimary: true,
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

  void _handlePurchase(SubscriptionProvider provider) {
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
