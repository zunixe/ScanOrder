class MarketplaceDetector {
  static String detect(String resi) {
    final upper = resi.toUpperCase().trim();

    // Shopee - SPX, SPXID
    if (upper.startsWith('SPX') || upper.startsWith('SPXID')) {
      return 'Shopee';
    }

    // TikTok Shop - TTS, TKT
    if (upper.startsWith('TTS') || upper.startsWith('TKT')) {
      return 'TikTok';
    }

    // Tokopedia - TKP patterns
    if (upper.startsWith('TKP')) {
      return 'Tokopedia';
    }

    // JNE
    if (RegExp(r'^(JN|TLJN|CGK|BDO|SUB|SRG)\d').hasMatch(upper) ||
        upper.startsWith('JNE')) {
      return 'JNE';
    }

    // J&T - common patterns: JP, JD, JA, JX, JO, JT + digits
    if (RegExp(r'^(JP|JD|JA|JX|JO|JT)\d').hasMatch(upper) ||
        upper.startsWith('J&T') ||
        upper.startsWith('JNT')) {
      return 'J&T';
    }

    // SiCepat
    if (upper.startsWith('SC') ||
        upper.startsWith('SCP') ||
        upper.startsWith('SICEPAT') ||
        RegExp(r'^\d{12}$').hasMatch(upper)) {
      return 'SiCepat';
    }

    // AnterAja
    if (upper.startsWith('AA') || upper.startsWith('ANTERAJA')) {
      return 'AnterAja';
    }

    // Ninja Express
    if (upper.startsWith('NV') || upper.startsWith('NINJA')) {
      return 'Ninja';
    }

    // ID Express
    if (upper.startsWith('IDE')) {
      return 'ID Express';
    }

    // Lazada - LEX
    if (upper.startsWith('LEX') || upper.startsWith('LZD')) {
      return 'Lazada';
    }

    return 'Lainnya';
  }

  static const List<String> allMarketplaces = [
    'Shopee',
    'Tokopedia',
    'TikTok',
    'Lazada',
    'JNE',
    'J&T',
    'SiCepat',
    'AnterAja',
    'Ninja',
    'ID Express',
    'Lainnya',
  ];
}
