import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/theme.dart';
import '../../models/scan_record.dart';
import '../../services/quota_service.dart';
import 'history_provider.dart';
import '../auth/auth_provider.dart';
import '../auth/login_dialog.dart';
import '../settings/settings_provider.dart';
import '../subscription/subscription_provider.dart';

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
    final auth = context.read<AuthProvider>();
    final teamId = auth.currentTeam?.id;
    final adminUserId = auth.isAdmin ? null : auth.currentTeam?.createdBy;
    final provider = context.read<HistoryProvider>();
    provider.setTeamContext(teamId, adminUserId);
    provider.loadDates();
    provider.loadScans();
    provider.loadCategories();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only update team context if changed — don't full refresh to preserve user's date/filter selection
    final auth = context.read<AuthProvider>();
    final teamId = auth.currentTeam?.id;
    final adminUserId = auth.isAdmin ? null : auth.currentTeam?.createdBy;
    final provider = context.read<HistoryProvider>();
    final needsRefresh = provider.teamId != teamId;
    provider.setTeamContext(teamId, adminUserId);
    if (needsRefresh) provider.refresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _exportCsv() async {
    final provider = context.read<HistoryProvider>();
    final scans = await provider.getAllForExport();

    if (scans.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada data untuk di-export')),
      );
      return;
    }

    final rows = <List<String>>[
      ['No', 'Resi', 'Marketplace', 'Kategori', 'Tanggal', 'Waktu'],
      ...scans.asMap().entries.map((e) {
        final o = e.value;
        final cats = o.categories.map((c) => c.name).join(', ');
        return [
          '${e.key + 1}',
          o.resi,
          o.marketplace,
          cats,
          o.date,
          DateFormat('HH:mm:ss').format(o.scannedAt),
        ];
      }),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'scanorder_export.csv'));
    await file.writeAsString(csv);

    await Share.shareXFiles([XFile(file.path)], text: 'ScanOrder Export CSV');
  }

  Future<void> _exportXlsx() async {
    final provider = context.read<HistoryProvider>();
    final scans = await provider.getAllForExport();

    if (scans.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada data untuk di-export')),
      );
      return;
    }

    final excel = Excel.createExcel();
    final sheet = excel['ScanOrder'];

    // Hapus default "Sheet1" yang kosong agar user langsung lihat sheet "ScanOrder"
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Header
    final headers = ['No', 'Resi', 'Marketplace', 'Kategori', 'Tanggal', 'Waktu'];
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(CellIndex.indexByString('${String.fromCharCode(65 + c)}1'));
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = CellStyle(bold: true);
    }

    // Data rows
    for (var i = 0; i < scans.length; i++) {
      final o = scans[i];
      final cats = o.categories.map((c) => c.name).join(', ');
      final row = i + 2;
      sheet.cell(CellIndex.indexByString('A$row')).value = IntCellValue(i + 1);
      sheet.cell(CellIndex.indexByString('B$row')).value = TextCellValue(o.resi);
      sheet.cell(CellIndex.indexByString('C$row')).value = TextCellValue(o.marketplace);
      sheet.cell(CellIndex.indexByString('D$row')).value = TextCellValue(cats);
      sheet.cell(CellIndex.indexByString('E$row')).value = TextCellValue(o.date);
      sheet.cell(CellIndex.indexByString('F$row')).value = TextCellValue(DateFormat('HH:mm:ss').format(o.scannedAt));
    }

    // Auto-fit column widths
    for (var c = 0; c < headers.length; c++) {
      sheet.setColumnWidth(c, 18);
    }

    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'scanorder_export.xlsx'));
    final bytes = excel.save(fileName: 'scanorder_export.xlsx');
    if (bytes == null) return;
    await file.writeAsBytes(bytes);

    await Share.shareXFiles([XFile(file.path)], text: 'ScanOrder Export XLSX');
  }

  void _showExportMenu() {
    final auth = context.read<AuthProvider>();
    final isPaid = context.read<SubscriptionProvider>().currentTier.index >= StorageTier.pro.index;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.table_chart),
            title: const Text('Export CSV'),
            subtitle: const Text('Format tabel, bisa dibuka di semua app'),
            onTap: () {
              Navigator.pop(ctx);
              _exportCsv();
            },
          ),
          if (isPaid)
            ListTile(
              leading: const Icon(Icons.file_present),
              title: const Text('Export XLSX (Excel)'),
              subtitle: const Text('Format Excel'),
              onTap: () {
                Navigator.pop(ctx);
                _exportXlsx();
              },
            ),
          if (!isPaid && auth.isLoggedIn)
            ListTile(
              leading: const Icon(Icons.lock_outline, color: Colors.grey),
              title: const Text('Export XLSX (Excel)'),
              subtitle: const Text('Upgrade ke paket berbayar untuk export Excel'),
              enabled: false,
            ),
        ],
      ),
    );
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
        title: const Text('Riwayat Scan'),
        actions: [
          Consumer<SubscriptionProvider>(
            builder: (_, sub, __) {
              if (sub.currentTier == StorageTier.free) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.file_download_outlined),
                onPressed: _showExportMenu,
                tooltip: 'Export',
              );
            },
          ),
        ],
      ),
      body: Consumer<HistoryProvider>(
        builder: (_, provider, _) => Column(
          children: [
            // Cloud backup prompt (guest only)
            Consumer<AuthProvider>(
              builder: (_, auth, __) {
                if (auth.isLoggedIn) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Card(
                    color: Colors.orange.withAlpha(30),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.cloud_upload_outlined, color: Colors.orange),
                      title: const Text('Data tersimpan lokal', style: TextStyle(fontSize: AppTheme.bodySize)),
                      subtitle: const Text('Login untuk backup & sync ke cloud', style: TextStyle(fontSize: AppTheme.captionSize)),
                      trailing: TextButton(
                        onPressed: () => showLoginDialog(context),
                        child: const Text('Login'),
                      ),
                    ),
                  ),
                );
              },
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Cari nomor resi...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchController.text.isNotEmpty || provider.isSearching)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            provider.search('');
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner, size: 20),
                        tooltip: 'Scan resi',
                        onPressed: () => _scanToSearch(context, provider),
                      ),
                    ],
                  ),
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
                    const SizedBox(width: 8),
                    // "Semua" button
                    InkWell(
                      onTap: () => provider.setDate(HistoryProvider.allDatesSentinel),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: provider.selectedDate == HistoryProvider.allDatesSentinel
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Semua',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: provider.selectedDate == HistoryProvider.allDatesSentinel
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${provider.filteredScans.length} scan',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            // Team tier: kategori list dengan count
            Consumer3<HistoryProvider, SubscriptionProvider, AuthProvider>(
              builder: (_, provider, sub, auth, _) {
                final isTeamUser = sub.currentTier == StorageTier.unlimited || auth.isTeamMember;
                if (!isTeamUser) return const SizedBox.shrink();
                if (provider.filterCategoryId != null) return const SizedBox.shrink();
                if (provider.isSearching) return const SizedBox.shrink();
                // Hide category list when "Semua" is selected
                if (provider.selectedDate == HistoryProvider.allDatesSentinel) return const SizedBox.shrink();
                // Jika ada kategori, tampilkan daftar kategori
                if (provider.categories.isNotEmpty) {
                  return Expanded(
                    child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: provider.categories.length,
                          itemBuilder: (_, i) {
                            final cat = provider.categories[i];
                            final count = provider.categoryCounts[cat.id] ?? 0;
                            final catColor = _parseColor(cat.color);
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: catColor.withValues(alpha: 0.2),
                                  child: Icon(Icons.folder, color: catColor),
                                ),
                                title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: catColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$count scan',
                                    style: TextStyle(color: catColor, fontWeight: FontWeight.w600, fontSize: AppTheme.bodySize),
                                  ),
                                ),
                                onTap: () => provider.setFilterCategory(cat.id),
                              ),
                            );
                          },
                        ),
                  );
                }
                // Tidak ada kategori: tampilkan daftar order langsung (jika ada)
                if (provider.scans.isEmpty) {
                  return Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text('Belum ada scan', style: TextStyle(fontSize: AppTheme.sectionTitleSize, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  );
                }
                // Ada scans tapi tidak ada kategori: tampilkan order list langsung
                return Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: provider.scans.length,
                    itemBuilder: (_, i) => _OrderTile(order: provider.scans[i], isLatest: i == 0),
                  ),
                );
              },
            ),

            // Order list (shown when category is selected or searching, or for non-team users)
            Consumer3<HistoryProvider, SubscriptionProvider, AuthProvider>(
              builder: (_, provider, sub, auth, _) {
                final isTeamUser = sub.currentTier == StorageTier.unlimited || auth.isTeamMember;
                // Team: sembunyikan jika belum memilih kategori dan ada kategori (sudah ditampilkan di atas)
                // Tapi tampilkan jika sedang mencari atau sudah pilih kategori atau mode "Semua"
                if (isTeamUser && provider.filterCategoryId == null && !provider.isSearching && provider.categories.isNotEmpty && provider.selectedDate != HistoryProvider.allDatesSentinel) {
                  return const SizedBox.shrink();
                }
                // Team tanpa kategori: order list sudah ditampilkan di widget atas, skip
                if (isTeamUser && provider.filterCategoryId == null && !provider.isSearching && provider.categories.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Expanded(
                  child: Column(
                    children: [
                      // Back button untuk Team tier saat di kategori
                      if (isTeamUser && provider.filterCategoryId != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => provider.setFilterCategory(null),
                              icon: const Icon(Icons.arrow_back, size: 18),
                              label: Text(
                                provider.categories.where((c) => c.id == provider.filterCategoryId).firstOrNull?.name ?? 'Kembali',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: provider.filteredScans.isEmpty
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
                                          : 'Belum ada scan',
                                      style: TextStyle(
                                        fontSize: AppTheme.sectionTitleSize,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                itemCount: provider.filteredScans.length,
                                itemBuilder: (_, i) =>
                                    _OrderTile(order: provider.filteredScans[i], isLatest: i == 0),
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateDisplay(String dateStr) {
    if (dateStr == HistoryProvider.allDatesSentinel) return 'Semua';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);

    if (d == today) return 'Hari ini';
    if (d == today.subtract(const Duration(days: 1))) return 'Kemarin';
    return DateFormat('dd MMM yyyy', 'id').format(date);
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.blue;
    }
  }

  Future<void> _scanToSearch(BuildContext ctx, HistoryProvider provider) async {
    final result = await showDialog<String>(
      context: ctx,
      builder: (scanCtx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Scan Resi'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(scanCtx),
            ),
          ),
          body: MobileScanner(
            onDetect: (capture) {
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) {
                Navigator.pop(scanCtx, barcode!.rawValue!);
              }
            },
          ),
        ),
      ),
    );
    if (result != null && result.isNotEmpty) {
      _searchController.text = result;
      provider.search(result);
    }
  }
}

class _OrderTile extends StatelessWidget {
  final ScanRecord order;
  final bool isLatest;
  const _OrderTile({required this.order, this.isLatest = false});

  Color _parseCatColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.getMarketplaceColor(order.marketplace);
    final time = DateFormat('HH:mm').format(order.scannedAt);
    final hasPhoto = order.photoPath != null;

    return Dismissible(
      key: ValueKey(order.id),
      direction: DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Hapus Scan?'),
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
          context.read<HistoryProvider>().deleteScan(order.id!);
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 3),
        child: ListTile(
          dense: true,
          leading: hasPhoto
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: order.photoPath!.startsWith('http')
                      ? Image.network(
                          order.photoPath!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.15),
                            radius: 20,
                            child: Text(
                              order.marketplace.substring(0, 1),
                              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                        )
                      : File(order.photoPath!).existsSync()
                          ? Image.file(
                              File(order.photoPath!),
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => CircleAvatar(
                                backgroundColor: color.withValues(alpha: 0.15),
                                radius: 20,
                                child: Text(
                                  order.marketplace.substring(0, 1),
                                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                            )
                          : CircleAvatar(
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
                )
              : CircleAvatar(
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
              fontSize: AppTheme.cardTitleSize,
              fontFamily: 'monospace',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: SizedBox(
            height: 20,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Text(
                  order.marketplace,
                  style: TextStyle(
                    fontSize: AppTheme.captionSize,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  DateFormat('dd MMM yyyy', 'id').format(order.scannedAt),
                  style: TextStyle(
                    fontSize: AppTheme.microSize,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (order.categories.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  ...order.categories.take(2).map((cat) => Container(
                    margin: const EdgeInsets.only(right: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    decoration: BoxDecoration(
                      color: _parseCatColor(cat.color).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      cat.name,
                      style: TextStyle(
                        fontSize: 10,
                        color: _parseCatColor(cat.color),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )),
                  if (order.categories.length > 2)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '+${order.categories.length - 2}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              if (order.syncStatus == 'pending') ...[
                const SizedBox(width: 6),
                const Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.orange),
              ],
              if (order.syncStatus == 'duplicate_conflict') ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Duplikat Cloud',
                    style: TextStyle(
                      fontSize: AppTheme.microSize,
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasPhoto)
                Icon(
                  Icons.image,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              if (!hasPhoto)
                IconButton(
                  icon: const Icon(Icons.add_a_photo, size: 16),
                  color: Colors.grey,
                  tooltip: 'Tambah foto',
                  onPressed: () => _pickNewPhoto(context),
                ),
              const SizedBox(width: 4),
              Text(
                time,
                style: TextStyle(
                  fontSize: AppTheme.captionSize,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          onTap: () {
            Clipboard.setData(ClipboardData(text: order.resi));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Resi ${order.resi} disalin'),
                duration: const Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          onLongPress: () {
            if (hasPhoto) {
              _showPhotoDialog(context, order.photoPath!);
            } else {
              _showPhotoOptions(context);
            }
          },
        ),
      ),
    );
  }

  void _showPhotoDialog(BuildContext context, String photoPath) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Foto Scan'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Ganti foto',
                onPressed: () {
                  Navigator.pop(ctx);
                  _pickNewPhoto(context);
                },
              ),
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Download',
                onPressed: () => _downloadPhoto(ctx, photoPath),
              ),
            ],
          ),
          body: InteractiveViewer(
            panEnabled: true,
            boundaryMargin: const EdgeInsets.all(20),
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: photoPath.startsWith('http')
                  ? Image.network(photoPath, fit: BoxFit.contain)
                  : Image.file(File(photoPath), fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadPhoto(BuildContext context, String photoPath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'scanorder_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final dest = File(p.join(dir.path, fileName));
      await File(photoPath).copy(dest.path);

      // Share file so user can save to gallery / downloads
      await Share.shareXFiles(
        [XFile(dest.path)],
        text: 'Foto Scan Resi',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal download: $e')),
        );
      }
    }
  }

  void _showPhotoOptions(BuildContext context) {
    final hasPhoto = order.photoPath != null;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Ambil foto dari kamera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickNewPhoto(context, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pilih dari galeri'),
              onTap: () {
                Navigator.pop(ctx);
                _pickNewPhoto(context, ImageSource.gallery);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Hapus foto', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _removePhoto(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickNewPhoto(BuildContext context, [ImageSource? source]) async {
    final compress = context.read<SettingsProvider>().compressPhoto;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source ?? ImageSource.camera,
      maxWidth: compress ? 1280 : null,
      maxHeight: compress ? 1280 : null,
      imageQuality: compress ? 85 : null,
    );
    if (picked == null) return;

    final provider = context.read<HistoryProvider>();
    await provider.updatePhoto(order.id!, picked.path);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto berhasil diperbarui')),
      );
    }
  }

  Future<void> _removePhoto(BuildContext context) async {
    final provider = context.read<HistoryProvider>();
    await provider.updatePhoto(order.id!, null);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto dihapus')),
      );
    }
  }
}
