import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/theme.dart';
import '../../models/order.dart';
import 'history_provider.dart';
import '../auth/auth_provider.dart';
import '../auth/login_dialog.dart';

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
                      title: const Text('Data tersimpan lokal', style: TextStyle(fontSize: 13)),
                      subtitle: const Text('Login untuk backup & sync ke cloud', style: TextStyle(fontSize: 12)),
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
                      if (_searchController.text.isNotEmpty)
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
                          _OrderTile(order: provider.orders[i], isLatest: i == 0),
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
  final ScannedOrder order;
  final bool isLatest;
  const _OrderTile({required this.order, this.isLatest = false});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.getMarketplaceColor(order.marketplace);
    final time = DateFormat('HH:mm').format(order.scannedAt);
    final hasPhoto = order.photoPath != null;

    return Dismissible(
      key: ValueKey(order.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
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
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          onTap: () {
            if (hasPhoto) {
              _showPhotoDialog(context, order.photoPath!);
            }
          },
          onLongPress: () => _showPhotoOptions(context),
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
              child: Image.file(
                File(photoPath),
                fit: BoxFit.contain,
              ),
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
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source ?? ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
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
