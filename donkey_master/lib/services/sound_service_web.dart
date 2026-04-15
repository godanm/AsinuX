import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class SoundService {
  static final SoundService _instance = SoundService._();
  static SoundService get instance => _instance;
  SoundService._();

  web.AudioContext? _ctx;
  bool _muted = false;
  bool get muted => _muted;

  web.AudioContext get _context {
    _ctx ??= web.AudioContext();
    return _ctx!;
  }

  Future<void> initialize() async {}

  void toggleMute() => _muted = !_muted;
  void dispose() {}

  /// Must be called on a user gesture to unlock the AudioContext.
  Future<void> _resume() async {
    final ctx = _context;
    if (ctx.state == 'suspended') {
      await ctx.resume().toDart;
    }
  }

  double get _now => _context.currentTime;

  // ── Tone helper ───────────────────────────────────────────────

  void _tone({
    required double freq,
    required double duration,
    required double volume,
    String type = 'sine',
    double when = 0,
    double endFreq = -1,
  }) {
    final ctx = _context;
    final osc = ctx.createOscillator();
    final gain = ctx.createGain();
    final t = _now + when;

    osc.type = type;
    osc.frequency.setValueAtTime(freq, t);
    if (endFreq > 0) {
      osc.frequency.linearRampToValueAtTime(endFreq, t + duration);
    }
    gain.gain.setValueAtTime(volume, t);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + duration);

    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(t);
    osc.stop(t + duration + 0.02);
  }

  // ── Sounds ────────────────────────────────────────────────────

  Future<void> playCardSlap() async {
    if (_muted) return;
    try {
      await _resume();
      // Short high-pitched thwack
      _tone(freq: 800, duration: 0.05, volume: 0.4, type: 'sawtooth');
      _tone(freq: 400, duration: 0.08, volume: 0.3, type: 'square', when: 0.01);
    } catch (e) {
      debugPrint('[Sound] cardSlap: $e');
    }
  }

  Future<void> playCut() async {
    if (_muted) return;
    try {
      await _resume();
      // Descending whoosh
      _tone(
        freq: 1000, endFreq: 120,
        duration: 0.3, volume: 0.35, type: 'sawtooth',
      );
    } catch (e) {
      debugPrint('[Sound] cut: $e');
    }
  }

  Future<void> playEscape() async {
    if (_muted) return;
    try {
      await _resume();
      // Rising C-E-G-C arpeggio
      final freqs = [523.0, 659.0, 784.0, 1047.0];
      for (int i = 0; i < freqs.length; i++) {
        _tone(freq: freqs[i], duration: 0.22, volume: 0.28, when: i * 0.15);
      }
    } catch (e) {
      debugPrint('[Sound] escape: $e');
    }
  }

  Future<void> playDonkey() async {
    if (_muted) return;
    try {
      await _resume();
      // "Hee" — rising
      _tone(freq: 250, endFreq: 450, duration: 0.35, volume: 0.35, type: 'sawtooth');
      // "Haw" — descending
      _tone(freq: 300, endFreq: 140, duration: 0.5, volume: 0.35, type: 'sawtooth', when: 0.42);
    } catch (e) {
      debugPrint('[Sound] donkey: $e');
    }
  }

  Future<void> playYourTurn() async {
    if (_muted) return;
    try {
      await _resume();
      _tone(freq: 880, duration: 0.18, volume: 0.2);
      _tone(freq: 1100, duration: 0.22, volume: 0.2, when: 0.2);
    } catch (e) {
      debugPrint('[Sound] yourTurn: $e');
    }
  }
}
