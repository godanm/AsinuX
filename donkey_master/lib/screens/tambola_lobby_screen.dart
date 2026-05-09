import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/auth_service.dart';
import '../services/error_log_service.dart';
import '../services/tambola_service.dart';
import '../widgets/player_avatar.dart';
import 'tambola_game_screen.dart';

class TambolaLobbyScreen extends StatefulWidget {
  final String roomId;
  final String playerId;
  final String playerName;
  final int maxPlayers;

  const TambolaLobbyScreen({
    super.key,
    required this.roomId,
    required this.playerId,
    required this.playerName,
    required this.maxPlayers,
  });

  @override
  State<TambolaLobbyScreen> createState() => _TambolaLobbyScreenState();
}

class _TambolaLobbyScreenState extends State<TambolaLobbyScreen> {
  StreamSubscription<Map<String, dynamic>?>? _sub;
  Map<String, dynamic> _room = {};
  bool _starting = false;

  static const _accent = Color(0xFFF57C00);

  @override
  void initState() {
    super.initState();
    _sub = TambolaService.instance
        .roomStream(widget.roomId)
        .listen(_onRoomUpdate);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onRoomUpdate(Map<String, dynamic>? room) {
    if (room == null) {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    if (mounted) setState(() => _room = room);

    if (room['status'] == 'started' && mounted) {
      _sub?.cancel();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TambolaGameScreen(
            roomId: widget.roomId,
            playerId: widget.playerId,
            playerName: widget.playerName,
            isHost: _isHost,
          ),
        ),
      );
    }
  }

  Map<String, dynamic> get _players {
    final p = _room['players'];
    if (p == null) return {};
    return Map<String, dynamic>.from(p as Map);
  }

  bool get _isHost => _room['hostId'] == widget.playerId;

  Future<void> _startGame() async {
    setState(() => _starting = true);
    try {
      await TambolaService.instance.startGame(widget.roomId);
    } catch (e, st) {
      ErrorLogService.instance.logAuto(game: 'tambola', error: e.toString(), stack: st);
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not start: $e'),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final players = _players;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0a0820),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Leave lobby?',
                style: TextStyle(color: Colors.white)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('STAY',
                    style: TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent),
                child: const Text('LEAVE'),
              ),
            ],
          ),
        );
        if (leave == true && mounted) {
          await TambolaService.instance
              .leaveRoom(widget.roomId, widget.playerId);
          nav.popUntil((r) => r.isFirst);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF04061a),
        body: SafeArea(
          child: Column(
            children: [
              // ── Header ────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      icon:
                          const Icon(Icons.close, color: Colors.white54),
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        await TambolaService.instance
                            .leaveRoom(widget.roomId, widget.playerId);
                        nav.popUntil((r) => r.isFirst);
                      },
                    ),
                    const Spacer(),
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [Color(0xFFF57C00), Color(0xFFFFCC02)],
                      ).createShader(b),
                      child: const Text(
                        'TAMBOLA',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),

                      Text(
                        'WAITING FOR HOST',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ).animate(
                        onPlay: (c) => c.repeat(),
                      ).fadeIn(duration: 600.ms).then().fadeOut(duration: 600.ms),

                      const SizedBox(height: 24),

                      // ── Player list ───────────────────────────────
                      Expanded(
                        child: ListView.separated(
                          itemCount: players.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) {
                            final entry = players.entries.elementAt(i);
                            final pid = entry.key;
                            final name = (entry.value['name'] as String?) ?? pid;
                            final isBot = pid.startsWith('bot_');
                            final isMe = pid == widget.playerId;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? _accent.withValues(alpha: 0.08)
                                    : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isMe
                                      ? _accent.withValues(alpha: 0.3)
                                      : Colors.white.withValues(alpha: 0.07),
                                ),
                              ),
                              child: Row(
                                children: [
                                  PlayerAvatarWidget(
                                    radius: 20,
                                    playerId: pid,
                                    playerName: name,
                                    preset: const AvatarPreset(
                                        colorIndex: -1, iconIndex: -1),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    name,
                                    style: TextStyle(
                                      color: isMe
                                          ? Colors.white
                                          : Colors.white
                                              .withValues(alpha: 0.7),
                                      fontWeight: isMe
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (isBot)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.06),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'BOT',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white
                                              .withValues(alpha: 0.3),
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                  if (isMe)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color:
                                            _accent.withValues(alpha: 0.2),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'YOU',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          color:
                                              _accent.withValues(alpha: 0.9),
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ).animate().fadeIn(
                                delay: Duration(milliseconds: i * 80));
                          },
                        ),
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // ── Start button (host only) ───────────────────────────
              if (_isHost)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _starting ? null : _startGame,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        disabledBackgroundColor:
                            _accent.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _starting
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            )
                          : const Text(
                              'START GAME',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                letterSpacing: 2,
                              ),
                            ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Text(
                    'Waiting for host to start…',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
