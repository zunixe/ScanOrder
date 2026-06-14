import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/scan_record.dart';
import '../history/history_provider.dart';
import '../settings/settings_provider.dart';

class PhotoPreviewPage extends StatefulWidget {
  final List<ScanRecord> scans;
  final int initialIndex;

  const PhotoPreviewPage({
    super.key,
    required this.scans,
    required this.initialIndex,
  });

  @override
  State<PhotoPreviewPage> createState() => _PhotoPreviewPageState();
}

class _PhotoPreviewPageState extends State<PhotoPreviewPage> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy', 'id');
    final tf = DateFormat('HH:mm:ss');

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            scrollDirection: Axis.vertical,
            controller: _pageController,
            onPageChanged: (i) => setState(() {}),
            itemCount: widget.scans.length,
            itemBuilder: (_, i) {
              final scan = widget.scans[i];
              return _PhotoPageItem(
                scan: scan,
                index: i,
                total: widget.scans.length,
                df: df,
                tf: tf,
              );
            },
          ),
          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: SafeArea(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPageItem extends StatefulWidget {
  final ScanRecord scan;
  final int index;
  final int total;
  final DateFormat df;
  final DateFormat tf;

  const _PhotoPageItem({
    required this.scan,
    required this.index,
    required this.total,
    required this.df,
    required this.tf,
  });

  @override
  State<_PhotoPageItem> createState() => _PhotoPageItemState();
}

class _PhotoPageItemState extends State<_PhotoPageItem> {
  late ScanRecord _scan;

  @override
  void initState() {
    super.initState();
    _scan = widget.scan;
  }

  void _showPhotoOptions() {
    final hasPhoto = _scan.photoPath != null;
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
                _pickNewPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pilih dari galeri'),
              onTap: () {
                Navigator.pop(ctx);
                _pickNewPhoto(ImageSource.gallery);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Hapus foto', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _removePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickNewPhoto(ImageSource source) async {
    final compress = context.read<SettingsProvider>().compressPhoto;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: compress ? 1280 : null,
      maxHeight: compress ? 1280 : null,
      imageQuality: compress ? 85 : null,
    );
    if (picked == null || !mounted) return;

    final provider = context.read<HistoryProvider>();
    await provider.updatePhoto(_scan.id!, picked.path);
    if (!mounted) return;

    final updated = provider.scans.cast<ScanRecord?>().firstWhere((s) => s?.id == _scan.id, orElse: () => null);
    if (updated != null) {
      setState(() => _scan = updated);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto berhasil diperbarui')),
      );
    }
  }

  Color get _marketplaceColor {
    switch (_scan.marketplace) {
      case 'Shopee': return Colors.orange;
      case 'Tokopedia': return const Color(0xFF42B549);
      case 'TikTok': return const Color(0xFF000000);
      case 'Lazada': return const Color(0xFF0F146D);
      case 'JNE': return const Color(0xFFE53935);
      case 'J&T': return const Color(0xFF1A237E);
      case 'SiCepat': return const Color(0xFFFF6F00);
      case 'AnterAja': return const Color(0xFF00897B);
      case 'Ninja': return const Color(0xFFFFD600);
      case 'ID Express': return const Color(0xFF1565C0);
      case 'Paxel': return const Color(0xFF6A1B9A);
      default: return Colors.grey;
    }
  }

  Future<void> _removePhoto() async {
    final provider = context.read<HistoryProvider>();
    await provider.updatePhoto(_scan.id!, null);
    if (!mounted) return;

    final updated = provider.scans.cast<ScanRecord?>().firstWhere((s) => s?.id == _scan.id, orElse: () => null);
    if (updated != null) {
      setState(() => _scan = updated);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto dihapus')),
      );
    }
  }

  Widget _buildImage() {
    final photoPath = _scan.photoPath;
    if (photoPath == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('Tidak ada foto', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return Center(
      child: photoPath.startsWith('http')
          ? CachedNetworkImage(
              imageUrl: photoPath,
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 64, color: Colors.grey),
            )
          : Image.file(
              File(photoPath),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 64, color: Colors.grey),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildImage(),

        // Top info overlay
        Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 60,
                left: 16,
                right: 56,
                bottom: 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _marketplaceColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _scan.marketplace,
                          style: TextStyle(
                            color: _marketplaceColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _scan.resi,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 12, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.df.format(_scan.scannedAt)} ${widget.tf.format(_scan.scannedAt)}',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.index + 1}/${widget.total}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // Bottom actions
        Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionButton(
                  icon: Icons.edit,
                  label: 'Edit',
                  onTap: _showPhotoOptions,
                ),
                const SizedBox(width: 16),
                if (_scan.photoPath != null)
                  _ActionButton(
                    icon: Icons.download,
                    label: 'Download',
                    onTap: () => _downloadPhoto(_scan.photoPath!),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _downloadPhoto(String photoPath) async {
    try {
      final dir = Directory('/storage/emulated/0/Download');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final fileName = 'scanorder_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final dest = File('${dir.path}/$fileName');

      if (photoPath.startsWith('http')) {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(photoPath));
        final response = await request.close();
        final bytes = await response.fold<List<int>>([], (p, e) => p..addAll(e));
        await dest.writeAsBytes(bytes);
      } else {
        await File(photoPath).copy(dest.path);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Foto disimpan: ${dest.path}'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal download: $e'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
