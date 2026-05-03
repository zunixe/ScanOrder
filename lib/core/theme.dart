import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF1565C0);
  static const Color successColor = Color(0xFF2E7D32);
  static const Color dangerColor = Color(0xFFC62828);
  static const Color warningColor = Color(0xFFEF6C00);
  static const Color surfaceColor = Color(0xFFF5F5F5);

  // Typography scale
  static const double heroSize = 24;
  static const double sectionTitleSize = 16;
  static const double cardTitleSize = 14;
  static const double bodySize = 13;
  static const double captionSize = 12;
  static const double microSize = 11;

  static const Color shopeeOrange = Color(0xFFEE4D2D);
  static const Color tokopediaGreen = Color(0xFF42B549);
  static const Color tiktokBlack = Color(0xFF010101);
  static const Color lazadaBlue = Color(0xFF0F1689);

  static Color getMarketplaceColor(String marketplace) {
    switch (marketplace) {
      case 'Shopee':
        return shopeeOrange;
      case 'Tokopedia':
        return tokopediaGreen;
      case 'TikTok':
        return tiktokBlack;
      case 'Lazada':
        return lazadaBlue;
      case 'Paxel':
        return const Color(0xFF6C5CE7);
      case 'JNE':
        return const Color(0xFFD32F2F);
      case 'J&T':
        return const Color(0xFFE53935);
      case 'SiCepat':
        return const Color(0xFFF57C00);
      case 'AnterAja':
        return const Color(0xFF00897B);
      case 'Ninja':
        return const Color(0xFFCD2027);
      case 'ID Express':
        return const Color(0xFFFF6F00);
      default:
        return Colors.grey;
    }
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 4,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
