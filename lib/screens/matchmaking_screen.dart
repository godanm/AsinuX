import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/firebase_service.dart';
import '../services/auth_service.dart';
import '../services/bot_service.dart';
import 'game_screen.dart';

const _fakeFirstNames = [
  // Indian
  'Arjun', 'Priya', 'Rahul', 'Ananya',
  'Vikram', 'Sneha', 'Karthik', 'Divya',
  'Rohan', 'Meera', 'Aditya', 'Kavya',
  'Siddharth', 'Pooja', 'Nikhil', 'Isha',
  'Abhishek', 'Shreya', 'Varun', 'Riya',
  'Akash', 'Nisha', 'Manish', 'Tanvi',
  'Gaurav', 'Simran', 'Kunal', 'Deepa',
  'Ajay', 'Kritika', 'Suresh', 'Payal',
  'Yash', 'Bhavna', 'Harish', 'Sonali',
  // Non-Indian
  'Alex', 'Emma', 'Jake', 'Olivia',
  'Liam', 'Sophia', 'Noah', 'Ava',
  'Ethan', 'Mia', 'Mason', 'Chloe',
  'Logan', 'Zoe', 'Lucas', 'Lily',
  'Ryan', 'Natalie', 'Tyler', 'Hannah',
  'Jordan', 'Kayla', 'Dylan', 'Amber',
  'Chase', 'Lexi', 'Caleb', 'Sierra',
  'Max', 'Jade', 'Sam', 'Brooke',
];

const _fakeSuffixes = [
  'ace', 'x', 'pro', 'gg', 'xo', 'ez',
  'fx', 'zz', 'ok', 'yo', 'mvp', 'no1',
  'xd', 'op', 'idk', 'lol', 'irl', 'afk',
  'tryhard', 'clutch', 'god', 'bot', 'carry', 'noob',
];

String _fakeName(Random rng) {
  final base = _fakeFirstNames[rng.nextInt(_fakeFirstNames.length)];
  final suffix = _fakeSuffixes[rng.nextInt(_fakeSuffixes.length)];
  final num = rng.nextInt(900) + 100; // 100–999
  return '${base}_$suffix$num';
}

class MatchmakingScreen extends StatefulWidget {
  final String playerName;
  final BotDifficulty difficulty;

  const MatchmakingScreen({
    super.key,
    required this.playerName,
    required this.difficulty,
  });

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> {
  final _random = Random();
  // Slot 0 = the real player. Slots 1–3 = fake joiners.
  final List<String?> _slots = [null, null, null, null];
  late final List<String> _generatedBotNames;
  bool _launching = false;
  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    _slots[0] = widget.playerName; // Real player is already "in"
    _generatedBotNames = List.generate(3, (_) => _fakeName(_random));
    _scheduleFakeJoins();
  }

  void _scheduleFakeJoins() {
    final names = _generatedBotNames;

    // Stagger them: 1.2s, 2.8s, 4.4s (feels natural)
    final delays = [1200, 2800, 4400];
    for (int i = 0; i < 3; i++) {
      final slotIndex = i + 1;
      final name = names[i];
      final t = Timer(Duration(milliseconds: delays[i]), () {
        if (!mounted) return;
        setState(() => _slots[slotIndex] = name);
        if (slotIndex == 3) {
          // All 4 filled — short pause then launch
          _timers.add(Timer(const Duration(milliseconds: 900), _launch));
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
      var state = await FirebaseService.instance.createRoom(
        playerId: user.uid,
        playerName: widget.playerName,
      );
      await BotService.instance.addBots(state, 3, names: _generatedBotNames);
      final fresh = await FirebaseService.instance.getFreshState(state.roomId);
      if (fresh != null) state = fresh;
      BotService.instance.start(state.roomId, difficulty: widget.difficulty);
      await FirebaseService.instance.startGame(state);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GameScreen(roomId: state.roomId, playerId: user.uid),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start: $e'), backgroundColor: Colors.red.shade700),
        );
        setState(() => _launching = false);
      }
    }
  }

  @override
  void dispose() {
    for (final t in _timers) { t.cancel(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filledCount = _slots.where((s) => s != null).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0d0007),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Spinner / checkmark
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: _launching
                      ? const Icon(Icons.check_circle,
                          key: ValueKey('check'),
                          color: Color(0xFFE63946),
                          size: 72)
                      : SizedBox(
                          key: const ValueKey('spin'),
                          width: 72,
                          height: 72,
                          child: CircularProgressIndicator(
                            value: filledCount / 4,
                            color: const Color(0xFFE63946),
                            backgroundColor: Colors.white12,
                            strokeWidth: 3,
                          ),
                        ),
                ),
                const SizedBox(height: 32),

                Text(
                  _launching ? 'Match Found!' : 'Finding Players',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _launching
                      ? 'Starting game...'
                      : '$filledCount / 4 players joined',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 32),

                // Player slots
                ...List.generate(4, (i) {
                  final name = _slots[i];
                  final isMe = i == 0;
                  return _PlayerSlot(
                    name: name,
                    isMe: isMe,
                    index: i,
                  );
                }),

                const SizedBox(height: 40),

                if (!_launching)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'CANCEL',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        letterSpacing: 2,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerSlot extends StatelessWidget {
  final String? name;
  final bool isMe;
  final int index;

  const _PlayerSlot({
    required this.name,
    required this.isMe,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final filled = name != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: filled
            ? Colors.green.shade900.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: filled ? Colors.green.shade700 : Colors.white12,
          width: filled ? 1.2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            filled ? Icons.person : Icons.person_outline,
            color: filled ? Colors.green.shade400 : Colors.white24,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Align(
                key: ValueKey(name ?? 'empty_$index'),
                alignment: Alignment.centerLeft,
                child: Text(
                  filled
                      ? '${name!}${isMe ? ' (You)' : ''}'
                      : 'Waiting...',
                  style: TextStyle(
                    color: filled
                        ? (isMe ? const Color(0xFFE63946) : Colors.green.shade400)
                        : Colors.white24,
                    fontSize: 13,
                    fontWeight: filled ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
          if (filled)
            Icon(Icons.check_circle,
                color: isMe ? const Color(0xFFE63946) : Colors.green.shade400,
                size: 16)
              .animate()
              .scale(begin: const Offset(0, 0), duration: 250.ms, curve: Curves.elasticOut),
        ],
      ),
    );
  }
}
