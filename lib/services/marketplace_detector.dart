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

    // JNE — berbagai prefix layanan JNE
    if (RegExp(r'^(JN|TLJN|CGK|BDO|SUB|SRG|MDN|UPG|MKS|YGY|PLM|BPN|BTH|CM|OK|MG|MP|CL|IN)\d').hasMatch(upper) ||
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
    if (upper.startsWith('AA') ||
        upper.startsWith('ANTERAJA') ||
        RegExp(r'^11\d{12}$').hasMatch(upper)) {
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

  /// Cek apakah barcode adalah nomor resi yang valid
  /// Menolak: Order ID (angka panjang 15-20 digit), URL, teks random
  static bool isValidResi(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty || trimmed.length < 4) return false;

    // Tolak URL
    if (trimmed.startsWith('http') || trimmed.contains('://')) return false;

    // Tolak angka murni panjang (Order ID Tokopedia/Shopee: 15-20 digit)
    if (RegExp(r'^\d{15,}$').hasMatch(trimmed)) return false;

    // Tolak angka murni pendek (< 8 digit, bukan resi)
    if (RegExp(r'^\d{1,7}$').hasMatch(trimmed)) return false;

    // Terima jika cocok pattern resi yang dikenal
    final marketplace = detect(trimmed);
    if (marketplace != 'Lainnya') return true;

    // Untuk "Lainnya": terima hanya jika alfanumerik 8-30 karakter
    if (RegExp(r'^[A-Za-z0-9\-]{8,30}$').hasMatch(trimmed)) return true;

    return false;
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
