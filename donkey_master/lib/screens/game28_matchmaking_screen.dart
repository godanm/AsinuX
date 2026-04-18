import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/auth_service.dart'; // AvatarPreset
import '../services/game28_service.dart';
import '../services/game28_bot_service.dart';
import '../widgets/player_avatar.dart';
import 'game28_game_screen.dart';

const _fakeFirstNames = [
  'Arjun', 'Priya', 'Rahul', 'Ananya', 'Vikram', 'Sneha',
  'Karthik', 'Divya', 'Rohan', 'Meera', 'Aditya', 'Kavya',
  'Alex', 'Emma', 'Jake', 'Olivia', 'Liam', 'Sophia',
  'Noah', 'Ava', 'Ethan', 'Mia', 'Logan', 'Zoe',
];
const _fakeSuffixes = [
  'ace', 'pro', 'gg', 'xo', 'mvp', 'clutch', 'god', 'carry',
];

String _fakeName(Random rng) {
  final base = _fakeFirstNames[rng.nextInt(_fakeFirstNames.length)];
  final suffix = _fakeSuffixes[rng.nextInt(_fakeSuffixes.length)];
  final num = rng.nextInt(900) + 100;
  return '${base}_$suffix$num';
}

class Game28MatchmakingScreen extends StatefulWidget {
  final String playerName;
  const Game28MatchmakingScreen({super.key, required this.playerName});

  @override
  State<Game28MatchmakingScreen> createState() =>
      _Game28MatchmakingScreenState();
}

class _Game28MatchmakingScreenState extends State<Game28MatchmakingScreen> {
  final _rng = Random();
  final List<String?> _slots = [null, null, null, null];
  late final List<String> _botNames;
  bool _launching = false;
  final List<Timer> _timers = [];

  // Teams: slots 0&2 = Team A, slots 1&3 = Team B
  static const _teamA = Color(0xFF00c6ff);
  static const _teamB = Color(0xFFE63946);

  @override
  void initState() {
    super.initState();
    _slots[0] = widget.playerName;
    _botNames = List.generate(3, (_) => _fakeName(_rng));
    _scheduleFakeJoins();
  }

  @override
  void dispose() {
    for (final t in _timers) t.cancel();
    super.dispose();
  }

  void _scheduleFakeJoins() {
    final delays = [1000, 2400, 3800];
    for (int i = 0; i < 3; i++) {
      final slotIdx = i + 1;
      final t = Timer(Duration(milliseconds: delays[i]), () {
        if (!mounted) return;
        setState(() => _slots[slotIdx] = _botNames[i]);
        if (slotIdx == 3) {
          _timers.add(Timer(const Duration(milliseconds: 800), _launch));
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
      var state = await Game28Service.instance.createRoom(
        playerId: user.uid,
        playerName: widget.playerName,
      );
      await Game28Service.instance.addBots(state, 3, names: _botNames);
      final fresh = await Game28Service.instance.getFreshState(state.roomId);
      if (fresh != null) state = fresh;
      Game28BotService.instance.start(state.roomId);
      await Game28Service.instance.startGame(state);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => Game28GameScreen(
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

  Color _slotColor(int idx) => idx % 2 == 0 ? _teamA : _teamB;
  String _teamLabel(int idx) => idx % 2 == 0 ? 'Team A' : 'Team B';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0008),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white54, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  const Text('28',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
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
                  // ── Logo ────────────────────────────────────────
                  const Text('🎴',
                      style: TextStyle(fontSize: 48))
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

                  const SizedBox(height: 32),

                  // ── Team label ───────────────────────────────────
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _teamDot(_teamA),
                        const SizedBox(width: 6),
                        Text('Seats 1 & 3',
                            style: TextStyle(
                                fontSize: 11,
                                color: _teamA.withValues(alpha: 0.85))),
                        Container(
                            margin:
                                const EdgeInsets.symmetric(horizontal: 12),
                            width: 1,
                            height: 14,
                            color: Colors.white12),
                        _teamDot(_teamB),
                        const SizedBox(width: 6),
                        Text('Seats 2 & 4',
                            style: TextStyle(
                                fontSize: 11,
                                color: _teamB.withValues(alpha: 0.85))),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Player slots ─────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: List.generate(4, (i) {
                        final name = _slots[i];
                        final teamColor = _slotColor(i);
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
                                  ? teamColor.withValues(alpha: 0.08)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: name != null
                                    ? teamColor.withValues(alpha: 0.3)
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
                                        child: Icon(Icons.person_outline,
                                            color: Colors.white24, size: 18),
                                      ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
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
                                      Text(
                                        _teamLabel(i),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: teamColor
                                              .withValues(alpha: 0.7),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isYou)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: teamColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text('YOU',
                                        style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: teamColor,
                                            letterSpacing: 1)),
                                  )
                                else if (name != null)
                                  Icon(Icons.check_circle_rounded,
                                      color: teamColor.withValues(alpha: 0.7),
                                      size: 18)
                                else
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white24,
                                    ),
                                  ),
                              ],
                            ),
                          ).animate(
                            effects: name != null && i > 0
                                ? [
                                    const FadeEffect(duration: Duration(milliseconds: 400)),
                                    const SlideEffect(
                                        begin: Offset(0, 0.1),
                                        duration: Duration(milliseconds: 400)),
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

  Widget _teamDot(Color color) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}
