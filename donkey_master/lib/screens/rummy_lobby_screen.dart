import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/rummy_service.dart';
import '../widgets/player_avatar.dart';
import 'rummy_game_screen.dart';

class RummyLobbyScreen extends StatefulWidget {
  final String roomId;
  final String playerId;
  final String playerName;
  final int maxPlayers;
  final int targetScore;

  const RummyLobbyScreen({
    super.key,
    required this.roomId,
    required this.playerId,
    required this.playerName,
    required this.maxPlayers,
    this.targetScore = 0,
  });

  @override
  State<RummyLobbyScreen> createState() => _RummyLobbyScreenState();
}

class _RummyLobbyScreenState extends State<RummyLobbyScreen> {
  StreamSubscription<Map<String, dynamic>?>? _sub;
  Map<String, dynamic> _room = {};
  bool _leaving = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _sub = RummyService.instance
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
      // Room deleted — go back
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    if (mounted) setState(() => _room = room);

    // Navigate all players to game screen when host starts
    if (room['status'] == 'started' && mounted) {
      _sub?.cancel();
      final botIds = _players.keys
          .where((id) => id.startsWith('bot_'))
          .toList();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RummyGameScreen(
            roomId: widget.roomId,
            playerId: widget.playerId,
            playerName: widget.playerName,
            botIds: botIds,
            targetScore: widget.targetScore,
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
  bool get _isFull => _players.length >= widget.maxPlayers;

  Future<void> _leave() async {
    setState(() => _leaving = true);
    await RummyService.instance.leaveRoom(widget.roomId, widget.playerId);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final playerList = _players.values
        .map((p) => Map<String, dynamic>.from(p as Map))
        .toList()
      ..sort((a, b) {
          final aTs = (a['joinedAt'] as num?)?.toInt() ?? 0;
          final bTs = (b['joinedAt'] as num?)?.toInt() ?? 0;
          return aTs.compareTo(bTs);
        });

    final waiting = widget.maxPlayers - playerList.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _leave(),
      child: Scaffold(
        backgroundColor: const Color(0xFF04061a),
        body: SafeArea(
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white70),
                      onPressed: _leaving ? null : _leave,
                    ),
                    const Spacer(),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFF4FC3F7), Color(0xFF1565C0), Color(0xFFE3F2FD)],
                      ).createShader(bounds),
                      child: const Text(
                        'RUMMY',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),

                      // ── Room info ────────────────────────────────
                      Text(
                        '${widget.maxPlayers}-PLAYER TABLE',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ).animate().fadeIn(duration: 300.ms),

                      const SizedBox(height: 6),

                      // Player count pill
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          key: ValueKey(playerList.length),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: _isFull
                                ? const Color(0xFF1565C0).withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _isFull
                                  ? const Color(0xFF4FC3F7).withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Text(
                            _isFull
                                ? 'Table full — ready to start!'
                                : 'Waiting for $waiting more player${waiting == 1 ? '' : 's'}…',
                            style: TextStyle(
                              color: _isFull
                                  ? const Color(0xFF4FC3F7)
                                  : Colors.white.withValues(alpha: 0.45),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── Seat chips ───────────────────────────────
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: List.generate(widget.maxPlayers, (i) {
                          if (i < playerList.length) {
                            final p = playerList[i];
                            final isMe = p['id'] == widget.playerId;
                            final isHost = _room['hostId'] == p['id'];
                            return _SeatChip(
                              name: (p['name'] as String).replaceAll('_', ' '),
                              isMe: isMe,
                              isHost: isHost,
                              playerId: p['id'] as String,
                            ).animate().fadeIn(
                                  delay: Duration(milliseconds: i * 60),
                                  duration: 250.ms,
                                );
                          } else {
                            return _EmptySeatChip(seat: i + 1)
                                .animate()
                                .fadeIn(
                                  delay: Duration(milliseconds: i * 60),
                                  duration: 250.ms,
                                );
                          }
                        }),
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // ── Start button (pinned bottom) ──────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: _isHost
                    ? SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isFull && !_starting ? _startGame : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            disabledBackgroundColor:
                                Colors.white.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(
                            _starting ? 'STARTING…' : _isFull ? 'START GAME' : 'WAITING FOR PLAYERS…',
                            style: TextStyle(
                              color: _isFull
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.3),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      )
                    : Text(
                        'Waiting for host to start…',
                        textAlign: TextAlign.center,
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

  Future<void> _startGame() async {
    setState(() => _starting = true);
    try {
      await RummyService.instance.startGame(roomId: widget.roomId, targetScore: widget.targetScore);
      // Navigation is handled by _onRoomUpdate when status → 'started'
    } catch (e, st) {
      debugPrint('[Rummy] startGame error: $e\n$st');
      if (mounted) {
        setState(() => _starting = false);
        final trace = st.toString().split('\n').take(4).join('\n');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText('$e\n$trace',
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 60),
          ),
        );
      }
    }
  }
}

// ── Seat chip (compact) ───────────────────────────────────────────────────────

class _SeatChip extends StatelessWidget {
  final String name;
  final bool isMe;
  final bool isHost;
  final String playerId;

  const _SeatChip({
    required this.name,
    required this.isMe,
    required this.isHost,
    required this.playerId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        color: isMe
            ? const Color(0xFF1565C0).withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: isMe
              ? const Color(0xFF4FC3F7).withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              LocalPlayerAvatar(radius: 14, playerId: playerId, playerName: name),
              if (isHost)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF04061a), width: 1),
                    ),
                    child: const Icon(Icons.star_rounded, size: 7, color: Colors.black),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Text(
            isMe ? 'You' : name,
            style: TextStyle(
              color: isMe ? const Color(0xFF4FC3F7) : Colors.white,
              fontSize: 12,
              fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          if (isHost) ...[
            const SizedBox(width: 4),
            const Text('HOST',
                style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
          ],
        ],
      ),
    );
  }
}

// ── Empty seat chip ───────────────────────────────────────────────────────────

class _EmptySeatChip extends StatelessWidget {
  final int seat;
  const _EmptySeatChip({required this.seat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        color: Colors.white.withValues(alpha: 0.02),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline,
              color: Colors.white.withValues(alpha: 0.15), size: 16),
          const SizedBox(width: 6),
          Text(
            'Seat $seat',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.15),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
