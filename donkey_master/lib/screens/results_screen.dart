import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/game_state.dart';
import '../services/firebase_service.dart';
import '../services/bot_service.dart';
import '../services/stats_service.dart';
import '../services/admob_service.dart';
import '../widgets/ad_banner_widget.dart';
import 'home_screen.dart';

class ResultsScreen extends StatefulWidget {
  final GameState state;
  final String playerId;

  const ResultsScreen({
    super.key,
    required this.state,
    required this.playerId,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  @override
  void initState() {
    super.initState();
    // Show interstitial as soon as the results screen is visible.
    // Using postFrameCallback ensures the screen is rendered before the ad
    // overlays it (avoids timing issues on Android; shows dialog on web).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AdMobService.instance.showRoundEndAd(context);
    });
    // Leave room when viewing results
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) _leaveAndGoHome();
    });
  }

  Future<void> _leaveAndGoHome() async {
    BotService.instance.stop();
    await FirebaseService.instance.leaveRoom(
      widget.state.roomId,
      widget.playerId,
    );
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final winner = widget.state.tournamentWinnerId != null
        ? widget.state.players[widget.state.tournamentWinnerId]
        : null;
    final iWon = widget.state.tournamentWinnerId == widget.playerId;

    final finishOrder = widget.state.finishOrder;
    final sortedPlayers = widget.state.allPlayers
      ..sort((a, b) => b.score.compareTo(a.score));

    return Scaffold(
      backgroundColor: const Color(0xFF0d0007),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 24),

                    // Trophy
                    Text(
                      iWon ? '🏆' : '🫏',
                      style: const TextStyle(fontSize: 72),
                    )
                        .animate()
                        .scale(duration: 500.ms, curve: Curves.elasticOut),

                    const SizedBox(height: 16),

                    Text(
                      iWon ? 'YOU WIN!' : 'GAME OVER',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        color: iWon
                            ? const Color(0xFFE63946)
                            : Colors.redAccent,
                      ),
                    ).animate().fadeIn(delay: 300.ms),

                    if (winner != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        iWon
                            ? 'Congratulations!'
                            : '${winner.name} wins this round!',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 16,
                        ),
                      ),
                    ],

                    const SizedBox(height: 40),

                    // Leaderboard
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'FINAL STANDINGS',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                                letterSpacing: 3,
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white12, height: 1),
                          ...sortedPlayers.asMap().entries.map((entry) {
                            final i = entry.key;
                            final p = entry.value;
                            final isWinner = p.id == widget.state.tournamentWinnerId;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                border: i < sortedPlayers.length - 1
                                    ? const Border(
                                        bottom: BorderSide(
                                          color: Colors.white12,
                                        ),
                                      )
                                    : null,
                                color: isWinner
                                    ? const Color(0xFFE63946).withValues(alpha: 0.12)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 32,
                                    child: Text(
                                      isWinner
                                          ? '🏆'
                                          : '${i + 1}.',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.5),
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      p.name,
                                      style: TextStyle(
                                        color: isWinner
                                            ? const Color(0xFFE63946)
                                            : Colors.white,
                                        fontWeight: isWinner
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  // Status badge
                                  if (p.isEliminated)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text('OUT', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                  const SizedBox(width: 8),
                                  // Points delta this round
                                  Builder(builder: (_) {
                                    final pos = p.isEliminated
                                        ? sortedPlayers.length - 1
                                        : finishOrder.indexOf(p.id);
                                    final pts = pointsForPosition(pos < 0 ? sortedPlayers.length - 1 : pos);
                                    final isLoss = pts < 0;
                                    final label = pts > 0 ? '+$pts pts' : pts < 0 ? '$pts pts' : '0 pts';
                                    final bg = pts > 0
                                        ? const Color(0xFFE63946).withValues(alpha: 0.15)
                                        : isLoss
                                            ? Colors.red.shade900.withValues(alpha: 0.4)
                                            : Colors.white.withValues(alpha: 0.07);
                                    final fg = pts > 0
                                        ? const Color(0xFFE63946)
                                        : isLoss
                                            ? Colors.red.shade300
                                            : Colors.white38;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: bg,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        label,
                                        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _leaveAndGoHome,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE63946),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'PLAY AGAIN',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Text(
                      'Returning to home in 10s...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 12,
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
  }
}
