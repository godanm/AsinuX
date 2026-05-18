import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;

const List<int> kStreakRewards = [100, 150, 200, 300, 500, 750, 1000];

class StreakStatus {
  final int currentDay;   // 1–7, which day is next to claim
  final bool canClaim;    // true if today's bonus not yet claimed
  final int reward;       // points for claiming today

  const StreakStatus({
    required this.currentDay,
    required this.canClaim,
    required this.reward,
  });
}

class StreakService {
  StreakService._();
  static final instance = StreakService._();

  final _db = FirebaseDatabase.instance;

  DatabaseReference _ref(String uid) => _db.ref('stats/$uid');

  String _todayKey() {
    final now = DateTime.now().toUtc();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _yesterdayKey() {
    final yesterday = DateTime.now().toUtc().subtract(const Duration(days: 1));
    return '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
  }

  Future<StreakStatus> checkStreak(String uid) async {
    if (uid.isEmpty) return const StreakStatus(currentDay: 1, canClaim: false, reward: 0);
    final snap = await _ref(uid).child('streak').get();
    final today = _todayKey();
    final yesterday = _yesterdayKey();

    if (!snap.exists) {
      return StreakStatus(currentDay: 1, canClaim: true, reward: kStreakRewards[0]);
    }

    final data = Map<String, dynamic>.from(snap.value as Map);
    final lastClaim = (data['lastClaim'] as String?) ?? '';
    final savedDay = (data['day'] as int?) ?? 1;

    if (lastClaim == today) {
      // Already claimed today — show current state but no claim available
      return StreakStatus(currentDay: savedDay, canClaim: false, reward: 0);
    }

    if (lastClaim == yesterday) {
      // Consecutive day — advance streak
      final nextDay = savedDay >= 7 ? 1 : savedDay + 1;
      return StreakStatus(
        currentDay: nextDay,
        canClaim: true,
        reward: kStreakRewards[nextDay - 1],
      );
    }

    // Missed a day or more — reset to Day 1
    return StreakStatus(currentDay: 1, canClaim: true, reward: kStreakRewards[0]);
  }

  Future<void> claimStreak(String uid, int day, int reward) async {
    if (uid.isEmpty) return;
    await _ref(uid).child('streak').update({
      'day': day,
      'lastClaim': _todayKey(),
    });
    debugPrint('[StreakService] $uid claimed Day $day streak (+$reward pts)');
  }
}
