import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:scanorder/core/theme.dart';

void main() {
  group('AppTheme', () {
    test('getMarketplaceColor returns correct colors', () {
      expect(AppTheme.getMarketplaceColor('Shopee'), AppTheme.shopeeOrange);
      expect(AppTheme.getMarketplaceColor('Tokopedia'), AppTheme.tokopediaGreen);
      expect(AppTheme.getMarketplaceColor('TikTok'), AppTheme.tiktokBlack);
      expect(AppTheme.getMarketplaceColor('Lazada'), AppTheme.lazadaBlue);
      expect(AppTheme.getMarketplaceColor('Paxel'), const Color(0xFF6C5CE7));
      expect(AppTheme.getMarketplaceColor('JNE'), const Color(0xFFD32F2F));
      expect(AppTheme.getMarketplaceColor('J&T'), const Color(0xFFE53935));
      expect(AppTheme.getMarketplaceColor('SiCepat'), const Color(0xFFF57C00));
      expect(AppTheme.getMarketplaceColor('AnterAja'), const Color(0xFF00897B));
      expect(AppTheme.getMarketplaceColor('Ninja'), const Color(0xFFCD2027));
      expect(AppTheme.getMarketplaceColor('ID Express'), const Color(0xFFFF6F00));
    });

    test('getMarketplaceColor returns grey for unknown', () {
      expect(AppTheme.getMarketplaceColor('Unknown'), Colors.grey);
      expect(AppTheme.getMarketplaceColor(''), Colors.grey);
    });

    test('lightTheme is valid ThemeData', () {
      final theme = AppTheme.lightTheme;
      expect(theme, isA<ThemeData>());
      expect(theme.useMaterial3, true);
    });

    test('darkTheme is valid ThemeData', () {
      final theme = AppTheme.darkTheme;
      expect(theme, isA<ThemeData>());
      expect(theme.useMaterial3, true);
    });

    test('color constants are not zero', () {
      expect(AppTheme.primaryColor, isNot(equals(const Color(0x00000000))));
      expect(AppTheme.successColor, isNot(equals(const Color(0x00000000))));
      expect(AppTheme.dangerColor, isNot(equals(const Color(0x00000000))));
      expect(AppTheme.warningColor, isNot(equals(const Color(0x00000000))));
    });

    test('typography scale constants', () {
      expect(AppTheme.heroSize, 24);
      expect(AppTheme.sectionTitleSize, 16);
      expect(AppTheme.cardTitleSize, 14);
      expect(AppTheme.bodySize, 13);
      expect(AppTheme.captionSize, 12);
      expect(AppTheme.microSize, 11);
    });
  });
}
