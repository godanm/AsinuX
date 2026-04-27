import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/auth_service.dart';
import '../services/teen_patti_service.dart';
import '../services/teen_patti_bot_service.dart';
import '../widgets/player_avatar.dart';
import 'teen_patti_game_screen.dart';

const _fakeFirstNames = [
  'Arjun', 'Priya', 'Rahul', 'Ananya', 'Vikram', 'Sneha',
  'Karthik', 'Divya', 'Rohan', 'Meera', 'Aditya', 'Kavya',
];
const _fakeSuffixes = ['ace', 'pro', 'gg', 'xo', 'mvp', 'clutch'];

String _fakeName(Random rng) {
  final base = _fakeFirstNames[rng.nextInt(_fakeFirstNames.length)];
  final suffix = _fakeSuffixes[rng.nextInt(_fakeSuffixes.length)];
  final num = rng.nextInt(900) + 100;
  return '${base}_$suffix$num';
}

class TeenPattiMatchmakingScreen extends StatefulWidget {
  final String playerName;
  const TeenPattiMatchmakingScreen({super.key, required this.playerName});

  @override
  State<TeenPattiMatchmakingScreen> createState() =>
      _TeenPattiMatchmakingScreenState();
}

class _TeenPattiMatchmakingScreenState
    extends State<TeenPattiMatchmakingScreen> {
  final _rng = Random();
  final List<String?> _slots = [null, null, null, null];
  bool _launching = false;
  final List<Timer> _timers = [];

  static const _accent = Color(0xFF2979FF);

  @override
  void initState() {
    super.initState();
    _slots[0] = widget.playerName;
    _scheduleFakeJoins();
  }

  @override
  void dispose() {
    for (final t in _timers) { t.cancel(); }
    super.dispose();
  }

  void _scheduleFakeJoins() {
    final delays = [900, 2100, 3400];
    for (int i = 0; i < 3; i++) {
      final slotIdx = i + 1;
      final t = Timer(Duration(milliseconds: delays[i]), () {
        if (!mounted) return;
        setState(() => _slots[slotIdx] = _fakeName(_rng));
        if (slotIdx == 3) {
          _timers.add(Timer(const Duration(milliseconds: 700), _launch));
        }
      });
      _timers.add(t);
    }
  }

  Future<void> _launch() async {
    if (!mounted || _launching) return;
    setState(() => _launching = true);
    try {
      final user = await AuthService.instance.signInAnonymously();
      var state = await TeenPattiService.instance.createRoom(
        playerId: user.uid,
        playerName: widget.playerName,
      );
      await TeenPattiService.instance.addBots(state, 3);
      final fresh =
          await TeenPattiService.instance.getFreshState(state.roomId);
      if (fresh != null) state = fresh;
      TeenPattiBotService.instance.start(state.roomId);
      await TeenPattiService.instance.startGame(state);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TeenPattiGameScreen(
            roomId: state.roomId,
            playerId: user.uid,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _launching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0008),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white54, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  const Text('TEEN PATTI',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: Colors.white)),
                  const Spacer(),
                  const SizedBox(width: 44),
                ],
              ),
            ),

            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🌹', style: TextStyle(fontSize: 48))
                      .animate()
                      .fadeIn(duration: 500.ms),
                  const SizedBox(height: 8),
                  Text(
                    _launching ? 'Starting game…' : 'Finding players…',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.45),
                        letterSpacing: 2),
                  ).animate().fadeIn(delay: 200.ms),

                  const SizedBox(height: 36),

                  // ── Player slots ─────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: List.generate(4, (i) {
                        final name = _slots[i];
                        final isYou = i == 0;
                        return AnimatedOpacity(
                          opacity: name != null ? 1.0 : 0.35,
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: name != null
                                  ? _accent.withValues(alpha: 0.08)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: name != null
                                    ? _accent.withValues(alpha: 0.3)
                                    : Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Row(
                              children: [
                                name != null
                                    ? PlayerAvatarWidget(
                                        radius: 18,
                                        playerId: name,
                                        playerName: name,
                                        preset: const AvatarPreset(
                                            colorIndex: -1, iconIndex: -1),
                                      )
                                    : Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white
                                              .withValues(alpha: 0.05),
                                        ),
                                        child: const Icon(Icons.person_outline,
                                            color: Colors.white24, size: 18),
                                      ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    name != null
                                        ? name.replaceAll('_', ' ')
                                        : 'Waiting…',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: name != null
                                          ? Colors.white
                                          : Colors.white24,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isYou)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('YOU',
                                        style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: _accent,
                                            letterSpacing: 1)),
                                  )
                                else if (name != null)
                                  Icon(Icons.check_circle_rounded,
                                      color: _accent.withValues(alpha: 0.7),
                                      size: 18)
                                else
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white24),
                                  ),
                              ],
                            ),
                          ).animate(
                            effects: name != null && i > 0
                                ? [
                                    const FadeEffect(
                                        duration:
                                            Duration(milliseconds: 400)),
                                    const SlideEffect(
                                        begin: Offset(0, 0.1),
                                        duration:
                                            Duration(milliseconds: 400)),
                                  ]
                                : [],
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
