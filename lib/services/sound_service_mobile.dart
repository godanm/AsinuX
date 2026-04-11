import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class SoundService {
  static final SoundService _instance = SoundService._();
  static SoundService get instance => _instance;
  SoundService._();

  final _cardPlayer = AudioPlayer();
  final _cutPlayer = AudioPlayer();
  final _escapePlayer = AudioPlayer();
  final _donkeyPlayer = AudioPlayer();
  final _turnPlayer = AudioPlayer();

  bool _muted = false;
  bool get muted => _muted;

  Future<void> initialize() async {
    await _cardPlayer.setReleaseMode(ReleaseMode.stop);
    await _cutPlayer.setReleaseMode(ReleaseMode.stop);
    await _escapePlayer.setReleaseMode(ReleaseMode.stop);
    await _donkeyPlayer.setReleaseMode(ReleaseMode.stop);
    await _turnPlayer.setReleaseMode(ReleaseMode.stop);
  }

  void toggleMute() => _muted = !_muted;

  Future<void> playCardSlap() => _play(_cardPlayer, 'sounds/card_play.wav');
  Future<void> playCut()      => _play(_cutPlayer,  'sounds/cut.wav');
  Future<void> playEscape()   => _play(_escapePlayer, 'sounds/escape.wav');
  Future<void> playDonkey()   => _play(_donkeyPlayer, 'sounds/donkey.wav');
  Future<void> playYourTurn() => _play(_turnPlayer, 'sounds/your_turn.wav');

  Future<void> _play(AudioPlayer player, String asset) async {
    if (_muted) return;
    try {
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (e) {
      debugPrint('[SoundService] Failed to play $asset: $e');
    }
  }

  void dispose() {
    _cardPlayer.dispose();
    _cutPlayer.dispose();
    _escapePlayer.dispose();
    _donkeyPlayer.dispose();
    _turnPlayer.dispose();
  }
}
