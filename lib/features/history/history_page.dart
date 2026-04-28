import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import 'history_provider.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<HistoryProvider>();
    provider.loadDates();
    provider.loadOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _exportCsv() async {
    final provider = context.read<HistoryProvider>();
    final orders = await provider.getAllForExport();

    final rows = <List<String>>[
      ['No', 'Resi', 'Marketplace', 'Tanggal', 'Waktu'],
      ...orders.asMap().entries.map((e) {
        final o = e.value;
        return [
          '${e.key + 1}',
          o.resi,
          o.marketplace,
          o.date,
          DateFormat('HH:mm:ss').format(o.scannedAt),
        ];
      }),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'scanorder_export.csv'));
    await file.writeAsString(csv);

    await Share.shareXFiles([XFile(file.path)], text: 'ScanOrder Export');
  }

  Future<void> _pickDate() async {
    final provider = context.read<HistoryProvider>();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(provider.selectedDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      provider.setDate(DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Order'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _exportCsv,
            tooltip: 'Export CSV',
          ),
        ],
      ),
      body: Consumer<HistoryProvider>(
        builder: (_, provider, _) => Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Cari nomor resi...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            provider.search('');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (v) => provider.search(v),
              ),
            ),

            // Date selector
            if (!provider.isSearching)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              _formatDateDisplay(provider.selectedDate),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${provider.orders.length} order',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            // Order list
            Expanded(
              child: provider.orders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            provider.isSearching
                                ? Icons.search_off
                                : Icons.inbox_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            provider.isSearching
                                ? 'Tidak ditemukan'
                                : 'Belum ada order',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: provider.orders.length,
                      itemBuilder: (_, i) =>
                          _OrderTile(order: provider.orders[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateDisplay(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);

    if (d == today) return 'Hari ini';
    if (d == today.subtract(const Duration(days: 1))) return 'Kemarin';
    return DateFormat('dd MMM yyyy', 'id').format(date);
  }
}

class _OrderTile extends StatelessWidget {
  final ScannedOrder order;
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.getMarketplaceColor(order.marketplace);
    final time = DateFormat('HH:mm').format(order.scannedAt);

    return Dismissible(
      key: ValueKey(order.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red[400],
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Hapus Order?'),
            content: Text('Hapus resi ${order.resi}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Hapus'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        if (order.id != null) {
          context.read<HistoryProvider>().deleteOrder(order.id!);
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 3),
        child: ListTile(
          dense: true,
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            radius: 20,
            child: Text(
              order.marketplace.substring(0, 1),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          title: Text(
            order.resi,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              fontFamily: 'monospace',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            order.marketplace,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: Text(
            time,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
