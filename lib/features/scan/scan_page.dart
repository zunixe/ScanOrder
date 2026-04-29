import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme.dart';
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

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      returnImage: true,
    );
    context.read<ScanProvider>().loadCounts();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_onCooldown) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final code = barcode.rawValue!;
    if (code == _lastScannedCode) return;

    _lastScannedCode = code;
    _onCooldown = true;
    _cooldownTimer = Timer(const Duration(seconds: 2), () {
      _onCooldown = false;
    });

    _handleScan(code, capture);
  }

  Future<void> _handleScan(String code, BarcodeCapture capture) async {
    final provider = context.read<ScanProvider>();
    
    // Capture photo from the BarcodeCapture (mobile_scanner returnImage: true)
    String? photoPath;
    try {
      if (capture.image != null && capture.image!.isNotEmpty) {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(path);
        await file.writeAsBytes(capture.image!);
        photoPath = path;
        debugPrint('Photo saved to: $photoPath');
      } else {
        debugPrint('capture.image is null or empty');
      }
    } catch (e) {
      debugPrint('Failed to capture photo: $e');
    }
    
    final result = await provider.processScan(code, photoPath);
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

      case ScanStatus.quotaExceeded:
        Vibration.vibrate(duration: 300);
        if (mounted) _showQuotaDialog();
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
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showQuotaDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kuota Habis'),
        content: const Text(
          'Kuota gratis 50 order sudah habis.\nUpgrade ke Pro untuk scan tanpa batas!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Nanti'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Navigate to subscription page
              DefaultTabController.of(context).animateTo(3);
            },
            child: const Text('Upgrade Pro'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} $h:$m';
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
              child: Consumer<ScanProvider>(
                builder: (_, provider, _) => Row(
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
                          'Hari ini: ${provider.todayCount} order',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
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
                        // Photo save toggle
                        Consumer<ScanProvider>(
                          builder: (_, provider, __) => IconButton(
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
                ),
              ),
            ),
          ),

          // Scan area indicator
          Center(
            child: Container(
              width: 280,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner, color: Colors.white70, size: 32),
                  SizedBox(height: 8),
                  Text(
                    'Arahkan ke barcode resi',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
