import 'dart:async';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final Widget next;
  const SplashScreen({super.key, required this.next});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoScale;
  late Animation<double> _textOpacity;
  late Animation<double> _shimmerPosition;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.65, curve: Curves.easeIn),
      ),
    );

    _shimmerPosition = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.6, 1.0, curve: Curves.easeInOut),
      ),
    );

    _controller.forward();

    // Navigate after animation + short hold
    Timer(const Duration(milliseconds: 1000), () {
      if (!mounted || _navigated) return;
      _navigated = true;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => widget.next,
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 300),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D1B2A) : const Color(0xFF1565C0);
    final fg = Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background decorative circles
          _buildBackgroundCircles(bg, isDark),

          // Main content
          AnimatedBuilder(
            animation: _controller,
            builder: (_, __) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo with scale animation
                  Transform.scale(
                    scale: _logoScale.value,
                    child: _buildLogo(fg),
                  ),
                  const SizedBox(height: 24),

                  // App name with fade-in
                  Opacity(
                    opacity: _textOpacity.value,
                    child: Text(
                      'ScanOrder',
                      style: TextStyle(
                        color: fg,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Tagline with shimmer
                  Opacity(
                    opacity: _textOpacity.value,
                    child: _buildShimmerText(
                      'Scan. Track. Deliver.',
                      fg,
                      isDark,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundCircles(Color bg, bool isDark) {
    final circleColor = (isDark ? Colors.white : Colors.white).withAlpha(15);
    return Stack(
      children: [
        // Top-right circle
        Positioned(
          top: -80,
          right: -60,
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: circleColor,
            ),
          ),
        ),
        // Bottom-left circle
        Positioned(
          bottom: -100,
          left: -80,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: circleColor,
            ),
          ),
        ),
        // Small accent circle
        Positioned(
          top: MediaQuery.of(context).size.height * 0.35,
          left: -30,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: circleColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo(Color fg) {
    return Image.asset(
      'assets/logo/logo.png',
      width: 160,
      height: 160,
      fit: BoxFit.contain,
    );
  }

  Widget _buildShimmerText(String text, Color fg, bool isDark) {
    return ShaderMask(
      shaderCallback: (bounds) {
        final pos = _shimmerPosition.value;
        return LinearGradient(
          begin: Alignment(pos - 0.5, 0),
          end: Alignment(pos + 0.5, 0),
          colors: [
            fg.withAlpha(180),
            fg,
            fg.withAlpha(180),
          ],
        ).createShader(bounds);
      },
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 14,
          letterSpacing: 3,
          fontWeight: FontWeight.w300,
        ),
      ),
    );
  }
}
