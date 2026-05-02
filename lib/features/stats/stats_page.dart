import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/db/database_helper.dart';
import '../../core/supabase/supabase_service.dart';
import '../../services/quota_service.dart';
import '../../services/sync_queue.dart';
import '../auth/auth_provider.dart';
import '../subscription/subscription_page.dart';
import '../subscription/subscription_provider.dart';
import 'stats_provider.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  @override
  void initState() {
    super.initState();
    context.read<StatsProvider>().loadStats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload stats when page becomes visible (e.g. after leaving team)
    context.read<StatsProvider>().loadStats();
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubscriptionProvider>();
    final isFree = sub.currentTier == StorageTier.free;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistik'),
      ),
      body: Consumer2<StatsProvider, AuthProvider>(
        builder: (_, provider, auth, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary cards — selalu tampil
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      title: 'Total Scan',
                      value: '${provider.totalScans}',
                      icon: Icons.inventory_2_outlined,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Scan Hari Ini',
                      value: '${provider.dailyStats[DateFormat('yyyy-MM-dd').format(DateTime.now())] ?? 0}',
                      icon: Icons.today,
                      color: AppTheme.successColor,
                    ),
                  ),
                ],
              ),

              if (isFree) ...[
                const SizedBox(height: 24),
                _buildLockedSection(context),
              ] else ...[
                const SizedBox(height: 24),

                // Period selector + bar chart
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Scan per Hari',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 7, label: Text('7h')),
                        ButtonSegment(value: 14, label: Text('14h')),
                        ButtonSegment(value: 30, label: Text('30h')),
                      ],
                      selected: {provider.periodDays},
                      onSelectionChanged: (v) => provider.setPeriod(v.first),
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        textStyle: WidgetStatePropertyAll(
                          Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: _DailyBarChart(
                    stats: provider.dailyStats,
                    days: provider.periodDays,
                  ),
                ),

                const SizedBox(height: 24),

                // Marketplace breakdown
                const Text(
                  'Marketplace',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                if (provider.marketplaceStats.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Belum ada data',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else ...[
                  SizedBox(
                    height: 180,
                    child: _MarketplacePieChart(stats: provider.marketplaceStats),
                  ),
                  const SizedBox(height: 12),
                  ...provider.marketplaceStats.entries.map(
                    (e) => _MarketplaceRow(
                      name: e.key,
                      count: e.value,
                      total: provider.totalScans,
                    ),
                  ),
                ],

                // Team member scan stats (Team users only)
                if ((sub.currentTier == StorageTier.unlimited || auth!.isTeamMember) && provider.memberScanStats.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Scan per Anggota Tim',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          ...provider.memberScanStats.entries.map((e) {
                            final total = provider.memberScanStats.values.fold(0, (a, b) => a + b);
                            final pct = total > 0 ? e.value / total : 0.0;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          e.key,
                                          style: const TextStyle(fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        '${e.value} scan',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: pct,
                                      minHeight: 6,
                                      backgroundColor: Colors.grey.shade200,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],

                // Category chart (all tiers with categories)
                if (provider.categoryStats.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Analisa per Kategori',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 180,
                    child: _CategoryPieChart(stats: provider.categoryStats),
                  ),
                  const SizedBox(height: 12),
                  ...provider.categoryStats.entries.map(
                    (e) => _CategoryRow(
                      name: e.key,
                      count: e.value,
                      total: provider.totalScans,
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Storage usage card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.storage,
                              color: AppTheme.primaryColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Penyimpanan',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Table(
                          columnWidths: const {
                            0: FlexColumnWidth(1.2),
                            1: FlexColumnWidth(1),
                            2: FlexColumnWidth(1),
                          },
                          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                          children: [
                            // Header
                            TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text('', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text('Lokal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600]), textAlign: TextAlign.center),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text('Cloud', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600]), textAlign: TextAlign.center),
                                ),
                              ],
                            ),
                            // Database row
                            TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      Icon(Icons.dataset_outlined, size: 16, color: Colors.grey),
                                      const SizedBox(width: 6),
                                      Text('Database', style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Text(
                                    '${provider.formattedDbSize}\n${provider.totalScans} data',
                                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Text(
                                    '${provider.formattedCloudDbSize}\n${provider.syncedScans} data',
                                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                            // Foto row
                            TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      Icon(Icons.photo_library_outlined, size: 16, color: Colors.grey),
                                      const SizedBox(width: 6),
                                      Text('Foto', style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Text(
                                    '${provider.formattedPhotoSize}\n${provider.photoCount} foto',
                                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Text(
                                    '${provider.formattedCloudPhotoSize}\n${provider.syncedPhotos} foto',
                                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                            // Total row
                            TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      Icon(Icons.folder_outlined, size: 16, color: AppTheme.primaryColor),
                                      const SizedBox(width: 6),
                                      Text('Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    provider.formattedTotalSize,
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    '${provider.formattedCloudTotalSize}\n${provider.syncedScans + provider.syncedPhotos} item',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Sync status card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.cloud_sync_outlined,
                              color: AppTheme.primaryColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Status Sync',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _SyncRow(
                          label: 'Data Scan Tersinkron',
                          value: '${provider.syncedScans}',
                          total: provider.totalScans,
                          synced: provider.syncedScans,
                          icon: Icons.dataset_outlined,
                        ),
                        const Divider(height: 16),
                        _SyncRow(
                          label: 'Data Scan Belum Sinkron',
                          value: '${provider.unsyncedScans}',
                          total: provider.totalScans,
                          synced: provider.unsyncedScans,
                          icon: Icons.cloud_off_outlined,
                          isWarning: provider.unsyncedScans > 0,
                        ),
                        const Divider(height: 16),
                        _SyncRow(
                          label: 'Foto Tersinkron ke Cloud',
                          value: '${provider.syncedPhotos}',
                          total: provider.syncedPhotos + provider.unsyncedPhotos,
                          synced: provider.syncedPhotos,
                          icon: Icons.cloud_done_outlined,
                        ),
                        const Divider(height: 16),
                        GestureDetector(
                          onTap: provider.unsyncedPhotos > 0 ? () => _showUnsyncedPhotoDialog(context, provider) : null,
                          child: _SyncRow(
                            label: 'Foto Belum Sinkron',
                            value: '${provider.unsyncedPhotos}',
                            total: provider.syncedPhotos + provider.unsyncedPhotos,
                            synced: provider.unsyncedPhotos,
                            icon: Icons.photo_library_outlined,
                            isWarning: provider.unsyncedPhotos > 0,
                          ),
                        ),
                        const Divider(height: 16),
                        _SyncRow(
                          label: 'Kategori Tersinkron ke Cloud',
                          value: '${provider.syncedCategories}',
                          total: provider.syncedCategories + provider.unsyncedCategories,
                          synced: provider.syncedCategories,
                          icon: Icons.cloud_done_outlined,
                        ),
                        const Divider(height: 16),
                        _SyncRow(
                          label: 'Kategori Belum Sinkron',
                          value: '${provider.unsyncedCategories}',
                          total: provider.syncedCategories + provider.unsyncedCategories,
                          synced: provider.unsyncedCategories,
                          icon: Icons.cloud_off_outlined,
                          isWarning: provider.unsyncedCategories > 0,
                        ),
                        if (provider.pendingQueueCount > 0) ...[
                          const Divider(height: 16),
                          Row(
                            children: [
                              Icon(Icons.schedule, size: 18, color: Colors.orange),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Antrian Sync: ${provider.pendingQueueCount} task',
                                  style: TextStyle(fontSize: 13, color: Colors.orange.shade800),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Manual sync button
                if (provider.unsyncedScans > 0 || provider.unsyncedPhotos > 0) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        // Re-enqueue unsynced photos
                        final db = DatabaseHelper.instance;
                        final userId = SupabaseService().currentUser?.id;
                        final syncQueue = SyncQueue();
                        if (userId != null) {
                          final orders = await db.getAllOrders(userId: userId);
                          for (final o in orders) {
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
                            }
                          }
                        }
                        await syncQueue.processPending();
                        await provider.loadStats();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Sync selesai'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.sync),
                      label: const Text('Sync Sekarang'),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showUnsyncedPhotoDialog(BuildContext context, StatsProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.photo_library_outlined, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            const Text('Foto Belum Sinkron', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: provider.unsyncedPhotoResis.isEmpty
              ? const Text('Tidak ada data')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: provider.unsyncedPhotoResis.length,
                  itemBuilder: (_, i) {
                    final resi = provider.unsyncedPhotoResis[i];
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                      leading: Icon(Icons.receipt_long, size: 18, color: Colors.orange.shade700),
                      title: Text(resi, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'Salin',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: resi));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Disalin: $resi'),
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          if (provider.unsyncedPhotoResis.length > 1)
            TextButton(
              onPressed: () {
                final all = provider.unsyncedPhotoResis.join('\n');
                Clipboard.setData(ClipboardData(text: all));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${provider.unsyncedPhotoResis.length} resi disalin'),
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('Salin Semua'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Widget _buildLockedSection(BuildContext context) {
    return Card(
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.lock_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text(
              'Statistik Lengkap',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Upgrade ke Basic atau lebih tinggi untuk melihat grafik, penyimpanan, dan breakdown marketplace.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SubscriptionPage()),
                );
              },
              icon: const Icon(Icons.workspace_premium),
              label: const Text('Subscribe'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyBarChart extends StatelessWidget {
  final Map<String, int> stats;
  final int days;

  const _DailyBarChart({required this.stats, required this.days});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final spots = <FlSpot>[];
    final labels = <int, String>{};

    for (int i = 0; i < days; i++) {
      final date = now.subtract(Duration(days: days - 1 - i));
      final key = DateFormat('yyyy-MM-dd').format(date);
      final count = stats[key] ?? 0;
      spots.add(FlSpot(i.toDouble(), count.toDouble()));

      if (days <= 7 || i % (days ~/ 7) == 0 || i == days - 1) {
        labels[i] = DateFormat('dd/MM').format(date);
      }
    }

    if (spots.isEmpty) {
      return const Center(child: Text('Belum ada data'));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withValues(alpha: 0.15),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (value, meta) {
                if (value == value.roundToDouble()) {
                  return Text(
                    '${value.toInt()}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final label = labels[value.toInt()];
                if (label != null) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: AppTheme.primaryColor,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: days <= 14,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                radius: 3,
                color: AppTheme.primaryColor,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots
                .map((s) => LineTooltipItem(
                      '${s.y.toInt()} scan',
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _MarketplacePieChart extends StatelessWidget {
  final Map<String, int> stats;
  const _MarketplacePieChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = stats.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    final sections = stats.entries.map((e) {
      final pct = (e.value / total * 100);
      final color = AppTheme.getMarketplaceColor(e.key);
      return PieChartSectionData(
        value: e.value.toDouble(),
        color: color,
        title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        radius: 50,
      );
    }).toList();

    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 30,
        sectionsSpace: 2,
      ),
    );
  }
}

class _MarketplaceRow extends StatelessWidget {
  final String name;
  final int count;
  final int total;

  const _MarketplaceRow({
    required this.name,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.getMarketplaceColor(name);
    final pct = total > 0 ? (count / total * 100) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 45,
            child: Text(
              '${pct.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String name;
  final int count;
  final int total;

  const _CategoryRow({
    required this.name,
    required this.count,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.getMarketplaceColor(name);
    final pct = total > 0 ? (count / total * 100) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 45,
            child: Text(
              '${pct.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPieChart extends StatelessWidget {
  final Map<String, int> stats;
  const _CategoryPieChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = stats.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    final categoryColors = [
      AppTheme.primaryColor,
      Colors.teal,
      Colors.orange,
      Colors.purple,
      Colors.pink,
      Colors.indigo,
      Colors.brown,
      Colors.cyan,
    ];

    final sections = stats.entries.toList().asMap().entries.map((indexed) {
      final i = indexed.key;
      final e = indexed.value;
      final pct = (e.value / total * 100);
      final color = categoryColors[i % categoryColors.length];
      return PieChartSectionData(
        value: e.value.toDouble(),
        color: color,
        title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        radius: 50,
      );
    }).toList();

    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 30,
        sectionsSpace: 2,
      ),
    );
  }
}

class _SyncRow extends StatelessWidget {
  final String label;
  final String value;
  final int total;
  final int synced;
  final IconData icon;
  final bool isWarning;

  const _SyncRow({
    required this.label,
    required this.value,
    required this.total,
    required this.synced,
    required this.icon,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? synced / total : 0.0;
    return Row(
      children: [
        Icon(icon, size: 18, color: isWarning ? Colors.orange : Colors.grey),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isWarning ? FontWeight.w600 : FontWeight.normal,
                  color: isWarning ? Colors.orange.shade800 : null,
                ),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct.clamp(0.0, 1.0),
                  backgroundColor: Colors.grey[200],
                  color: isWarning ? Colors.orange : AppTheme.successColor,
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isWarning ? Colors.orange.shade800 : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
