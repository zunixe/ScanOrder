import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Sound effect service for scan feedback
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _player = AudioPlayer();

  /// Play scan success sound (short beep)
  Future<void> playScanSuccess() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/scan_success.mp3'));
    } catch (e) {
      debugPrint('[SoundService] playScanSuccess error: $e');
    }
  }

  /// Play duplicate/error sound (buzzer)
  Future<void> playScanDuplicate() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/scan_duplicate.mp3'));
    } catch (e) {
      debugPrint('[SoundService] playScanDuplicate error: $e');
    }
  }

  /// Dispose player
  void dispose() {
    _player.dispose();
  }
}
