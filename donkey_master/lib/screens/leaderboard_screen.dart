import 'package:flutter/material.dart';
import '../services/stats_service.dart';

class LeaderboardScreen extends StatefulWidget {
  final String currentUid;

  const LeaderboardScreen({super.key, required this.currentUid});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardEntry>? _entries;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final entries = await StatsService.instance.topPlayers(limit: 10);
      if (mounted) setState(() { _entries = entries; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d0007),
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
              setState(() { _loading = true; _entries = null; });
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
                  : _buildList(),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 48),
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
          Icon(Icons.emoji_events_outlined, color: Colors.white12, size: 64),
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
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: entries.length,
      itemBuilder: (context, i) => _EntryTile(
        rank: i + 1,
        entry: entries[i],
        isMe: entries[i].uid == widget.currentUid,
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final int rank;
  final LeaderboardEntry entry;
  final bool isMe;

  const _EntryTile({required this.rank, required this.entry, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final (medalColor, medalIcon) = switch (rank) {
      1 => (const Color(0xFFFFD700), Icons.emoji_events_rounded),
      2 => (const Color(0xFFB0BEC5), Icons.emoji_events_rounded),
      3 => (const Color(0xFFCD7F32), Icons.emoji_events_rounded),
      _ => (Colors.white24, Icons.circle_outlined),
    };

    final avatarColor = _avatarColors[
        entry.uid.codeUnits.fold(0, (a, b) => a + b) % _avatarColors.length];
    final initial = entry.name.isNotEmpty ? entry.name[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe
            ? const Color(0xFFE63946).withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe
              ? const Color(0xFFE63946).withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.06),
          width: isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 36,
            child: rank <= 3
                ? Icon(medalIcon, color: medalColor, size: 26)
                : Text(
                    '#$rank',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: avatarColor.withValues(alpha: 0.25),
            child: Text(
              initial,
              style: TextStyle(
                color: avatarColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.name,
                      style: TextStyle(
                        color: isMe ? const Color(0xFFFF6B6B) : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE63946).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'YOU',
                          style: TextStyle(
                            color: Color(0xFFE63946),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.wins} wins · ${entry.gamesPlayed} games',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Points
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.totalPoints}',
                style: TextStyle(
                  color: rank == 1
                      ? const Color(0xFFFFD700)
                      : isMe
                          ? const Color(0xFFFF6B6B)
                          : Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              Text(
                'pts',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _avatarColors = [
  Color(0xFFE63946),
  Color(0xFF2196F3),
  Color(0xFF4CAF50),
  Color(0xFFFF9800),
  Color(0xFF9C27B0),
  Color(0xFF00BCD4),
  Color(0xFFFF5722),
  Color(0xFF607D8B),
  Color(0xFFE91E63),
  Color(0xFF8BC34A),
  Color(0xFF795548),
  Color(0xFF3F51B5),
];
