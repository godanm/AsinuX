import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/stats_service.dart';
import '../widgets/player_avatar.dart';

class StatsScreen extends StatelessWidget {
  final String uid;
  final String playerName;

  const StatsScreen({super.key, required this.uid, required this.playerName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d0007),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Your Stats', style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<PlayerStats>(
        stream: StatsService.instance.statsStream(uid),
        builder: (context, snap) {
          final stats = snap.data ?? const PlayerStats();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Center(
                  child: Column(
                    children: [
                      LocalPlayerAvatar(
                        radius: 40,
                        playerId: uid,
                        playerName: playerName,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        playerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${stats.gamesPlayed} games played',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms),

                const SizedBox(height: 32),

                // Big 3 stats
                Row(
                  children: [
                    _BigStat(
                      label: 'Win Rate',
                      value: '${(stats.winRate * 100).toStringAsFixed(0)}%',
                      icon: '🏆',
                      color: const Color(0xFFE63946),
                    ),
                    const SizedBox(width: 12),
                    _BigStat(
                      label: 'Escape Rate',
                      value: '${(stats.escapeRate * 100).toStringAsFixed(0)}%',
                      icon: '🎉',
                      color: Colors.green.shade400,
                    ),
                    const SizedBox(width: 12),
                    _BigStat(
                      label: 'Donkey Rate',
                      value: '${(stats.donkeyRate * 100).toStringAsFixed(0)}%',
                      icon: '🫏',
                      color: Colors.redAccent,
                    ),
                  ],
                ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

                const SizedBox(height: 24),

                // Detailed breakdown
                _SectionTitle('Lifetime Totals'),
                const SizedBox(height: 12),
                _StatRow(label: 'Total Points', value: '${stats.totalPoints}', icon: Icons.stars_rounded, color: const Color(0xFFE63946)),
                _StatRow(label: 'Rounds played', value: '${stats.roundsPlayed}', icon: Icons.casino_outlined),
                _StatRow(label: 'Times escaped', value: '${stats.escapeCount}', icon: Icons.exit_to_app, color: Colors.green.shade400),
                _StatRow(label: 'Times the Donkey', value: '${stats.donkeyCount}', icon: Icons.mood_bad, color: Colors.redAccent),
                _StatRow(label: 'Times finished 1st', value: '${stats.firstPlaceCount}', icon: Icons.emoji_events, color: const Color(0xFFFFD700)),

                const SizedBox(height: 32),

                // Performance bar
                if (stats.roundsPlayed > 0) ...[
                  _SectionTitle('Round Breakdown'),
                  const SizedBox(height: 16),
                  _BreakdownBar(stats: stats),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  final String label;
  final String value;
  final String icon;
  final Color color;

  const _BigStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatRow({
    required this.label,
    required this.value,
    required this.icon,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownBar extends StatelessWidget {
  final PlayerStats stats;
  const _BreakdownBar({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = stats.roundsPlayed;
    final escaped = stats.escapeCount;
    final donkey = stats.donkeyCount;
    final neutral = total - escaped - donkey;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 20,
            child: Row(
              children: [
                if (escaped > 0)
                  Expanded(
                    flex: escaped,
                    child: Container(color: Colors.green.shade600),
                  ),
                if (neutral > 0)
                  Expanded(
                    flex: neutral.clamp(0, total),
                    child: Container(color: Colors.white24),
                  ),
                if (donkey > 0)
                  Expanded(
                    flex: donkey,
                    child: Container(color: Colors.redAccent),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Legend(color: Colors.green.shade600, label: 'Escaped'),
            const SizedBox(width: 16),
            _Legend(color: Colors.white24, label: 'Played'),
            const SizedBox(width: 16),
            _Legend(color: Colors.redAccent, label: 'Donkey'),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.4),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      ),
    );
  }
}
