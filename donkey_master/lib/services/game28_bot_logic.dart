import '../models/card_model.dart';
import '../models/game28_state.dart';

// ── Bidding ────────────────────────────────────────────────────────────────────

/// Raw point total plus +2 for each Jack-Nine pair of the same suit.
int botHandStrength(List<PlayingCard> hand) {
  int pts = hand.fold(0, (s, c) => s + cardPoints28(c.rank));
  for (final suit in Suit.values) {
    final hasJ = hand.any((c) => c.suit == suit && c.rank == Rank.jack);
    final has9 = hand.any((c) => c.suit == suit && c.rank == Rank.nine);
    if (hasJ && has9) pts += 2;
  }
  return pts;
}

/// Maximum bid the bot is willing to place given hand strength.
/// Calibrated so a J+9 same-suit hand (strength≈7) maps to 14–17.
int botMaxBidForStrength(int strength) {
  if (strength >= 11) return 22;
  if (strength >= 9) return 20;
  if (strength >= 7) return 17;
  if (strength >= 5) return 15;
  if (strength >= 3) return 14;
  return 13; // pass
}

// ── Trump selection ────────────────────────────────────────────────────────────

/// Choose trump suit: weight each suit by (pts×2 + strength) and add a
/// length bonus (+8 for 4 cards, +3 for 3 cards) so long suits compete
/// with Jack-bearing short suits.
int botChooseTrump(List<PlayingCard> hand) {
  final scores = <int, int>{};
  final counts = <int, int>{};
  for (final card in hand) {
    final s = card.suit.index;
    scores[s] = (scores[s] ?? 0) +
        cardPoints28(card.rank) * 2 +
        rankStrength28(card.rank);
    counts[s] = (counts[s] ?? 0) + 1;
  }
  for (final s in counts.keys) {
    final n = counts[s] ?? 0;
    if (n >= 4) {
      scores[s] = (scores[s] ?? 0) + 8;
    } else if (n == 3) {
      scores[s] = (scores[s] ?? 0) + 3;
    }
  }
  return scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

// ── Ask-for-trump timing ───────────────────────────────────────────────────────

/// Non-bid-winner should reveal trump when any scoring card (A/10=1pt,
/// 9=2pts, J=3pts) is already on the table and going to the opponent.
bool botShouldAskTrump(Game28State state) =>
    state.currentTrick.values.any((c) => cardPoints28(c.rank) >= 1);

// ── Card play ──────────────────────────────────────────────────────────────────

/// Full card-choice algorithm. Returns an **index into [hand]**.
///
/// [shouldPlayTrumpWhenVoid] lets the caller inject the random 60% decision
/// for unrevealed-trump play, keeping this function deterministic for tests.
int botChooseCard(
  Game28State state,
  String playerId,
  List<PlayingCard> hand,
  int? trumpSuit, {
  bool shouldPlayTrumpWhenVoid = true,
}) {
  if (hand.isEmpty) return 0;

  final leadSuit = state.leadSuit;
  final isLeader = state.currentTrick.isEmpty;

  // ── A. Leader ────────────────────────────────────────────────────────────
  if (isLeader) {
    return _indexIn(hand, _pickLeadCard(hand, trumpSuit));
  }

  // ── B. Forced trump after reveal ─────────────────────────────────────────
  if (state.trumpRevealRequired && trumpSuit != null) {
    final hasSuit = hand.any((c) => c.suit.index == leadSuit);
    if (!hasSuit) {
      final trumpCards = hand.where((c) => c.suit.index == trumpSuit).toList();
      if (trumpCards.isNotEmpty) {
        return _indexIn(
          hand,
          trumpCards.reduce((a, b) =>
              rankStrength28(a.rank) > rankStrength28(b.rank) ? a : b),
        );
      }
    }
  }

  // ── C. Must follow lead suit ──────────────────────────────────────────────
  final mustFollowCards =
      hand.where((c) => c.suit.index == leadSuit).toList();
  if (mustFollowCards.isNotEmpty) {
    return _indexIn(hand, _pickFollowCard(mustFollowCards, state, trumpSuit));
  }

  // ── D. Void in lead suit ──────────────────────────────────────────────────
  if (shouldPlayTrumpWhenVoid && trumpSuit != null) {
    final trumpCards = hand.where((c) => c.suit.index == trumpSuit).toList();
    if (trumpCards.isNotEmpty) {
      return _indexIn(
        hand,
        trumpCards.reduce((a, b) =>
            rankStrength28(a.rank) > rankStrength28(b.rank) ? a : b),
      );
    }
  }

  // Discard: partner high-value win → throw points; else safest discard
  return _indexIn(hand, _discardCard(hand, state, playerId, trumpSuit));
}

// ── Internal helpers ───────────────────────────────────────────────────────────

PlayingCard _pickLeadCard(List<PlayingCard> hand, int? trumpSuit) {
  // If holding a non-trump J or 9, lead SMALL to draw out opponents' Aces/Tens
  final hasHighPower = hand.any(
      (c) => c.suit.index != trumpSuit && cardPoints28(c.rank) >= 2);

  final nonTrumpNonPoint = hand
      .where((c) => c.suit.index != trumpSuit && cardPoints28(c.rank) == 0)
      .toList();

  if (hasHighPower && nonTrumpNonPoint.isNotEmpty) {
    // Lead smallest non-trump non-point card
    return nonTrumpNonPoint.reduce((a, b) =>
        rankStrength28(a.rank) < rankStrength28(b.rank) ? a : b);
  }

  if (nonTrumpNonPoint.isNotEmpty) {
    // No J/9 held — lead highest to exhaust opponents
    return nonTrumpNonPoint.reduce((a, b) =>
        rankStrength28(a.rank) > rankStrength28(b.rank) ? a : b);
  }

  // Fallback: lowest card overall
  return hand.reduce(
      (a, b) => rankStrength28(a.rank) < rankStrength28(b.rank) ? a : b);
}

PlayingCard _pickFollowCard(
    List<PlayingCard> cards, Game28State state, int? trumpSuit) {
  final leadSuit = state.leadSuit!;

  // Find current trick leader (highest-strength lead-suit card played so far)
  int currentWinStrength = -1;
  String? currentWinnerId;
  for (final e in state.currentTrick.entries) {
    if (e.value.suit.index == leadSuit) {
      final s = rankStrength28(e.value.rank);
      if (s > currentWinStrength) {
        currentWinStrength = s;
        currentWinnerId = e.key;
      }
    }
  }

  final myTeam = state.players.values
      .firstWhere((p) => p.id == state.currentTurn,
          orElse: () => state.players.values.first)
      .teamIndex;
  final partnerIsWinning = currentWinnerId != null &&
      state.players[currentWinnerId]?.teamIndex == myTeam;

  if (partnerIsWinning) {
    final partnerCard = state.currentTrick[currentWinnerId];
    if (partnerCard != null && cardPoints28(partnerCard.rank) >= 2) {
      // Partner has J or 9 — throw our highest point card that won't take the trick
      final safeThrow = cards
          .where((c) =>
              cardPoints28(c.rank) > 0 &&
              rankStrength28(c.rank) < rankStrength28(partnerCard.rank))
          .toList();
      if (safeThrow.isNotEmpty) {
        return safeThrow.reduce((a, b) =>
            cardPoints28(a.rank) >= cardPoints28(b.rank) ? a : b);
      }
    }
    // Partner winning with low card — conserve
    return cards.reduce(
        (a, b) => rankStrength28(a.rank) < rankStrength28(b.rank) ? a : b);
  }

  // Opponent winning — try to beat with lowest winning card
  final canWin = cards
      .where((c) => rankStrength28(c.rank) > currentWinStrength)
      .toList();
  if (canWin.isNotEmpty) {
    return canWin.reduce(
        (a, b) => rankStrength28(a.rank) < rankStrength28(b.rank) ? a : b);
  }

  // Can't win — throw lowest
  return cards.reduce(
      (a, b) => rankStrength28(a.rank) < rankStrength28(b.rank) ? a : b);
}

/// When void in lead and not playing trump, decide what to discard.
/// Throws a high-point non-trump card onto a partner's high-value winning trick;
/// otherwise discards as safely as possible.
PlayingCard _discardCard(
    List<PlayingCard> hand, Game28State state, String playerId, int? trumpSuit) {
  final leadSuit = state.leadSuit;
  if (leadSuit != null) {
    String? winningId;
    int bestStrength = -1;
    for (final e in state.currentTrick.entries) {
      if (e.value.suit.index == leadSuit) {
        final s = rankStrength28(e.value.rank);
        if (s > bestStrength) {
          bestStrength = s;
          winningId = e.key;
        }
      }
    }
    if (winningId != null) {
      final myTeam = state.players[playerId]?.teamIndex;
      final winnerTeam = state.players[winningId]?.teamIndex;
      final partnerWinning = myTeam != null && winnerTeam == myTeam;
      final winnerCard = state.currentTrick[winningId];
      final highValueTrick =
          winnerCard != null && cardPoints28(winnerCard.rank) >= 2;

      if (partnerWinning && highValueTrick) {
        // Throw highest-point non-trump card
        final nonTrump =
            hand.where((c) => c.suit.index != trumpSuit).toList();
        if (nonTrump.isNotEmpty) {
          return nonTrump.reduce((a, b) {
            final aPts = cardPoints28(a.rank);
            final bPts = cardPoints28(b.rank);
            if (aPts != bPts) return aPts > bPts ? a : b;
            return rankStrength28(a.rank) > rankStrength28(b.rank) ? a : b;
          });
        }
      }
    }
  }
  return _safestDiscard(hand, trumpSuit);
}

PlayingCard _safestDiscard(List<PlayingCard> hand, int? trumpSuit) {
  final safe = hand
      .where((c) => c.suit.index != trumpSuit && cardPoints28(c.rank) == 0)
      .toList();
  if (safe.isNotEmpty) {
    return safe.reduce(
        (a, b) => rankStrength28(a.rank) < rankStrength28(b.rank) ? a : b);
  }
  return hand.reduce(
      (a, b) => rankStrength28(a.rank) < rankStrength28(b.rank) ? a : b);
}

int _indexIn(List<PlayingCard> hand, PlayingCard card) {
  final idx = hand.indexWhere((c) => c == card);
  return idx == -1 ? 0 : idx;
}
