import 'package:firebase_database/firebase_database.dart';

const _startingPoints = 10000;

// Points delta by finish position (0-indexed: 0=first, 1=second, 2=third, 3=donkey)
// Positive = gain, negative = loss
const _positionPoints = [100, 60, 30, -50];

int pointsForPosition(int zeroIndexedPosition) {
  if (zeroIndexedPosition < 0) return 0;
  if (zeroIndexedPosition >= _positionPoints.length) return 0;
  return _positionPoints[zeroIndexedPosition];
}

/// Stats stored per UID under `stats/{uid}` in Firebase.
class PlayerStats {
  final int gamesPlayed;
  final int roundsPlayed;
  final int donkeyCount;
  final int escapeCount;
  final int firstPlaceCount;
  final int wins;
  final int totalPoints;

  const PlayerStats({
    this.gamesPlayed = 0,
    this.roundsPlayed = 0,
    this.donkeyCount = 0,
    this.escapeCount = 0,
    this.firstPlaceCount = 0,
    this.wins = 0,
    this.totalPoints = 0,
  });

  double get escapeRate =>
      roundsPlayed == 0 ? 0 : escapeCount / roundsPlayed;

  double get donkeyRate =>
      roundsPlayed == 0 ? 0 : donkeyCount / roundsPlayed;

  double get winRate =>
      gamesPlayed == 0 ? 0 : wins / gamesPlayed;

  factory PlayerStats.fromMap(Map<dynamic, dynamic> map) => PlayerStats(
        gamesPlayed: (map['gamesPlayed'] as int?) ?? 0,
        roundsPlayed: (map['roundsPlayed'] as int?) ?? 0,
        donkeyCount: (map['donkeyCount'] as int?) ?? 0,
        escapeCount: (map['escapeCount'] as int?) ?? 0,
        firstPlaceCount: (map['firstPlaceCount'] as int?) ?? 0,
        wins: (map['wins'] as int?) ?? 0,
        totalPoints: (map['totalPoints'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'gamesPlayed': gamesPlayed,
        'roundsPlayed': roundsPlayed,
        'donkeyCount': donkeyCount,
        'escapeCount': escapeCount,
        'firstPlaceCount': firstPlaceCount,
        'wins': wins,
        'totalPoints': totalPoints,
      };
}

class LeaderboardEntry {
  final String uid;
  final String name;
  final int totalPoints;
  final int wins;
  final int gamesPlayed;

  const LeaderboardEntry({
    required this.uid,
    required this.name,
    required this.totalPoints,
    required this.wins,
    required this.gamesPlayed,
  });
}

class StatsService {
  static final StatsService _instance = StatsService._();
  static StatsService get instance => _instance;
  StatsService._();

  final _db = FirebaseDatabase.instance;

  DatabaseReference _ref(String uid) => _db.ref('stats/$uid');

  Future<PlayerStats> getStats(String uid) async {
    final snap = await _ref(uid).get();
    if (!snap.exists) return const PlayerStats();
    return PlayerStats.fromMap(snap.value as Map<dynamic, dynamic>);
  }

  Stream<PlayerStats> statsStream(String uid) {
    return _ref(uid).onValue.map((event) {
      if (!event.snapshot.exists) return const PlayerStats();
      return PlayerStats.fromMap(
          event.snapshot.value as Map<dynamic, dynamic>);
    });
  }

  /// Returns top [limit] players ordered by totalPoints descending.
  Future<List<LeaderboardEntry>> topPlayers({int limit = 10}) async {
    final snap = await _db
        .ref('stats')
        .orderByChild('totalPoints')
        .limitToLast(limit)
        .get();
    if (!snap.exists) return [];

    final map = snap.value as Map<dynamic, dynamic>;
    final entries = map.entries.map((e) {
      final uid = e.key as String;
      final data = e.value as Map<dynamic, dynamic>;
      final name = (data['displayName'] as String?) ?? uid.substring(0, 6);
      final points = (data['totalPoints'] as int?) ?? 0;
      final wins = (data['wins'] as int?) ?? 0;
      final gamesPlayed = (data['gamesPlayed'] as int?) ?? 0;
      return LeaderboardEntry(uid: uid, name: name, totalPoints: points, wins: wins, gamesPlayed: gamesPlayed);
    }).toList();

    entries.sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
    return entries;
  }

  /// Called when a round ends.
  /// [finishOrder] = players who escaped, in order (1st, 2nd, 3rd...).
  /// [donkeyId]   = player who lost the round (eliminated).
  /// [winnerId]   = tournament winner (null if game still ongoing).
  Future<void> recordRound({
    required List<String> allPlayerIds,
    required List<String> escapedIds,
    required String donkeyId,
    required String? winnerId,
    required bool isBot,
    Map<String, String> playerNames = const {},
  }) async {
    // Build a unified list: real player IDs as-is, bot IDs mapped to stable npc_ keys.
    // e.g. bot_1234_0 named "Arjun" → stats written under "npc_arjun"
    final entries = allPlayerIds.map((id) {
      if (id.startsWith('bot_')) {
        final name = playerNames[id];
        if (name == null) return null; // skip unnamed bots
        return (statsId: 'npc_${name.toLowerCase()}', originalId: id, displayName: name);
      }
      return (statsId: id, originalId: id, displayName: playerNames[id]);
    }).whereType<({String statsId, String originalId, String? displayName})>();

    for (final entry in entries) {
      final statsId = entry.statsId;
      final originalId = entry.originalId;
      final escapeIndex = escapedIds.indexOf(originalId);
      final isDonkey = originalId == donkeyId;
      final isWinner = originalId == winnerId;
      final escaped = escapeIndex >= 0;
      final isFirst = escapeIndex == 0;

      // Position: escaped players get 0,1,2... donkey gets last position
      final position = isDonkey ? allPlayerIds.length - 1 : escapeIndex;
      final delta = pointsForPosition(position);

      // First-time players start at 10K; existing players get incremented.
      final snap = await _ref(statsId).child('totalPoints').get();
      final currentPoints = snap.exists ? (snap.value as int? ?? 0) : _startingPoints;
      final newPoints = (currentPoints + delta).clamp(0, 999999);

      await _ref(statsId).update({
        'roundsPlayed': ServerValue.increment(1),
        'totalPoints': newPoints,
        if (entry.displayName != null) 'displayName': entry.displayName!,
        if (escaped) 'escapeCount': ServerValue.increment(1),
        if (isFirst) 'firstPlaceCount': ServerValue.increment(1),
        if (isDonkey) 'donkeyCount': ServerValue.increment(1),
        if (isWinner) 'wins': ServerValue.increment(1),
        if (isWinner || isDonkey) 'gamesPlayed': ServerValue.increment(1),
      });
    }
  }
}
