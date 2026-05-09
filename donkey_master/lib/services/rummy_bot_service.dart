import 'dart:math' show min;
import '../models/rummy_models.dart';

/// Helpers for Rummy bot players.
/// Bots are virtual — they exist only in Firebase, driven by the host's client.
class RummyBotService {
  RummyBotService._();

  static const _names = [
    'Priya', 'Arjun', 'Meera', 'Karthik',
    'Divya', 'Rajan', 'Ananya', 'Vikram',
  ];

  // ── Identity ─────────────────────────────────────────────────

  static String botId(int index) => 'bot_$index';
  static String botName(int index) => _names[index % _names.length];
  static bool isBot(String playerId) => playerId.startsWith('bot_');

  // ── Draw decision ─────────────────────────────────────────────

  /// Returns true if the bot should draw from the open deck.
  ///
  /// Takes the open card when it:
  /// - Is a joker (always valuable)
  /// - Has genuine connections to the hand AND we'd actually keep it
  ///   (prevents the cycle where bot picks up X then immediately discards X)
  static bool shouldDrawFromOpen(
    RummyCard? topOfOpen,
    List<RummyCard> hand,
    RummyCard wildJoker,
  ) {
    if (topOfOpen == null) return false;

    final wildRank = wildJoker.rank;

    // Always grab a joker
    if (topOfOpen.isPrintedJoker || topOfOpen.rank == wildRank) return true;

    // Check for any connection to current hand
    bool hasConnection = false;
    for (final card in hand) {
      if (isRummyJoker(card, wildRank)) continue;
      if (card.rank == topOfOpen.rank && card.suit != topOfOpen.suit) {
        hasConnection = true;
        break;
      }
      if (card.suit == topOfOpen.suit) {
        final diff = (card.rank - topOfOpen.rank).abs();
        if (diff == 1 || diff == 2) {
          hasConnection = true;
          break;
        }
      }
    }

    if (!hasConnection) return false;

    // Simulate: only draw if we'd actually keep it, not discard it immediately.
    // This prevents the bot from cycling the same card back and forth.
    final simulated = [...hand, topOfOpen];
    final discardIdx = chooseDiscard(simulated, wildJoker);
    return simulated[discardIdx] != topOfOpen;
  }

  // ── Discard decision ──────────────────────────────────────────

  /// Returns the index of the card to discard.
  ///
  /// Strategy (in priority order):
  /// 1. Never discard jokers (printed or wild-rank).
  /// 2. Score each non-joker by its connections to other cards:
  ///    - Adjacent same-suit card (rank ±1): +3 per card   (sequence neighbor)
  ///    - Gap same-suit card (rank ±2): +1 per card         (joker-bridgeable)
  ///    - Same-rank different-suit card: +2 per card        (set partner)
  /// 3. Discard the lowest-scored card; break ties by highest point value.
  static int chooseDiscard(List<RummyCard> hand, RummyCard wildJoker) {
    final wildRank = wildJoker.rank;

    final candidates = hand
        .asMap()
        .entries
        .where((e) => !isRummyJoker(e.value, wildRank))
        .toList();

    if (candidates.isEmpty) return hand.length - 1;

    // Compute keep-score for each candidate
    int scoreFor(MapEntry<int, RummyCard> entry) {
      final card = entry.value;
      int score = 0;
      for (final other in candidates) {
        if (other.key == entry.key) continue;
        final o = other.value;

        // Set connection
        if (o.rank == card.rank && o.suit != card.suit) {
          score += 2;
        }

        // Sequence connection (same suit)
        if (o.suit == card.suit) {
          final diff = (o.rank - card.rank).abs();
          if (diff == 1) { score += 3; }
          else if (diff == 2) { score += 1; }
        }
      }
      return score;
    }

    MapEntry<int, RummyCard>? worst;
    int worstScore = 999;
    int worstPoints = -1;

    for (final entry in candidates) {
      final s = scoreFor(entry);
      final p = entry.value.points;
      // Lower score = more isolated; among ties, higher points = better discard
      if (s < worstScore || (s == worstScore && p > worstPoints)) {
        worstScore = s;
        worstPoints = p;
        worst = entry;
      }
    }

    return worst?.key ?? hand.length - 1;
  }

  // ── Declaration ───────────────────────────────────────────────

  /// Returns true if the 14-card [hand] contains a declarable 13-card arrangement.
  static bool shouldDeclare(List<RummyCard> hand, RummyCard wildJoker) =>
      buildDeclaration(hand, wildJoker) != null;

  /// Returns `{'melds': List<List<RummyCard>>, 'discardIdx': int}` if a valid
  /// winning declaration exists in the 14-card hand, null otherwise.
  static Map<String, dynamic>? buildDeclaration(
      List<RummyCard> hand, RummyCard wildJoker) {
    for (int di = 0; di < hand.length; di++) {
      final remaining = List<RummyCard>.from(hand)..removeAt(di);
      final melds = _tryPartition(remaining, wildJoker.rank);
      if (melds != null) return {'melds': melds, 'discardIdx': di};
    }
    return null;
  }

  /// Tries to partition [cards] (exactly 13) into valid melds satisfying:
  /// ≥1 pure sequence + ≥2 total sequences. Returns null if impossible.
  static List<List<RummyCard>>? _tryPartition(
      List<RummyCard> cards, int wildRank) {
    // Sort: regular cards by (suit, rank); jokers last so the anchor is always a regular card.
    final sorted = List<RummyCard>.from(cards)
      ..sort((a, b) {
        final aj = isRummyJoker(a, wildRank);
        final bj = isRummyJoker(b, wildRank);
        if (aj != bj) return aj ? 1 : -1;
        if (a.suit != b.suit) return a.suit.compareTo(b.suit);
        return a.rank.compareTo(b.rank);
      });
    return _backtrack(sorted, [], wildRank);
  }

  static List<List<RummyCard>>? _backtrack(
      List<RummyCard> rem, List<List<RummyCard>> built, int wildRank) {
    if (rem.isEmpty) {
      final pureSeqs = built.where((m) => isPureSequence(m, wildRank)).length;
      final seqs = built.where((m) => isValidSequence(m, wildRank)).length;
      return (pureSeqs >= 1 && seqs >= 2) ? built : null;
    }

    // Always anchor on the first non-joker — it must belong to some meld.
    final anchorIdx = rem.indexWhere((c) => !isRummyJoker(c, wildRank));
    if (anchorIdx == -1) return null; // only jokers left, no valid meld possible

    final anchor = rem[anchorIdx];
    final others = List<RummyCard>.from(rem)..removeAt(anchorIdx);

    for (int size = 3; size <= min(4, rem.length); size++) {
      for (final combo in _combos(others, size - 1)) {
        final meld = [anchor, ...combo];
        if (!isValidMeld(meld, wildRank)) continue;
        final newRem = List<RummyCard>.from(rem);
        for (final c in meld) { newRem.remove(c); }
        final result = _backtrack(newRem, [...built, meld], wildRank);
        if (result != null) return result;
      }
    }
    return null;
  }

  static Iterable<List<RummyCard>> _combos(List<RummyCard> pool, int r) sync* {
    if (r == 0) {
      yield [];
      return;
    }
    if (pool.length < r) { return; }
    for (int i = 0; i <= pool.length - r; i++) {
      for (final rest in _combos(pool.sublist(i + 1), r - 1)) {
        yield [pool[i], ...rest];
      }
    }
  }
}
