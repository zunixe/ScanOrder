import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistik'),
      ),
      body: Consumer<StatsProvider>(
        builder: (_, provider, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary cards
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      title: 'Total Order',
                      value: '${provider.totalOrders}',
                      icon: Icons.inventory_2_outlined,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Hari ini',
                      value: '${provider.dailyStats[DateFormat('yyyy-MM-dd').format(DateTime.now())] ?? 0}',
                      icon: Icons.today,
                      color: AppTheme.successColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Period selector + bar chart
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Order per Hari',
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
                    total: provider.totalOrders,
                  ),
                ),
              ],
            ],
          ),
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
                      '${s.y.toInt()} order',
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
