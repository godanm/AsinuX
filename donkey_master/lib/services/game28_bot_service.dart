import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/card_model.dart';
import '../models/game28_state.dart';
import 'game28_service.dart';
import 'game28_bot_logic.dart';

class Game28BotService {
  static final Game28BotService _instance = Game28BotService._();
  static Game28BotService get instance => _instance;
  Game28BotService._();

  StreamSubscription<Game28State?>? _sub;
  final List<Timer> _timers = [];
  final _rng = Random();
  String? _roomId;
  int? _localTrumpSuit; // bid-winner bot's trump before it is revealed in state

  bool get isRunning => _roomId != null;
  int? get localTrumpSuit => _localTrumpSuit;

  // Called by the game screen when the human bid winner selects trump,
  // so bots can ask for trump when void in the lead suit.
  void setLocalTrump(int suit) => _localTrumpSuit = suit;

  void start(String roomId) {
    stop();
    _roomId = roomId;
    _sub = Game28Service.instance.roomStream(roomId).listen(_onState);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    for (final t in _timers) {
      t.cancel();
    }
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

    final delay = 1000 + _rng.nextInt(2000);
    _schedule(delay, () async {
      final fresh = await Game28Service.instance.getFreshState(state.roomId);
      if (fresh == null || fresh.biddingTurn != biddingTurn) return;

      final strength =
          botHandStrength(fresh.players[biddingTurn]?.hand ?? player.hand);
      final maxBid = botMaxBidForStrength(strength);

      // Partner 20 rule: must bid ≥ 20 to outbid own partner
      final holder = fresh.currentBidder;
      final holderTeam = fresh.players[holder ?? '']?.teamIndex;
      final partnerHoldsBid = holder != null &&
          holder != biddingTurn &&
          holderTeam == player.teamIndex;
      final minBid = (partnerHoldsBid && fresh.currentBid < 20)
          ? 20
          : fresh.currentBid + 1;

      // First bidder must open — never pass before anyone has bid
      final isFirstBidder = fresh.currentBidder == null;

      if (maxBid >= minBid) {
        // Occasionally pass even when able — simulates conservative play (~15%)
        if (!isFirstBidder && _rng.nextDouble() < 0.15 && fresh.currentBid >= 14) {
          await Game28Service.instance.placeBid(fresh, biddingTurn);
          debugPrint('[28Bot] $biddingTurn folds (bluff pass, strength=$strength)');
          return;
        }
        // Vary bid amount: strong hands jump 1-3 above minimum; weak hands hug minimum
        final room = (maxBid - minBid).clamp(0, 4);
        final extra = room == 0 ? 0 : _rng.nextInt(room + 1);
        final actualExtra = (_rng.nextDouble() < 0.4) ? extra : (extra > 0 ? 1 : 0);
        final bidValue = (minBid + actualExtra).clamp(minBid, 28);
        await Game28Service.instance.placeBid(fresh, biddingTurn, bidValue: bidValue);
        debugPrint('[28Bot] $biddingTurn bids $bidValue (strength=$strength, range=$minBid-$maxBid)');
      } else if (!isFirstBidder) {
        await Game28Service.instance.placeBid(fresh, biddingTurn);
        debugPrint('[28Bot] $biddingTurn passes (strength=$strength, maxBid=$maxBid, minBid=$minBid)');
      } else {
        // First bidder with weak hand: bid minimum 14
        await Game28Service.instance.placeBid(fresh, biddingTurn, bidValue: 14);
        debugPrint('[28Bot] $biddingTurn opens at 14 (first bidder, strength=$strength)');
      }
    });
  }

  // ── Trump selection ───────────────────────────────────────────────────────

  void _handleTrumpSelection(Game28State state) {
    final winnerId = state.bidWinnerId;
    if (winnerId == null) return;
    final winner = state.players[winnerId];
    if (winner == null || !winner.isBot) return;
    if (state.trumpSuit != null) return;

    final delay = 1000 + _rng.nextInt(2000);
    _schedule(delay, () async {
      final fresh = await Game28Service.instance.getFreshState(state.roomId);
      if (fresh == null || fresh.bidWinnerId != winnerId) return;
      if (fresh.trumpSuit != null) return;

      final bestSuit = botChooseTrump(winner.hand);
      _localTrumpSuit = bestSuit;
      await Game28Service.instance.selectTrump(fresh, winnerId, bestSuit);
      debugPrint('[28Bot] $winnerId selects trump ${Suit.values[bestSuit]}');
    });
  }

  // ── Card play ─────────────────────────────────────────────────────────────

  void _handleCardPlay(Game28State state) {
    final turn = state.currentTurn;
    if (turn == null) return;
    final player = state.players[turn];
    if (player == null || !player.isBot) return;

    final delay = 1000 + _rng.nextInt(2000);
    _schedule(delay, () async {
      final fresh = await Game28Service.instance.getFreshState(state.roomId);
      if (fresh == null || fresh.currentTurn != turn) return;
      if (fresh.phase != Game28Phase.playing) return;

      final hand = fresh.players[turn]!.hand;
      if (hand.isEmpty) return;

      // Bid-winner bot knows trump from _localTrumpSuit before state reveals it
      final effectiveTrump = fresh.trumpSuit ??
          (turn == fresh.bidWinnerId ? _localTrumpSuit : null);

      // Non-bid-winner void in lead → reveal trump only if the trick is worth it
      if (!fresh.trumpRevealed &&
          fresh.leadSuit != null &&
          turn != fresh.bidWinnerId &&
          _localTrumpSuit != null) {
        final isVoidInLead = !hand.any((c) => c.suit.index == fresh.leadSuit);
        if (isVoidInLead && botShouldAskTrump(fresh)) {
          await Game28Service.instance.askForTrump(fresh, turn,
              knownSuitIndex: _localTrumpSuit);
          final afterReveal =
              await Game28Service.instance.getFreshState(state.roomId);
          if (afterReveal == null || afterReveal.currentTurn != turn) return;
          if (afterReveal.phase != Game28Phase.playing) return;
          final updatedHand = afterReveal.players[turn]!.hand;
          final cardIdx2 = botChooseCard(
            afterReveal, turn, updatedHand, afterReveal.trumpSuit,
            shouldPlayTrumpWhenVoid: true,
          );
          await Game28Service.instance.playCard(afterReveal, turn, cardIdx2);
          return;
        }
      }

      final shouldPlayTrump =
          fresh.trumpRevealed || _rng.nextDouble() < 0.6;
      final cardIdx =
          botChooseCard(fresh, turn, hand, effectiveTrump,
              shouldPlayTrumpWhenVoid: shouldPlayTrump);
      final chosenCard = hand[cardIdx];

      // Bid winner cannot lead trump unless all cards in hand are trump.
      if (!fresh.trumpRevealed &&
          turn == fresh.bidWinnerId &&
          effectiveTrump != null &&
          fresh.leadSuit == null &&
          chosenCard.suit.index == effectiveTrump &&
          hand.any((c) => c.suit.index != effectiveTrump)) {
        // Re-pick: choose the lowest non-trump card to lead safely
        final nonTrump =
            hand.where((c) => c.suit.index != effectiveTrump).toList();
        final altCard = nonTrump.reduce((a, b) =>
            rankStrength28(a.rank) < rankStrength28(b.rank) ? a : b);
        await Game28Service.instance.playCard(
            fresh, turn, hand.indexOf(altCard));
        return;
      }

      // Bid-winner bot: if playing trump while unrevealed (leading all-trump OR
      // following while void), reveal it first so playCard sees trumpRevealed=true.
      final isBidWinnerPlayingTrump = !fresh.trumpRevealed &&
          effectiveTrump != null &&
          chosenCard.suit.index == effectiveTrump &&
          (fresh.leadSuit == null ||
              !fresh.players[turn]!.hand
                  .any((c) => c.suit.index == fresh.leadSuit));
      if (isBidWinnerPlayingTrump) {
        await Game28Service.instance.askForTrump(fresh, turn,
            knownSuitIndex: effectiveTrump);
        final afterReveal =
            await Game28Service.instance.getFreshState(state.roomId);
        if (afterReveal == null || afterReveal.currentTurn != turn) return;
        if (afterReveal.phase != Game28Phase.playing) return;
        await Game28Service.instance.playCard(afterReveal, turn, cardIdx);
        return;
      }

      await Game28Service.instance.playCard(fresh, turn, cardIdx);
    });
  }

  // ── Trick end auto-advance ─────────────────────────────────────────────────

  void _handleTrickEnd(Game28State state) {
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
