import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:image/image.dart' as img;
import '../../core/theme.dart';
import '../../features/auth/auth_provider.dart';
import '../../models/category.dart';
import '../../services/quota_service.dart';
import '../settings/settings_provider.dart';
import 'scan_provider.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  MobileScannerController? _controller;
  bool _isTorchOn = false;
  String? _lastScannedCode;
  Timer? _cooldownTimer;
  bool _onCooldown = false;
  List<Offset> _barcodeCorners = const [];
  Size _cameraSize = Size.zero;
  Timer? _barcodeRectTimer;
  bool _focusResiMode = true;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.unrestricted,
      facing: CameraFacing.back,
      returnImage: true,
      formats: [BarcodeFormat.code128, BarcodeFormat.code39, BarcodeFormat.code93, BarcodeFormat.ean13, BarcodeFormat.qrCode],
    );
    final auth = context.read<AuthProvider>();
    final team = auth.currentTeam;
    final teamId = team?.id;
    final adminUserId = auth.isAdmin ? null : team?.createdBy;
    context.read<ScanProvider>().setTeamContext(teamId, adminUserId);
    context.read<ScanProvider>().loadCounts();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _controller?.dispose();
    _cooldownTimer?.cancel();
    _barcodeRectTimer?.cancel();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_onCooldown) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final code = barcode.rawValue!;
    if (code == _lastScannedCode) return;

    if (_focusResiMode && !_isBarcodeInsideResiZone(barcode.corners, capture.size)) {
      if (barcode.corners.isNotEmpty) {
        setState(() {
          _barcodeCorners = barcode.corners;
          _cameraSize = capture.size;
        });
        _barcodeRectTimer?.cancel();
        _barcodeRectTimer = Timer(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _barcodeCorners = const []);
        });
      }
      return;
    }

    _lastScannedCode = code;
    _onCooldown = true;
    _cooldownTimer = Timer(const Duration(milliseconds: 1500), () {
      _onCooldown = false;
      _lastScannedCode = null;
    });

    // Update barcode corners overlay
    if (barcode.corners.isNotEmpty) {
      setState(() {
        _barcodeCorners = barcode.corners;
        _cameraSize = capture.size;
      });
      _barcodeRectTimer?.cancel();
      _barcodeRectTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _barcodeCorners = const []);
      });
    }

    _handleScan(code, capture);
  }

  bool _isBarcodeInsideResiZone(List<Offset> corners, Size cameraSize) {
    if (corners.isEmpty || cameraSize == Size.zero) return false;

    final center = corners.fold<Offset>(
          Offset.zero,
          (sum, point) => sum + point,
        ) /
        corners.length.toDouble();

    final normalizedX = center.dx / cameraSize.width;
    final normalizedY = center.dy / cameraSize.height;

    return normalizedX >= 0.15 &&
        normalizedX <= 0.85 &&
        normalizedY >= 0.06 &&
        normalizedY <= 0.36;
  }

  Future<void> _handleScan(String code, BarcodeCapture capture) async {
    final provider = context.read<ScanProvider>();
    final teamId = context.read<AuthProvider>().currentTeam?.id;

    // Capture photo simultaneously during scan
    String? photoPath;
    if (provider.savePhoto && capture.image != null) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File('${dir.path}/$fileName');
        final compress = context.read<SettingsProvider>().compressPhoto;
        if (compress) {
          // Compress: resize max 1280px, quality 80%
          final image = img.decodeImage(capture.image!);
          if (image != null) {
            final resized = img.copyResize(image, width: image.width > image.height ? 1280 : null, height: image.height >= image.width ? 1280 : null);
            final compressed = img.encodeJpg(resized, quality: 80);
            await file.writeAsBytes(compressed);
          } else {
            await file.writeAsBytes(capture.image!);
          }
        } else {
          await file.writeAsBytes(capture.image!);
        }
        photoPath = file.path;
      } catch (_) {
        photoPath = null;
      }
    }

    final result = await provider.processScan(code, photoPath, teamId: teamId);
    if (result == null) return;

    switch (result.status) {
      case ScanStatus.success:
        // Green feedback - auto continue
        Vibration.vibrate(duration: 100);
        HapticFeedback.lightImpact();
        if (mounted) _showSuccessOverlay(result);
        break;

      case ScanStatus.duplicate:
        // Red feedback - warning
        Vibration.vibrate(duration: 500, amplitude: 255);
        HapticFeedback.heavyImpact();
        if (mounted) _showDuplicateOverlay(result);
        break;

      case ScanStatus.recentRepeat:
        HapticFeedback.selectionClick();
        if (mounted) _showRecentRepeatOverlay(result);
        break;

      case ScanStatus.quotaExceeded:
        Vibration.vibrate(duration: 300);
        if (mounted) _showQuotaDialog();
        break;

      case ScanStatus.noCategory:
        Vibration.vibrate(duration: 200);
        HapticFeedback.mediumImpact();
        if (mounted) _showNoCategoryDialog();
        break;

      case ScanStatus.idle:
        break;
    }
  }

  void _showSuccessOverlay(ScanResult result) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.resi,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    result.marketplace,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.successColor,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showDuplicateOverlay(ScanResult result) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DUPLIKAT!',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    result.resi,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (result.existingOrder != null)
                    Text(
                      'Sudah discan: ${_formatTime(result.existingOrder!.scannedAt)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.dangerColor,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showRecentRepeatOverlay(ScanResult result) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BARU SAJA DISCAN',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    result.resi,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Diabaikan agar tidak terbaca double',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blueGrey,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showQuotaDialog() {
    final auth = context.read<AuthProvider>();
    final isExpired = auth.isLoggedIn;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isExpired ? 'Langganan Habis' : 'Kuota Habis'),
        content: Text(
          isExpired
              ? 'Langganan Anda sudah berakhir. Perpanjang paket untuk lanjut scan dan sinkronisasi ke cloud.'
              : 'Kuota scan periode ini sudah habis.\nUpgrade paket untuk kuota lebih banyak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Nanti'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              DefaultTabController.of(context).animateTo(3);
            },
            child: Text(isExpired ? 'Perpanjang Paket' : 'Upgrade Pro'),
          ),
        ],
      ),
    );
  }

  void _showNoCategoryDialog() {
    final provider = context.read<ScanProvider>();
    final hasCategories = provider.categories.isNotEmpty;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(hasCategories ? 'Pilih Kategori Dulu' : 'Buat Kategori Dulu'),
        content: Text(
          hasCategories
              ? 'Untuk mulai scan tim, pilih kategori terlebih dahulu dengan mengetuk chip kategori di bawah.'
              : 'Untuk mulai scan tim, kategori harus ada terlebih dahulu. Minta admin membuat kategori dengan tombol +.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showManualInputDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Input Manual No. Resi'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'No. Resi',
            hintText: 'Masukkan nomor resi',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submitManualResi(ctx, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => _submitManualResi(ctx, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitManualResi(BuildContext dialogContext, String value) async {
    final code = value.trim().toUpperCase();
    if (code.isEmpty) return;

    Navigator.pop(dialogContext);
    await _handleScan(code, const BarcodeCapture());
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} $h:$m';
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.blue;
    }
  }

  void _showCreateCategoryDialog(BuildContext context) {
    final nameController = TextEditingController();
    String selectedColor = '#2196F3'; // default blue

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Kategori Baru'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama kategori',
                  hintText: 'Misal: Gudang A, Retur',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  '#F44336', '#E91E63', '#9C27B0', '#2196F3',
                  '#009688', '#4CAF50', '#FF9800', '#795548',
                ].map((hex) => GestureDetector(
                  onTap: () => setState(() => selectedColor = hex),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _parseColor(hex),
                      shape: BoxShape.circle,
                      border: selectedColor == hex
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                    ),
                  ),
                )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) return;
                context.read<ScanProvider>().addCategory(nameController.text.trim(), selectedColor);
                Navigator.pop(ctx);
              },
              child: const Text('Buat'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCategoryOptions(BuildContext context, ScanCategory cat) {
    final auth = context.read<AuthProvider>();
    final isReadOnly = auth.isTeamMember;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _parseColor(cat.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    cat.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            if (isReadOnly) ...[
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Kategori dibuat oleh admin tim. Hanya admin yang bisa mengedit.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            ] else ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Rename'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRenameCategoryDialog(context, cat);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Hapus', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Semua scan dalam kategori ini akan ikut terhapus'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      title: Text('Hapus "${cat.name}"?'),
                      content: const Text('Semua scan dalam kategori ini juga akan dihapus. Tindakan ini tidak bisa dibatalkan.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Batal')),
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx, true),
                          child: const Text('Hapus', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    context.read<ScanProvider>().deleteCategory(cat.id!);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showRenameCategoryDialog(BuildContext context, ScanCategory cat) {
    final nameController = TextEditingController(text: cat.name);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Kategori'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Nama kategori',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty) return;
              context.read<ScanProvider>().renameCategory(cat.id!, nameController.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Camera
          MobileScanner(
            controller: _controller!,
            onDetect: _onDetect,
          ),

          // Top overlay - counts
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                bottom: 12,
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
              child: Consumer2<ScanProvider, AuthProvider>(
                builder: (_, provider, auth, _) {
                  final isTeamMember = auth.isTeamMember;
                  return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ScanOrder',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Hari ini: ${provider.todayCount} scan',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (isTeamMember)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Anggota Tim',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          )
                        else if (provider.scanLimit >= 0)
                          Text(
                            'Sisa: ${provider.quotaDisplay}',
                            style: TextStyle(
                              color: provider.remainingScans <= 10 && provider.scanLimit > 0
                                  ? Colors.orangeAccent
                                  : Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Total: ${provider.totalCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () {
                            setState(() => _focusResiMode = !_focusResiMode);
                          },
                          icon: Icon(
                            _focusResiMode ? Icons.center_focus_strong : Icons.center_focus_weak,
                            color: _focusResiMode ? Colors.lightGreenAccent : Colors.white70,
                          ),
                          tooltip: _focusResiMode ? 'Fokus Resi: ON' : 'Fokus Resi: OFF',
                        ),
                        const SizedBox(width: 4),
                        // Photo save toggle
                        Consumer<ScanProvider>(
                          builder: (_, provider, _) => IconButton(
                            onPressed: () => provider.setSavePhoto(!provider.savePhoto),
                            icon: Icon(
                              provider.savePhoto ? Icons.photo_camera : Icons.photo_camera_outlined,
                              color: provider.savePhoto ? Colors.white : Colors.white70,
                            ),
                            tooltip: provider.savePhoto ? 'Foto: ON' : 'Foto: OFF',
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () {
                            setState(() => _isTorchOn = !_isTorchOn);
                            _controller?.toggleTorch();
                          },
                          icon: Icon(
                            _isTorchOn ? Icons.flash_on : Icons.flash_off,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
                },
              ),
            ),
          ),

          // Category chips (Team tier only) — sejajar dengan FAB input manual di kiri bawah
          Positioned(
            left: 12,
            right: 70,
            bottom: MediaQuery.of(context).padding.bottom + 20,
            child: Consumer2<ScanProvider, AuthProvider>(
              builder: (_, provider, auth, _) {
                final isTeamUser = provider.currentTier == StorageTier.unlimited || auth.hasTeam;
                if (!isTeamUser) {
                  return const SizedBox.shrink();
                }
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Category chips — tap to select, tap again to deselect
                        ...provider.categories.map((cat) {
                          final catColor = _parseColor(cat.color);
                          final isActive = provider.activeCategoryId == cat.id;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () => provider.setActiveCategory(isActive ? null : cat.id),
                              onLongPress: () => _showCategoryOptions(context, cat),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? catColor
                                      : catColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isActive
                                        ? catColor
                                        : catColor.withValues(alpha: 0.6),
                                    width: 1.5,
                                ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: isActive ? Colors.white : catColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${cat.name} (${provider.categoryCounts[cat.id] ?? 0})',
                                      style: TextStyle(
                                        color: isActive ? Colors.white : Colors.white,
                                        fontSize: 12,
                                        fontWeight: isActive
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.more_vert,
                                      size: 14,
                                      color: isActive ? Colors.white70 : Colors.white54,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        // Add category button (admin only)
                        if (!auth.isTeamMember)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => _showCreateCategoryDialog(context),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(Icons.add, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Scan area indicator / barcode tracker
          _BarcodeTracker(
            corners: _barcodeCorners,
            cameraSize: _cameraSize,
            focusResiMode: _focusResiMode,
          ),

          Positioned(
            right: 18,
            bottom: MediaQuery.of(context).padding.bottom + 18,
            child: FloatingActionButton.small(
              heroTag: 'manual_resi_input',
              onPressed: _showManualInputDialog,
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              tooltip: 'Input manual no. resi',
              child: const Icon(Icons.keyboard),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarcodeTracker extends StatelessWidget {
  final List<Offset> corners;
  final Size cameraSize;
  final bool focusResiMode;

  const _BarcodeTracker({
    required this.corners,
    required this.cameraSize,
    required this.focusResiMode,
  });

  @override
  Widget build(BuildContext context) {
    if (corners.isEmpty || cameraSize == Size.zero) {
      // Default scan area box
      return LayoutBuilder(
        builder: (_, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final boxWidth = focusResiMode ? width * 0.7 : 280.0;
          final boxHeight = focusResiMode ? 120.0 : 160.0;
          final top = focusResiMode ? height * 0.18 : (height - boxHeight) / 2;
          final left = (width - boxWidth) / 2;

          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                child: Container(
                  width: boxWidth,
                  height: boxHeight,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: focusResiMode
                          ? Colors.lightGreenAccent.withValues(alpha: 0.85)
                          : Colors.white.withValues(alpha: 0.6),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        focusResiMode ? Icons.center_focus_strong : Icons.qr_code_scanner,
                        color: focusResiMode ? Colors.lightGreenAccent : Colors.white70,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        focusResiMode ? 'Fokus ke barcode No. Resi' : 'Arahkan ke barcode resi',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: focusResiMode ? Colors.lightGreenAccent : Colors.white70,
                          fontSize: 13,
                          fontWeight: focusResiMode ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: cameraSize.width / cameraSize.height,
        child: LayoutBuilder(
          builder: (_, constraints) {
            final scaleX = constraints.maxWidth / cameraSize.width;
            final scaleY = constraints.maxHeight / cameraSize.height;

            final scaledCorners = corners.map((c) => Offset(c.dx * scaleX, c.dy * scaleY)).toList();

            return CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _BarcodeOverlayPainter(corners: scaledCorners),
            );
          },
        ),
      ),
    );
  }
}

class _BarcodeOverlayPainter extends CustomPainter {
  final List<Offset> corners;

  _BarcodeOverlayPainter({required this.corners});

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 4) return;

    final fillPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    // Fill area
    final path = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();
    canvas.drawPath(path, fillPaint);

    // Corner brackets (YOLO style)
    final cornerLen = 20.0;
    final cornerPaint = Paint()
      ..color = const Color(0xFF00E676)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(corners[0], Offset(corners[0].dx + cornerLen, corners[0].dy), cornerPaint);
    canvas.drawLine(corners[0], Offset(corners[0].dx, corners[0].dy + cornerLen), cornerPaint);

    // Top-right
    canvas.drawLine(corners[1], Offset(corners[1].dx - cornerLen, corners[1].dy), cornerPaint);
    canvas.drawLine(corners[1], Offset(corners[1].dx, corners[1].dy + cornerLen), cornerPaint);

    // Bottom-right
    canvas.drawLine(corners[2], Offset(corners[2].dx - cornerLen, corners[2].dy), cornerPaint);
    canvas.drawLine(corners[2], Offset(corners[2].dx, corners[2].dy - cornerLen), cornerPaint);

    // Bottom-left
    canvas.drawLine(corners[3], Offset(corners[3].dx + cornerLen, corners[3].dy), cornerPaint);
    canvas.drawLine(corners[3], Offset(corners[3].dx, corners[3].dy - cornerLen), cornerPaint);

    // Dashed border connecting corners
    final dashPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 4; i++) {
      final start = corners[i];
      final end = corners[(i + 1) % 4];
      _drawDashedLine(canvas, start, end, dashPaint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLen = 6.0;
    const gapLen = 4.0;
    final total = (end - start).distance;
    final dx = (end.dx - start.dx) / total;
    final dy = (end.dy - start.dy) / total;

    double dist = 0;
    while (dist < total) {
      final s = Offset(start.dx + dx * dist, start.dy + dy * dist);
      final eDist = (dist + dashLen).clamp(0, total);
      final e = Offset(start.dx + dx * eDist, start.dy + dy * eDist);
      canvas.drawLine(s, e, paint);
      dist += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodeOverlayPainter old) => old.corners != corners;
}
