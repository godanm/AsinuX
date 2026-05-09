import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/auth_service.dart';
import '../services/error_log_service.dart';
import '../services/tambola_service.dart';
import '../widgets/how_to_play_overlay.dart';
import '../widgets/player_avatar.dart';
import 'tambola_lobby_screen.dart';

class TambolaMatchmakingScreen extends StatefulWidget {
  final String playerName;
  const TambolaMatchmakingScreen({super.key, required this.playerName});

  @override
  State<TambolaMatchmakingScreen> createState() =>
      _TambolaMatchmakingScreenState();
}

class _TambolaMatchmakingScreenState extends State<TambolaMatchmakingScreen> {
  int _selectedCount = 4;
  bool _searching = false;
  AvatarPreset _avatar = const AvatarPreset(colorIndex: -1, iconIndex: -1);

  static const _counts = [2, 4, 6];
  static const _accent = Color(0xFFF57C00);
  static const _accentDark = Color(0xFF7f3c00);

  @override
  void initState() {
    super.initState();
    AuthService.instance
        .loadAvatar()
        .then((p) => mounted ? setState(() => _avatar = p) : null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF04061a),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    onPressed: _searching ? null : () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  ShaderMask(
                    shaderCallback: (b) => const LinearGradient(
                      colors: [Color(0xFFF57C00), Color(0xFFFFCC02), Color(0xFFF57C00)],
                    ).createShader(b),
                    child: const Text(
                      'TAMBOLA',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.help_outline_rounded,
                        color: Colors.white54),
                    onPressed: () =>
                        showHowToPlay(context, game: 'tambola'),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 24),

                    // ── Avatar ─────────────────────────────────────
                    PlayerAvatarWidget(
                      radius: 36,
                      playerId: widget.playerName,
                      playerName: widget.playerName,
                      preset: _avatar,
                    ).animate().fadeIn(duration: 400.ms).scale(
                        begin: const Offset(0.8, 0.8)),

                    const SizedBox(height: 12),

                    Text(
                      widget.playerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ).animate().fadeIn(delay: 100.ms),

                    const SizedBox(height: 32),

                    // ── Player count ───────────────────────────────
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'PLAYERS AT TABLE',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ).animate().fadeIn(delay: 200.ms),

                    const SizedBox(height: 12),

                    Row(
                      children: _counts.map((count) {
                        final selected = _selectedCount == count;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                                right: count != _counts.last ? 10 : 0),
                            child: GestureDetector(
                              onTap: _searching
                                  ? null
                                  : () =>
                                      setState(() => _selectedCount = count),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                height: 72,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: selected
                                      ? const LinearGradient(
                                          colors: [_accent, _accentDark],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  color: selected
                                      ? null
                                      : Colors.white.withValues(alpha: 0.05),
                                  border: Border.all(
                                    color: selected
                                        ? _accent.withValues(alpha: 0.7)
                                        : Colors.white.withValues(alpha: 0.1),
                                    width: selected ? 1.5 : 1,
                                  ),
                                  boxShadow: selected
                                      ? [
                                          BoxShadow(
                                            color: _accent.withValues(
                                                alpha: 0.4),
                                            blurRadius: 16,
                                            spreadRadius: 1,
                                          )
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$count',
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : Colors.white
                                                .withValues(alpha: 0.45),
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      'players',
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white.withValues(alpha: 0.7)
                                            : Colors.white
                                                .withValues(alpha: 0.25),
                                        fontSize: 10,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.15),

                    const SizedBox(height: 12),

                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _tableDesc(_selectedCount),
                        key: ValueKey(_selectedCount),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 12,
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── How it works ───────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _accent.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HOW IT WORKS',
                            style: TextStyle(
                              color: _accent.withValues(alpha: 0.8),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...[
                            '🎟  Each player gets a 3×9 ticket with 15 numbers',
                            '🔢  Numbers 1–90 are called one by one automatically',
                            '🏆  Claim Early Five, Lines, and Full House to win',
                            '🎉  Full House ends the game',
                          ].map((t) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  t,
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.55),
                                    fontSize: 12,
                                  ),
                                ),
                              )),
                        ],
                      ),
                    ).animate().fadeIn(delay: 400.ms),
                  ],
                ),
              ),
            ),

            // ── Find match button ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _searching ? null : _findMatch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    disabledBackgroundColor: _accent.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _searching
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'FINDING TABLE…',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_rounded,
                                color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'FIND MATCH',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                ),
              ).animate().fadeIn(delay: 450.ms).slideY(begin: 0.1),
            ),
          ],
        ),
      ),
    );
  }

  String _tableDesc(int count) => switch (count) {
        2 => 'Head-to-head — fills instantly',
        4 => 'Classic Housie — most popular',
        6 => 'Full table — traditional format',
        _ => '',
      };

  Future<void> _findMatch() async {
    setState(() => _searching = true);
    try {
      final user = await AuthService.instance.signInAnonymously();
      final roomId = await TambolaService.instance.findOrCreateRoom(
        playerId: user.uid,
        playerName: widget.playerName,
        maxPlayers: _selectedCount,
      );
      await TambolaService.instance.fillRoomWithBots(
        roomId: roomId,
        maxPlayers: _selectedCount,
        currentCount: 1,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TambolaLobbyScreen(
            roomId: roomId,
            playerId: user.uid,
            playerName: widget.playerName,
            maxPlayers: _selectedCount,
          ),
        ),
      );
    } catch (e, st) {
      ErrorLogService.instance.logAuto(game: 'tambola', error: e.toString(), stack: st);
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not find a table: $e'),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }
}
