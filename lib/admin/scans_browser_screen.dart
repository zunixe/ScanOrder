import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import 'admin_provider.dart';

/// Browser seluruh data scan milik semua user (read-only).
/// Data dilayani lewat policy RLS super admin di tabel scans.
class ScansBrowserScreen extends StatefulWidget {
  const ScansBrowserScreen({super.key});

  @override
  State<ScansBrowserScreen> createState() => _ScansBrowserScreenState();
}

class _ScansBrowserScreenState extends State<ScansBrowserScreen> {
  final _scrollController = ScrollController();
  String? _marketplace;
  String? _teamId;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _apply());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      final admin = context.read<AdminProvider>();
      if (admin.hasMoreScans && !admin.scansLoading) {
        admin.loadMoreScans();
      }
    }
  }

  Future<void> _apply() async {
    await context.read<AdminProvider>().applyFilter(ScanFilter(
          marketplace: (_marketplace?.isEmpty ?? true) ? null : _marketplace,
          teamId: (_teamId?.isEmpty ?? true) ? null : _teamId,
          from: _from,
          to: _to,
        ));
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? (_from ?? DateTime.now()) : (_to ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _from = DateTime(picked.year, picked.month, picked.day);
      } else {
        // Eksklusif: batas atas = tengah malam hari berikutnya.
        final next = picked.add(const Duration(days: 1));
        _to = DateTime(next.year, next.month, next.day);
      }
    });
    await _apply();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final marketplaces = <String>{};
    for (final s in admin.scans) {
      final m = s['marketplace'] as String?;
      if (m != null && m.isNotEmpty) marketplaces.add(m);
    }
    final marketplaceList = marketplaces.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text(admin.filter.describe()),
        actions: [
          IconButton(
            tooltip: 'Reset filter',
            icon: const Icon(Icons.filter_alt_off_outlined),
            onPressed: () {
              setState(() {
                _marketplace = null;
                _teamId = null;
                _from = null;
                _to = null;
              });
              _apply();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Bar filter ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DropdownButton<String>(
                  hint: const Text('Marketplace'),
                  value: (_marketplace?.isEmpty ?? true) ? null : _marketplace,
                  items: [
                    for (final m in marketplaceList)
                      DropdownMenuItem(value: m, child: Text(m)),
                    const DropdownMenuItem(value: '', child: Text('Semua')),
                  ],
                  onChanged: (v) {
                    setState(() => _marketplace = v);
                    _apply();
                  },
                ),
                DropdownButton<String>(
                  hint: const Text('Tim'),
                  value: (_teamId?.isEmpty ?? true) ? null : _teamId,
                  items: [
                    for (final t in admin.teams)
                      DropdownMenuItem(
                          value: t['id'] as String,
                          child: Text((t['name'] ?? '') as String)),
                    const DropdownMenuItem(value: '', child: Text('Semua')),
                  ],
                  onChanged: (v) {
                    setState(() => _teamId = v);
                    _apply();
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(_rangeLabel()),
                  onPressed: () => _pickDate(isStart: true),
                ),
                if (_from != null || _to != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Hapus tanggal'),
                    onPressed: () {
                      setState(() {
                        _from = null;
                        _to = null;
                      });
                      _apply();
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 16),
          // ── Daftar scan ──
          Expanded(
            child: admin.scansError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        admin.scansError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.dangerColor),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _apply,
                    child: ListView.separated(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount:
                          admin.scans.length + (admin.scansLoading ? 1 : 0),
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        if (i >= admin.scans.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                                child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )),
                          );
                        }
                        return _ScanTile(row: admin.scans[i]);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _rangeLabel() {
    final df = DateFormat('dd MMM');
    if (_from != null && _to != null) {
      return '${df.format(_from!)} – ${df.format(_to!.subtract(const Duration(days: 1)))}';
    }
    if (_from != null) return 'Sejak ${df.format(_from!)}';
    if (_to != null) return 'Sampai ${df.format(_to!)}';
    return 'Pilih rentang';
  }
}

class _ScanTile extends StatelessWidget {
  final Map<String, dynamic> row;

  const _ScanTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final resi = (row['resi'] ?? '-') as String;
    final marketplace = (row['marketplace'] ?? '-') as String;
    final scannedAt = row['scanned_at'];
    final dateText = scannedAt is num
        ? DateFormat('dd MMM yyyy HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(scannedAt.toInt()))
        : (row['date'] ?? '-').toString();
    final userId = (row['user_id'] as String?) ?? 'guest';
    final teamId = row['team_id'] as String?;

    return ListTile(
      dense: true,
      title: Text(resi,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('$marketplace · $dateText\nuser: $userId${teamId != null ? ' · tim: ${teamId.substring(0, 8)}…' : ''}',
          style: TextStyle(fontSize: AppTheme.captionSize, height: 1.35)),
      isThreeLine: true,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(marketplace,
            style: const TextStyle(
                fontSize: AppTheme.microSize, color: AppTheme.primaryColor)),
      ),
    );
  }
}
