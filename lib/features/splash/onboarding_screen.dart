import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingDone = 'onboarding_done';

/// Returns true if onboarding should be shown (first launch).
Future<bool> shouldShowOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kOnboardingDone) != true;
}

class OnboardingScreen extends StatefulWidget {
  final Widget next;
  const OnboardingScreen({super.key, required this.next});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;
  static const _pageCount = 4;

  void _nextPage() {
    if (_currentPage < _pageCount - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingDone, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => widget.next,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _skip() {
    _finish();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1B2A) : Colors.white;
    final accent = const Color(0xFF1565C0);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _skip,
                child: Text(
                  'Lewati',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontSize: 14,
                  ),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pageCount,
                onPageChanged: (i) => setState(() => _currentPage = i),
                physics: const BouncingScrollPhysics(),
                itemBuilder: (_, i) => _OnboardingPage(
                  index: i,
                  accent: accent,
                  isDark: isDark,
                ),
              ),
            ),

            // Indicators + button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Dot indicators
                  Row(
                    children: List.generate(_pageCount, (i) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(right: 8),
                        width: _currentPage == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? accent
                              : (isDark ? Colors.white24 : Colors.black12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),

                  // Next / Mulai button
                  FilledButton(
                    onPressed: _nextPage,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Text(
                      _currentPage == _pageCount - 1 ? 'Mulai' : 'Lanjut',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final int index;
  final Color accent;
  final bool isDark;

  const _OnboardingPage({
    required this.index,
    required this.accent,
    required this.isDark,
  });

  static const _pages = [
    _PageData(
      icon: Icons.qr_code_scanner_rounded,
      title: 'Scan Resi Instan',
      desc: 'Pindai barcode atau QR code resi pengiriman hanya dalam hitungan detik. Mendukung semua ekspedisi populer di Indonesia.',
    ),
    _PageData(
      icon: Icons.cloud_sync_rounded,
      title: 'Sinkronisasi Cloud',
      desc: 'Data tersimpan aman di cloud. Login dari perangkat manapun dan data Anda tetap tersinkronisasi secara otomatis.',
    ),
    _PageData(
      icon: Icons.group_rounded,
      title: 'Mode Tim',
      desc: 'Kerja sama dengan tim Anda. Admin membuat tim, anggota bergabung dengan kode undangan. Semua data tersinkronisasi real-time.',
    ),
    _PageData(
      icon: Icons.bar_chart_rounded,
      title: 'Statistik Lengkap',
      desc: 'Pantau performa pengiriman dengan grafik dan statistik detail. Ketahui tren pengiriman per marketplace dan ekspedisi.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final page = _pages[index];
    final fg = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subFg = isDark ? Colors.white70 : Colors.black54;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated icon container
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (_, val, child) {
              return Transform.scale(
                scale: val,
                child: child,
              );
            },
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: accent.withAlpha(20),
                shape: BoxShape.circle,
                border: Border.all(color: accent.withAlpha(40), width: 2),
              ),
              child: Icon(
                page.icon,
                size: 64,
                color: accent,
              ),
            ),
          ),

          const SizedBox(height: 40),

          // Title
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: fg,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(height: 16),

          // Description
          Text(
            page.desc,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: subFg,
              fontSize: 15,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageData {
  final IconData icon;
  final String title;
  final String desc;
  const _PageData({
    required this.icon,
    required this.title,
    required this.desc,
  });
}
