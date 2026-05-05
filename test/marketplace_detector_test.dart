import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/services/marketplace_detector.dart';

void main() {
  group('MarketplaceDetector.detect', () {
    // Shopee
    test('SPX → Shopee', () => expect(MarketplaceDetector.detect('SPX123456789'), 'Shopee'));
    test('SPXID → Shopee', () => expect(MarketplaceDetector.detect('SPXID123456'), 'Shopee'));

    // TikTok
    test('TTS → TikTok', () => expect(MarketplaceDetector.detect('TTS123456'), 'TikTok'));
    test('TKT → TikTok', () => expect(MarketplaceDetector.detect('TKT123456'), 'TikTok'));

    // Tokopedia
    test('TKP → Tokopedia', () => expect(MarketplaceDetector.detect('TKP123456'), 'Tokopedia'));

    // JNE
    test('JN → JNE', () => expect(MarketplaceDetector.detect('JN1234567890'), 'JNE'));
    test('CM → JNE', () => expect(MarketplaceDetector.detect('CM40443408053'), 'JNE'));
    test('OK → JNE', () => expect(MarketplaceDetector.detect('OK1234567890'), 'JNE'));
    test('CGK → JNE', () => expect(MarketplaceDetector.detect('CGK1234567890'), 'JNE'));
    test('BDO → JNE', () => expect(MarketplaceDetector.detect('BDO1234567890'), 'JNE'));
    test('SUB → JNE', () => expect(MarketplaceDetector.detect('SUB1234567890'), 'JNE'));
    test('SRG → JNE', () => expect(MarketplaceDetector.detect('SRG1234567890'), 'JNE'));
    test('MG → JNE', () => expect(MarketplaceDetector.detect('MG1234567890'), 'JNE'));
    test('MP → JNE', () => expect(MarketplaceDetector.detect('MP1234567890'), 'JNE'));
    test('JNE prefix → JNE', () => expect(MarketplaceDetector.detect('JNE123456'), 'JNE'));

    // J&T
    test('JP → J&T', () => expect(MarketplaceDetector.detect('JP1234567890'), 'J&T'));
    test('JD → J&T', () => expect(MarketplaceDetector.detect('JD1234567890'), 'J&T'));
    test('JA → J&T', () => expect(MarketplaceDetector.detect('JA1234567890'), 'J&T'));
    test('JNT → J&T', () => expect(MarketplaceDetector.detect('JNT123456'), 'J&T'));

    // SiCepat
    test('SCP → SiCepat', () => expect(MarketplaceDetector.detect('SCP1234567890'), 'SiCepat'));

    // AnterAja
    test('AA → AnterAja', () => expect(MarketplaceDetector.detect('AA1234567890'), 'AnterAja'));
    test('numeric 14 digit starting 11 → AnterAja', () => expect(MarketplaceDetector.detect('11003703532205'), 'AnterAja'));

    // Ninja
    test('NV → Ninja', () => expect(MarketplaceDetector.detect('NV1234567890'), 'Ninja'));

    // ID Express
    test('IDE → ID Express', () => expect(MarketplaceDetector.detect('IDE1234567890'), 'ID Express'));

    // Lazada
    test('LEX → Lazada', () => expect(MarketplaceDetector.detect('LEX1234567890'), 'Lazada'));
    test('LZD → Lazada', () => expect(MarketplaceDetector.detect('LZD123456'), 'Lazada'));

    // Unknown
    test('XYZ → Lainnya', () => expect(MarketplaceDetector.detect('XYZ1234567890'), 'Lainnya'));

    // Case insensitive
    test('lowercase spx → Shopee', () => expect(MarketplaceDetector.detect('spx123456789'), 'Shopee'));
    test('mixed case Cm → JNE', () => expect(MarketplaceDetector.detect('Cm40443408053'), 'JNE'));

    // Trim whitespace
    test('whitespace trimmed', () => expect(MarketplaceDetector.detect('  SPX123456789  '), 'Shopee'));

    // Additional patterns
    test('26xxxxx pattern → Shopee', () => expect(MarketplaceDetector.detect('2612345ABCDEF'), 'Shopee'));
    test('25xxxxx pattern → Shopee', () => expect(MarketplaceDetector.detect('2512345ABCDEF'), 'Shopee'));
    test('JX prefix → J&T', () => expect(MarketplaceDetector.detect('JX1234567890'), 'J&T'));
    test('JO prefix → J&T', () => expect(MarketplaceDetector.detect('JO1234567890'), 'J&T'));
    test('JT prefix → J&T', () => expect(MarketplaceDetector.detect('JT1234567890'), 'J&T'));
    test('J&T prefix → J&T', () => expect(MarketplaceDetector.detect('J&T123456'), 'J&T'));
    test('SC prefix → SiCepat', () => expect(MarketplaceDetector.detect('SC1234567890'), 'SiCepat'));
    test('SICEPAT prefix → SiCepat', () => expect(MarketplaceDetector.detect('SICEPAT123'), 'SiCepat'));
    test('12-digit number → SiCepat', () => expect(MarketplaceDetector.detect('123456789012'), 'SiCepat'));
    test('ANTERAJA prefix → AnterAja', () => expect(MarketplaceDetector.detect('ANTERAJA123'), 'AnterAja'));
    test('NINJA prefix → Ninja', () => expect(MarketplaceDetector.detect('NINJA123'), 'Ninja'));
    test('15-20 digit number → Tokopedia', () => expect(MarketplaceDetector.detect('123456789012345'), 'Tokopedia'));
    test('TSPX prefix → Paxel', () => expect(MarketplaceDetector.detect('TSPX123456'), 'Paxel'));
    test('TLJN prefix → JNE', () => expect(MarketplaceDetector.detect('TLJN1234567890'), 'JNE'));
    test('MDN prefix → JNE', () => expect(MarketplaceDetector.detect('MDN1234567890'), 'JNE'));
    test('UPG prefix → JNE', () => expect(MarketplaceDetector.detect('UPG1234567890'), 'JNE'));
    test('CL prefix → JNE', () => expect(MarketplaceDetector.detect('CL1234567890'), 'JNE'));
    test('IN prefix → JNE', () => expect(MarketplaceDetector.detect('IN1234567890'), 'JNE'));
  });

  group('MarketplaceDetector.isValidResi', () {
    test('Valid Shopee resi', () => expect(MarketplaceDetector.isValidResi('SPX123456789'), isTrue));
    test('Valid JNE resi', () => expect(MarketplaceDetector.isValidResi('CM40443408053'), isTrue));
    test('Valid J&T resi', () => expect(MarketplaceDetector.isValidResi('JP1234567890'), isTrue));
    test('Valid alphanumeric 8-30 chars', () => expect(MarketplaceDetector.isValidResi('ABCD12345678'), isTrue));

    test('Reject URL', () => expect(MarketplaceDetector.isValidResi('https://example.com'), isFalse));
    test('Reject long pure numbers (Order ID)', () => expect(MarketplaceDetector.isValidResi('123456789012345'), isFalse));
    test('Reject short pure numbers', () => expect(MarketplaceDetector.isValidResi('1234567'), isFalse));
    test('Reject empty', () => expect(MarketplaceDetector.isValidResi(''), isFalse));
    test('Reject too short', () => expect(MarketplaceDetector.isValidResi('AB'), isFalse));
    test('Reject URL with scheme', () => expect(MarketplaceDetector.isValidResi('http://foo.com'), isFalse));
  });

  group('MarketplaceDetector.allMarketplaces', () {
    test('Contains all expected marketplaces', () {
      expect(MarketplaceDetector.allMarketplaces, containsAll([
        'Shopee', 'Tokopedia', 'TikTok', 'Lazada',
        'JNE', 'J&T', 'SiCepat', 'AnterAja',
        'Ninja', 'ID Express', 'Lainnya',
      ]));
    });
  });
}
