import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/card_model.dart';
import '../models/game28_state.dart';
import 'game28_service.dart';

class Game28BotService {
  static final Game28BotService _instance = Game28BotService._();
  static Game28BotService get instance => _instance;
  Game28BotService._();

  StreamSubscription<Game28State?>? _sub;
  final List<Timer> _timers = [];
  final _rng = Random();
  String? _roomId;
  int? _localTrumpSuit; // bid-winner bot's trump before it is revealed in state

  void start(String roomId) {
    stop();
    _roomId = roomId;
    _sub = Game28Service.instance.roomStream(roomId).listen(_onState);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    for (final t in _timers) t.cancel();
    _timers.clear();
    _roomId = null;
    _localTrumpSuit = null;
  }

  void _onState(Game28State? state) {
    if (state == null || _roomId == null) return;

    switch (state.phase) {
      case Game28Phase.bidding:
        _handleBidding(state);
        break;
      case Game28Phase.trumpSelection:
        _handleTrumpSelection(state);
        break;
      case Game28Phase.playing:
        _handleCardPlay(state);
        break;
      case Game28Phase.trickEnd:
        _handleTrickEnd(state);
        break;
      default:
        break;
    }
  }

  // ── Bidding ───────────────────────────────────────────────────────────────

  void _handleBidding(Game28State state) {
    final biddingTurn = state.biddingTurn;
    if (biddingTurn == null) return;
    final player = state.players[biddingTurn];
    if (player == null || !player.isBot) return;

    final delay = 800 + _rng.nextInt(1200);
    _schedule(delay, () async {
      final fresh = await Game28Service.instance.getFreshState(state.roomId);
      if (fresh == null || fresh.biddingTurn != biddingTurn) return;

      final strength = _handStrength(fresh.players[biddingTurn]?.hand ?? player.hand);
      final maxBid = _maxBidForStrength(strength);

      // Partner 20 rule: must bid ≥ 20 to outbid own partner
      final holder = fresh.currentBidder;
      final holderTeam = fresh.players[holder ?? '']?.teamIndex;
      final partnerHoldsBid = holder != null &&
          holder != biddingTurn &&
          holderTeam == player.teamIndex;
      final minBid = (partnerHoldsBid && fresh.currentBid < 20)
          ? 20
          : fresh.currentBid + 1;

      if (maxBid >= minBid) {
        // Occasionally pass even when able — simulates conservative play (~15%)
        if (_rng.nextDouble() < 0.15 && fresh.currentBid >= 14) {
          await Game28Service.instance.placeBid(fresh, biddingTurn);
          debugPrint('[28Bot] $biddingTurn folds (bluff pass, strength=$strength)');
          return;
        }
        // Vary bid amount: strong hands jump 1-3 above minimum; weak hands hug minimum
        final room = (maxBid - minBid).clamp(0, 4);
        final extra = room == 0 ? 0 : _rng.nextInt(room + 1);
        // Bias: use full jump only ~40% of the time to avoid always jumping
        final actualExtra = (_rng.nextDouble() < 0.4) ? extra : (extra > 0 ? 1 : 0);
        final bidValue = (minBid + actualExtra).clamp(minBid, 28);
        await Game28Service.instance.placeBid(fresh, biddingTurn, bidValue: bidValue);
        debugPrint('[28Bot] $biddingTurn bids $bidValue (strength=$strength, range=$minBid-$maxBid)');
      } else {
        await Game28Service.instance.placeBid(fresh, biddingTurn);
        debugPrint('[28Bot] $biddingTurn passes (strength=$strength, maxBid=$maxBid, minBid=$minBid)');
      }
    });
  }

  /// Total card point value in hand (J=3, 9=2, A=1, 10=1)
  int _handStrength(List<PlayingCard> hand) =>
      hand.fold(0, (sum, c) => sum + cardPoints28(c.rank));

  int _maxBidForStrength(int strength) {
    if (strength >= 10) return 22;
    if (strength >= 8) return 20;
    if (strength >= 6) return 18;
    if (strength >= 4) return 16;
    if (strength >= 2) return 15;
    return 13; // will pass
  }

  // ── Trump selection ───────────────────────────────────────────────────────

  void _handleTrumpSelection(Game28State state) {
    final winnerId = state.bidWinnerId;
    if (winnerId == null) return;
    final winner = state.players[winnerId];
    if (winner == null || !winner.isBot) return;
    if (state.trumpSuit != null) return; // already chosen

    final delay = 600 + _rng.nextInt(800);
    _schedule(delay, () async {
      final fresh = await Game28Service.instance.getFreshState(state.roomId);
      if (fresh == null || fresh.bidWinnerId != winnerId) return;
      if (fresh.trumpSuit != null) return;

      final bestSuit = _chooseTrump(winner.hand);
      _localTrumpSuit = bestSuit;
      await Game28Service.instance.selectTrump(fresh, winnerId, bestSuit);
      debugPrint('[28Bot] $winnerId selects trump ${Suit.values[bestSuit]}');
    });
  }

  /// Pick the suit that maximises control: point cards + high cards count.
  int _chooseTrump(List<PlayingCard> hand) {
    final scores = <int, int>{};
    for (final card in hand) {
      final s = card.suit.index;
      final pts = cardPoints28(card.rank) * 2 + rankStrength28(card.rank);
      scores[s] = (scores[s] ?? 0) + pts;
    }
    return scores.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  // ── Card play ─────────────────────────────────────────────────────────────

  void _handleCardPlay(Game28State state) {
    final turn = state.currentTurn;
    if (turn == null) return;
    final player = state.players[turn];
    if (player == null || !player.isBot) return;

    final delay = 700 + _rng.nextInt(1300);
    _schedule(delay, () async {
      final fresh = await Game28Service.instance.getFreshState(state.roomId);
      if (fresh == null || fresh.currentTurn != turn) return;
      if (fresh.phase != Game28Phase.playing) return;

      final hand = fresh.players[turn]!.hand;
      if (hand.isEmpty) return;

      // Bid-winner bot knows trump from _localTrumpSuit before state reveals it
      final effectiveTrump = fresh.trumpSuit ??
          (turn == fresh.bidWinnerId ? _localTrumpSuit : null);

      final cardIdx = _chooseCard(fresh, turn, hand, effectiveTrump);
      final chosenCard = hand[cardIdx];

      // If playing a trump card while trump is unrevealed, explicitly reveal first
      if (!fresh.trumpRevealed &&
          effectiveTrump != null &&
          chosenCard.suit.index == effectiveTrump &&
          fresh.leadSuit != null) {
        await Game28Service.instance.askForTrump(fresh, turn);
      }

      await Game28Service.instance.playCard(fresh, turn, cardIdx);
    });
  }

  int _chooseCard(Game28State state, String playerId, List<PlayingCard> hand,
      int? effectiveTrump) {
    final leadSuit = state.leadSuit;
    final trumpSuit = effectiveTrump;
    final isLeader = state.currentTrick.isEmpty;

    // ── Leader: pick best lead ───────────────────────────────────────────
    if (isLeader) {
      return _pickLeadCard(hand, trumpSuit);
    }

    // ── Follower ─────────────────────────────────────────────────────────
    final mustFollowCards =
        hand.where((c) => c.suit.index == leadSuit).toList();

    if (mustFollowCards.isNotEmpty) {
      return _indexIn(hand, _pickFollowCard(mustFollowCards, state));
    }

    // No lead suit — can play trump or anything else
    if (trumpSuit != null) {
      final trumpCards =
          hand.where((c) => c.suit.index == trumpSuit).toList();
      if (trumpCards.isNotEmpty && _shouldPlayTrump(state, playerId)) {
        return _indexIn(hand, trumpCards
            .reduce((a, b) => rankStrength28(a.rank) > rankStrength28(b.rank) ? a : b));
      }
    }

    // Throw lowest non-point card, or lowest card overall
    return _indexIn(hand, _safestDiscard(hand, trumpSuit));
  }

  int _pickLeadCard(List<PlayingCard> hand, int? trumpSuit) {
    // Lead a non-trump, non-point card if possible
    final safe = hand.where((c) =>
        c.suit.index != trumpSuit && cardPoints28(c.rank) == 0).toList();
    if (safe.isNotEmpty) {
      // Lead highest safe card to exhaust opponents
      return _indexIn(hand,
          safe.reduce((a, b) => rankStrength28(a.rank) > rankStrength28(b.rank) ? a : b));
    }
    // Fall back: lowest card
    return _indexIn(hand,
        hand.reduce((a, b) => rankStrength28(a.rank) < rankStrength28(b.rank) ? a : b));
  }

  PlayingCard _pickFollowCard(
      List<PlayingCard> cards, Game28State state) {
    // Find current winning card of lead suit in trick
    final leadSuit = state.leadSuit!;
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
      // Partner winning — play lowest to conserve cards
      return cards.reduce(
          (a, b) => rankStrength28(a.rank) < rankStrength28(b.rank) ? a : b);
    }

    // Try to win with lowest card that beats current winner
    final canWin = cards
        .where((c) => rankStrength28(c.rank) > currentWinStrength)
        .toList();
    if (canWin.isNotEmpty) {
      return canWin.reduce(
          (a, b) => rankStrength28(a.rank) < rankStrength28(b.rank) ? a : b);
    }

    // Can't win — throw lowest card
    return cards.reduce(
        (a, b) => rankStrength28(a.rank) < rankStrength28(b.rank) ? a : b);
  }

  bool _shouldPlayTrump(Game28State state, String playerId) {
    if (state.trumpRevealed) return true; // trump known, use strategically
    // Only reveal trump ~60% of the time
    return _rng.nextDouble() < 0.6;
  }

  PlayingCard _safestDiscard(List<PlayingCard> hand, int? trumpSuit) {
    // Prefer discarding non-point, non-trump
    final safe = hand.where((c) =>
        c.suit.index != trumpSuit && cardPoints28(c.rank) == 0).toList();
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

  // ── Trick end auto-advance ─────────────────────────────────────────────────

  void _handleTrickEnd(Game28State state) {
    // Only the next leader (bot) kicks off the next trick
    final nextLeader = state.currentTurn;
    if (nextLeader == null) return;
    final player = state.players[nextLeader];
    if (player == null || !player.isBot) return;

    _schedule(1600, () async {
      final fresh = await Game28Service.instance.getFreshState(state.roomId);
      if (fresh == null || fresh.phase != Game28Phase.trickEnd) return;
      if (fresh.currentTurn != nextLeader) return;
      await Game28Service.instance.startNextTrick(fresh);
    });
  }

  void _schedule(int ms, Future<void> Function() fn) {
    final t = Timer(Duration(milliseconds: ms), fn);
    _timers.add(t);
  }
}
