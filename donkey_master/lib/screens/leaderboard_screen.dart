import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/stats_service.dart';
import '../widgets/player_avatar.dart';

class LeaderboardScreen extends StatefulWidget {
  final String currentUid;
  final String currentPlayerName;

  const LeaderboardScreen({
    super.key,
    required this.currentUid,
    required this.currentPlayerName,
  });

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardEntry>? _entries;
  LeaderboardEntry? _myEntry; // non-null when current user is outside top 50
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; _myEntry = null; });
    try {
      final entries = await StatsService.instance.topPlayers(limit: 50);
      LeaderboardEntry? myEntry;
      if (widget.currentUid.isNotEmpty &&
          !entries.any((e) => e.uid == widget.currentUid)) {
        final myStats = await StatsService.instance.getStats(widget.currentUid);
        myEntry = LeaderboardEntry(
          uid: widget.currentUid,
          name: widget.currentPlayerName.isNotEmpty ? widget.currentPlayerName : widget.currentUid.substring(0, 6),
          totalPoints: myStats.totalPoints,
          wins: myStats.wins,
          gamesPlayed: myStats.gamesPlayed,
        );
      }
      if (mounted) setState(() { _entries = entries; _myEntry = myEntry; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0008),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'LEADERBOARD',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
            onPressed: () {
              setState(() { _loading = true; _entries = null; _myEntry = null; });
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE63946)))
          : _error != null
              ? _buildError(_error!)
              : _entries == null || _entries!.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: const Color(0xFFE63946),
                      backgroundColor: const Color(0xFF1a000e),
                      child: _buildList(),
                    ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 48),
            const SizedBox(height: 16),
            Text(
              'Could not load leaderboard',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: _load,
              child: const Text('RETRY', style: TextStyle(color: Color(0xFFE63946), letterSpacing: 1.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events_outlined, color: Colors.white12, size: 64),
          const SizedBox(height: 16),
          Text(
            'No players yet',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final entries = _entries!;
    final top3 = entries.take(3).toList();
    final rest = entries.skip(3).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // ── Your rank (outside top 50) — shown at top so it's always visible ──
        if (_myEntry != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'YOUR RANKING',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 10, letterSpacing: 1.5),
            ),
          ),
          _EntryTile(
            rank: entries.length + 1,
            entry: _myEntry!,
            isMe: true,
            rankLabel: '#${entries.length}+',
          ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.03, end: 0),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
        ],

        // ── Podium (top 3) ─────────────────────────────────────
        _Podium(top3: top3, currentUid: widget.currentUid)
            .animate()
            .fadeIn(duration: 400.ms)
            .slideY(begin: -0.05, end: 0),

        const Divider(color: Colors.white10, height: 1),
        const SizedBox(height: 12),

        // ── Rank 4+ ────────────────────────────────────────────
        ...rest.asMap().entries.map((e) => _EntryTile(
              rank: e.key + 4,
              entry: e.value,
              isMe: e.value.uid == widget.currentUid,
            ).animate(delay: Duration(milliseconds: e.key * 30)).fadeIn(duration: 250.ms).slideX(begin: 0.03, end: 0)),
      ],
    );
  }
}

// ── Podium widget ─────────────────────────────────────────────────────────────

class _Podium extends StatelessWidget {
  final List<LeaderboardEntry> top3;
  final String currentUid;

  const _Podium({required this.top3, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    // Display order: 2nd (left), 1st (center), 3rd (right)
    final slots = [
      if (top3.length > 1) (entry: top3[1], rank: 2, podiumH: 70.0, avatarR: 26.0),
      if (top3.isNotEmpty) (entry: top3[0], rank: 1, podiumH: 100.0, avatarR: 34.0),
      if (top3.length > 2) (entry: top3[2], rank: 3, podiumH: 52.0, avatarR: 22.0),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: slots.map((s) => _PodiumSlot(
          entry: s.entry,
          rank: s.rank,
          podiumHeight: s.podiumH,
          avatarRadius: s.avatarR,
          isMe: s.entry.uid == currentUid,
        )).toList(),
      ),
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  final LeaderboardEntry entry;
  final int rank;
  final double podiumHeight;
  final double avatarRadius;
  final bool isMe;

  const _PodiumSlot({
    required this.entry,
    required this.rank,
    required this.podiumHeight,
    required this.avatarRadius,
    required this.isMe,
  });

  Color get _rankColor => switch (rank) {
        1 => const Color(0xFFFFD700),
        2 => const Color(0xFFC0C0C0),
        _ => const Color(0xFFCD7F32),
      };

  String get _medal => switch (rank) {
        1 => '🥇',
        2 => '🥈',
        _ => '🥉',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_medal, style: TextStyle(fontSize: rank == 1 ? 26 : 20)),
          const SizedBox(height: 6),
          Stack(
            clipBehavior: Clip.none,
            children: [
              PlayerAvatarWidget(
                radius: avatarRadius,
                playerId: entry.uid,
                playerName: entry.name,
              ),
              if (isMe)
                Positioned(
                  top: -4, right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE63946),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('YOU', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: rank == 1 ? 90 : 74,
            child: Text(
              entry.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isMe ? const Color(0xFFFF6B6B) : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: rank == 1 ? 13 : 11,
              ),
            ),
          ),
          Text(
            '${entry.totalPoints} pts',
            style: TextStyle(color: _rankColor, fontWeight: FontWeight.w700, fontSize: rank == 1 ? 13 : 11),
          ),
          const SizedBox(height: 6),
          Container(
            width: rank == 1 ? 90 : 74,
            height: podiumHeight,
            decoration: BoxDecoration(
              color: _rankColor.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              border: Border(top: BorderSide(color: _rankColor.withValues(alpha: 0.5), width: 2)),
            ),
            alignment: Alignment.center,
            child: Text(
              '#$rank',
              style: TextStyle(color: _rankColor.withValues(alpha: 0.6), fontWeight: FontWeight.w900, fontSize: rank == 1 ? 26 : 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Row tile (rank 4+) ────────────────────────────────────────────────────────

class _EntryTile extends StatelessWidget {
  final int rank;
  final LeaderboardEntry entry;
  final bool isMe;
  final String? rankLabel;

  const _EntryTile({required this.rank, required this.entry, required this.isMe, this.rankLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe
            ? const Color(0xFFE63946).withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe
              ? const Color(0xFFE63946).withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.06),
          width: isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              rankLabel ?? '#$rank',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          PlayerAvatarWidget(radius: 20, playerId: entry.uid, playerName: entry.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isMe ? const Color(0xFFFF6B6B) : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE63946).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('YOU', style: TextStyle(color: Color(0xFFE63946), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.wins} wins · ${entry.gamesPlayed} games',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.totalPoints}',
                style: TextStyle(
                  color: isMe ? const Color(0xFFFF6B6B) : Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              Text('pts', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}
