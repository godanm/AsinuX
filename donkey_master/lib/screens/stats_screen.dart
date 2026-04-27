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
      body: Column(
        children: [
          // ── Compact player header ──────────────────────────────
          StreamBuilder<PlayerStats>(
            stream: StatsService.instance.statsStream(uid),
            builder: (context, snap) {
              final stats = snap.data ?? const PlayerStats();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    LocalPlayerAvatar(radius: 24, playerId: uid, playerName: playerName),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(playerName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          Text('${stats.totalPoints} pts',
                              style: TextStyle(
                                  color: const Color(0xFFFFD700).withValues(alpha: 0.85),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms);
            },
          ),

          const Divider(color: Colors.white10, height: 1),

          // ── 2×2 stats grid ────────────────────────────────────
          Expanded(
            child: Row(
              children: [
                // Left column
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _KazhuthaBlock(uid: uid)),
                      const _GridDividerH(),
                      Expanded(child: _Game28Block(uid: uid)),
                    ],
                  ),
                ),
                const _GridDividerV(),
                // Right column
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _RummyBlock(uid: uid)),
                      const _GridDividerH(),
                      Expanded(child: _TeenPattiBlock(uid: uid)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Kazhutha block ────────────────────────────────────────────────────────────

class _KazhuthaBlock extends StatelessWidget {
  final String uid;
  const _KazhuthaBlock({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerStats>(
      stream: StatsService.instance.statsStream(uid),
      builder: (context, snap) {
        final s = snap.data ?? const PlayerStats();
        return _GameBlock(
          emoji: '🃏',
          title: 'KAZHUTHA',
          accentColor: const Color(0xFFE63946),
          hasData: s.roundsPlayed > 0,
          children: [
            _MiniStat('Rounds', '${s.roundsPlayed}'),
            _MiniStat('Escaped', '${s.escapeCount}', color: Colors.greenAccent.shade400),
            _MiniStat('Donkey', '${s.donkeyCount}', color: Colors.redAccent),
            _MiniStat('1st place', '${s.firstPlaceCount}', color: const Color(0xFFFFD700)),
            _MiniStat(
              'Escape rate',
              '${(s.escapeRate * 100).toStringAsFixed(0)}%',
              color: Colors.greenAccent.shade400,
            ),
            _MiniStat(
              'Donkey rate',
              '${(s.donkeyRate * 100).toStringAsFixed(0)}%',
              color: Colors.redAccent,
            ),
            if (s.roundsPlayed > 0) ...[
              const SizedBox(height: 8),
              _MiniBar(
                segments: [
                  _Seg(s.escapeCount, Colors.green.shade600),
                  _Seg((s.roundsPlayed - s.escapeCount - s.donkeyCount).clamp(0, s.roundsPlayed), Colors.white24),
                  _Seg(s.donkeyCount, Colors.redAccent),
                ],
                labels: const ['Escaped', 'Played', 'Donkey'],
              ),
            ],
          ],
        );
      },
    );
  }
}

// ── Rummy block ───────────────────────────────────────────────────────────────

class _RummyBlock extends StatelessWidget {
  final String uid;
  const _RummyBlock({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RummyStats>(
      stream: StatsService.instance.rummyStatsStream(uid),
      builder: (context, snap) {
        final s = snap.data ?? const RummyStats();
        return _GameBlock(
          emoji: '🀄',
          title: 'RUMMY',
          accentColor: const Color(0xFF1565C0),
          hasData: s.gamesPlayed > 0,
          children: [
            _MiniStat('Games', '${s.gamesPlayed}'),
            _MiniStat('Wins', '${s.wins}', color: const Color(0xFF4FC3F7)),
            _MiniStat('Drops', '${s.drops}', color: Colors.redAccent),
            _MiniStat('Avg penalty', '${s.avgPenalty} pts', color: Colors.amber),
            _MiniStat(
              'Win rate',
              '${(s.winRate * 100).toStringAsFixed(0)}%',
              color: const Color(0xFF4FC3F7),
            ),
            _MiniStat(
              'Drop rate',
              '${(s.dropRate * 100).toStringAsFixed(0)}%',
              color: Colors.redAccent,
            ),
            if (s.gamesPlayed > 0) ...[
              const SizedBox(height: 8),
              _MiniBar(
                segments: [
                  _Seg(s.wins, const Color(0xFF1565C0)),
                  _Seg((s.gamesPlayed - s.wins - s.drops).clamp(0, s.gamesPlayed), Colors.white24),
                  _Seg(s.drops, Colors.redAccent),
                ],
                labels: const ['Won', 'Lost', 'Dropped'],
              ),
            ],
          ],
        );
      },
    );
  }
}

// ── Game 28 block ─────────────────────────────────────────────────────────────

class _Game28Block extends StatelessWidget {
  final String uid;
  const _Game28Block({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Game28Stats>(
      stream: StatsService.instance.game28StatsStream(uid),
      builder: (context, snap) {
        final s = snap.data ?? const Game28Stats();
        return _GameBlock(
          emoji: '🃏',
          title: 'GAME 28',
          accentColor: const Color(0xFF00c6ff),
          hasData: s.roundsPlayed > 0,
          children: [
            _MiniStat('Rounds', '${s.roundsPlayed}'),
            _MiniStat('Won', '${s.roundsWon}', color: Colors.greenAccent.shade400),
            _MiniStat('Bids won', '${s.bidsWon}', color: const Color(0xFFFFD700)),
            _MiniStat('Bid success', '${s.bidsMade}/${s.bidsWon}',
                color: Colors.amberAccent),
            _MiniStat(
              'Round win%',
              '${(s.roundWinRate * 100).toStringAsFixed(0)}%',
              color: Colors.greenAccent.shade400,
            ),
            _MiniStat(
              'Bid success%',
              '${(s.bidSuccessRate * 100).toStringAsFixed(0)}%',
              color: Colors.amberAccent,
            ),
            if (s.gamesPlayed > 0)
              _MiniStat('Games won', '${s.gamesWon}/${s.gamesPlayed}',
                  color: const Color(0xFF00c6ff)),
            if (s.roundsPlayed > 0) ...[
              const SizedBox(height: 8),
              _MiniBar(
                segments: [
                  _Seg(s.roundsWon, Colors.teal.shade600),
                  _Seg((s.roundsPlayed - s.roundsWon).clamp(0, s.roundsPlayed),
                      Colors.white24),
                ],
                labels: const ['Won', 'Lost'],
              ),
            ],
          ],
        );
      },
    );
  }
}

// ── Teen Patti block ──────────────────────────────────────────────────────────

class _TeenPattiBlock extends StatelessWidget {
  final String uid;
  const _TeenPattiBlock({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TeenPattiStats>(
      stream: StatsService.instance.teenPattiStatsStream(uid),
      builder: (context, snap) {
        final s = snap.data ?? const TeenPattiStats();
        return _GameBlock(
          emoji: '♟️',
          title: 'TEEN PATTI',
          accentColor: const Color(0xFF7B2FBE),
          hasData: s.roundsPlayed > 0,
          children: [
            _MiniStat('Rounds', '${s.roundsPlayed}'),
            _MiniStat('Won', '${s.roundsWon}', color: Colors.greenAccent.shade400),
            _MiniStat(
              'Win rate',
              '${(s.winRate * 100).toStringAsFixed(0)}%',
              color: Colors.greenAccent.shade400,
            ),
            _MiniStat('Chips won', '${s.totalChipsWon}', color: const Color(0xFFFFD700)),
            if (s.roundsPlayed > 0) ...[
              const SizedBox(height: 8),
              _MiniBar(
                segments: [
                  _Seg(s.roundsWon, const Color(0xFF7B2FBE)),
                  _Seg((s.roundsPlayed - s.roundsWon).clamp(0, s.roundsPlayed), Colors.white24),
                ],
                labels: const ['Won', 'Lost'],
              ),
            ],
          ],
        );
      },
    );
  }
}

// ── Reusable game block ───────────────────────────────────────────────────────

class _GameBlock extends StatelessWidget {
  final String emoji;
  final String title;
  final Color accentColor;
  final bool hasData;
  final List<Widget> children;

  const _GameBlock({
    required this.emoji,
    required this.title,
    required this.accentColor,
    required this.hasData,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Block header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: accentColor.withValues(alpha: 0.25)),
              ),
            ),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),

          // Scrollable stats content
          Expanded(
            child: hasData
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  )
                : Center(
                    child: Text(
                      'No games yet',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.2),
                        fontSize: 12,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Mini stat row ─────────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat(this.label, this.value, {this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mini breakdown bar ────────────────────────────────────────────────────────

class _Seg {
  final int count;
  final Color color;
  const _Seg(this.count, this.color);
}

class _MiniBar extends StatelessWidget {
  final List<_Seg> segments;
  final List<String> labels;
  const _MiniBar({required this.segments, required this.labels});

  @override
  Widget build(BuildContext context) {
    final total = segments.fold(0, (s, e) => s + e.count);
    if (total == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: segments
                  .where((s) => s.count > 0)
                  .map((s) => Expanded(
                        flex: s.count,
                        child: Container(color: s.color),
                      ))
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          children: List.generate(
            segments.length,
            (i) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: segments[i].color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  labels[i],
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Grid dividers ─────────────────────────────────────────────────────────────

class _GridDividerV extends StatelessWidget {
  const _GridDividerV();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: Colors.white10);
}

class _GridDividerH extends StatelessWidget {
  const _GridDividerH();
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: Colors.white10);
}
