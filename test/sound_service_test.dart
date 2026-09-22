import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/services/sound_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SoundService', () {
    test('playScanSuccess does not throw without platform support', () async {
      // audioplayers throws MissingPluginException in tests; the service
      // swallows it, so the call must complete normally.
      await expectLater(SoundService().playScanSuccess(), completes);
    });

    test('playScanDuplicate does not throw without platform support', () async {
      await expectLater(SoundService().playScanDuplicate(), completes);
    });
  });
}
