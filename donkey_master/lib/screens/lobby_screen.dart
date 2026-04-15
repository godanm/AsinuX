import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_state.dart';
import '../models/player_model.dart';
import '../services/firebase_service.dart';
import '../services/bot_service.dart';
import '../widgets/ad_banner_widget.dart';
import 'game_screen.dart';

class LobbyScreen extends StatefulWidget {
  final String roomId;
  final String playerId;

  const LobbyScreen({super.key, required this.roomId, required this.playerId});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late Stream<GameState?> _stateStream;

  @override
  void initState() {
    super.initState();
    _stateStream = FirebaseService.instance.roomStream(widget.roomId);
  }


  Future<void> _startGame(GameState state) async {
    if (!state.canStart) return;
    BotService.instance.start(state.roomId);
    await FirebaseService.instance.startGame(state);
  }

  Future<void> _startWithBots(GameState state) async {
    final needed = 4 - state.players.length;
    if (needed > 0) {
      await BotService.instance.addBots(state, needed);
    }
    // Fetch fresh state after bots added
    final snap = await Future.delayed(
      const Duration(milliseconds: 500),
      () => FirebaseService.instance.roomStream(state.roomId).first,
    );
    if (snap != null) {
      BotService.instance.start(snap.roomId);
      await FirebaseService.instance.startGame(snap);
    }
  }

  Future<void> _leaveRoom() async {
    BotService.instance.stop();
    await FirebaseService.instance.leaveRoom(
      widget.roomId,
      widget.playerId,
    );
    if (mounted) Navigator.pop(context);
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Room code copied!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GameState?>(
      stream: _stateStream,
      builder: (context, snap) {
        if (!snap.hasData || snap.data == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF0a0a1a),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final state = snap.data!;

        // Navigate to game when phase changes
        if (state.phase == GamePhase.playing) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => GameScreen(
                  roomId: widget.roomId,
                  playerId: widget.playerId,
                ),
              ),
            );
          });
        }

        final isHost = state.hostId == widget.playerId;
        final players = state.allPlayers;
        final canStart = state.canStart;

        return Scaffold(
          backgroundColor: const Color(0xFF0a0a1a),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: _leaveRoom,
            ),
            title: const Text(
              'Lobby',
              style: TextStyle(color: Colors.white),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Room code
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'ROOM CODE',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11,
                                  letterSpacing: 3,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    state.roomCode,
                                    style: const TextStyle(
                                      color: Color(0xFFFFD700),
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 8,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.copy,
                                        color: Colors.white54),
                                    onPressed: () =>
                                        _copyCode(state.roomCode),
                                  ),
                                ],
                              ),
                              Text(
                                'Share this code with friends',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Player count
                        Text(
                          '${players.length}/8 Players',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!canStart && players.length < 2)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Need at least 2 players to start',
                              style: TextStyle(
                                color: Colors.orange.shade400,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),

                        // Player list
                        Expanded(
                          child: ListView.separated(
                            itemCount: players.length,
                            separatorBuilder: (context, i) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final p = players[i];
                              return _PlayerTile(
                                player: p,
                                isCurrentUser: p.id == widget.playerId,
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Start buttons (host only)
                        if (isHost) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: () => _startWithBots(state),
                              icon: const Icon(Icons.smart_toy, color: Colors.black87),
                              label: const Text(
                                'START WITH BOTS',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFD700),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: canStart
                                  ? () => _startGame(state)
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white12,
                                disabledBackgroundColor: Colors.grey.shade800,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                canStart
                                    ? 'START WITH FRIENDS'
                                    : 'WAITING FOR PLAYERS...',
                                style: TextStyle(
                                  color: canStart
                                      ? Colors.white
                                      : Colors.white38,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                          ),
                        ]
                        else
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Waiting for host to start...',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const AdBannerWidget(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlayerTile extends StatelessWidget {
  final Player player;
  final bool isCurrentUser;

  const _PlayerTile({required this.player, required this.isCurrentUser});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? Colors.blue.shade900.withValues(alpha: 0.5)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentUser ? Colors.blue.shade700 : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isCurrentUser
                ? Colors.blue.shade700
                : Colors.grey.shade700,
            child: Text(
              player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      player.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (player.isHost) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'HOST',
                          style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    if (isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(you)',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle,
            color: Colors.green.shade400,
            size: 18,
          ),
        ],
      ),
    );
  }
}
