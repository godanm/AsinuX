import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/card_model.dart';
import '../models/game28_state.dart';
import 'game_logger.dart';

class Game28Service {
  static final Game28Service _instance = Game28Service._();
  static Game28Service get instance => _instance;
  Game28Service._();

  final _db = FirebaseDatabase.instance;
  DatabaseReference _ref(String roomId) => _db.ref('game28_rooms/$roomId');
  DatabaseReference _secretsRef(String roomId) =>
      _db.ref('game28_secrets/$roomId');

  /// Bid winner subscribes to this to know their trump before it is revealed.
  Stream<int?> trumpSecretStream(String roomId) =>
      _secretsRef(roomId).child('trumpSuit').onValue.map(
            (e) => (e.snapshot.value as num?)?.toInt(),
          );

  // ── Room lifecycle ────────────────────────────────────────────────────────

  Future<Game28State> createRoom({
    required String playerId,
    required String playerName,
  }) async {
    final code = _generateCode();
    final roomId = _db.ref('game28_rooms').push().key!;
    final host = Game28Player(
      id: playerId,
      name: playerName,
      isHost: true,
      seatIndex: 0,
    );
    final state = Game28State(
      roomId: roomId,
      roomCode: code,
      players: {playerId: host},
      playerOrder: [playerId],
      hostId: playerId,
    );
    await _ref(roomId).set(state.toMap());
    await _db.ref('game28_codes/$code').set(roomId);
    return state;
  }

  Future<void> addBots(Game28State state, int count,
      {List<String>? names}) async {
    final rng = Random();
    final existing = state.players.length;
    final updatedPlayers =
        Map<String, Game28Player>.from(state.players);
    final updatedOrder = List<String>.from(state.playerOrder);

    for (int i = 0; i < count; i++) {
      final seatIndex = existing + i;
      final botId = 'bot_${state.roomId}_$seatIndex';
      final name = (names != null && i < names.length)
          ? names[i]
          : _botNames[rng.nextInt(_botNames.length)];
      updatedPlayers[botId] = Game28Player(
        id: botId,
        name: name,
        isBot: true,
        seatIndex: seatIndex,
      );
      updatedOrder.add(botId);
    }
    await _ref(state.roomId).update({
      'players': updatedPlayers.map((k, v) => MapEntry(k, v.toMap())),
      'playerOrder': updatedOrder,
    });
  }

  Future<void> leaveRoom(String roomId, String playerId) async {
    final snap = await _ref(roomId).get();
    if (!snap.exists) return;
    final state =
        Game28State.fromMap(snap.value as Map<dynamic, dynamic>);
    final remaining = state.playerOrder
        .where((id) => id != playerId && !id.startsWith('bot_'))
        .toList();
    if (remaining.isEmpty) {
      await _ref(roomId).remove();
      if (state.roomCode.isNotEmpty) {
        await _db.ref('game28_codes/${state.roomCode}').remove();
      }
    } else {
      await _ref(roomId).child('players/$playerId').remove();
      final newOrder =
          state.playerOrder.where((id) => id != playerId).toList();
      await _ref(roomId).child('playerOrder').set(newOrder);
    }
  }

  // ── Game start ────────────────────────────────────────────────────────────

  Future<void> startGame(Game28State state) async {
    final deck = buildDeck28()..shuffle(Random());
    final order = List<String>.from(state.playerOrder);
    // Phase 1: deal first 4 cards to each player (used for bidding)
    final updatedPlayers = Map<String, Game28Player>.from(state.players);
    for (int i = 0; i < order.length; i++) {
      final hand = deck.sublist(i * 4, i * 4 + 4);
      updatedPlayers[order[i]] =
          updatedPlayers[order[i]]!.copyWith(hand: hand);
    }
    // Remaining 16 cards stored until trump is chosen (phase 2 deal)
    final pendingDeck = deck.sublist(16);
    // Rotate first bidder each round so every player gets to open
    final firstBidder = order[(state.roundNumber) % order.length];
    await _secretsRef(state.roomId).remove();
    await _ref(state.roomId).update({
      'phase': Game28Phase.bidding.index,
      'roundNumber': state.roundNumber + 1,
      'trickNumber': 1,
      'currentBid': 13,
      'currentBidder': null,
      'biddingTurn': firstBidder,
      'passedPlayers': [],
      'trumpSuit': null,
      'trumpRevealed': false,
      'bidWinnerId': null,
      'bidWinnerTeam': null,
      'currentTrick': {},
      'leadSuit': null,
      'leadPlayer': null,
      'currentTurn': null,
      'pendingDeck': pendingDeck.map((c) => c.toMap()).toList(),
      'teamTrickPoints': {'t0': 0, 't1': 0},
      'players': updatedPlayers.map((k, v) => MapEntry(k, v.toMap())),
    });
    GameLogger.instance.game28RoundStart(
      roomId: state.roomId,
      roundNumber: state.roundNumber + 1,
      firstBidder: firstBidder,
      hands: updatedPlayers.map((k, v) => MapEntry(k, v.hand)),
    );
    debugPrint('[28] startGame — round ${state.roundNumber + 1}, dealt 4 bid cards each');
  }

  // ── Bidding ───────────────────────────────────────────────────────────────

  /// Pass bidValue=null to pass, or a value > currentBid to bid.
  Future<void> placeBid(Game28State state, String playerId,
      {int? bidValue}) async {
    if (state.biddingTurn != playerId) return;
    final order = state.playerOrder;
    final passed = List<String>.from(state.passedPlayers);

    if (bidValue == null) {
      // Pass — but last un-passed player must bid at minimum 14
      final active =
          order.where((id) => !passed.contains(id) && id != playerId).toList();
      if (active.isEmpty) {
        // This is the last player — force minimum bid instead of pass
        bidValue = 14;
      } else {
        passed.add(playerId);
      }
    }

    if (bidValue != null) {
      // Validate bid
      if (bidValue <= state.currentBid || bidValue < 14 || bidValue > 28) return;
      // Partner 20 rule: must bid ≥ 20 to outbid your own partner
      final holder = state.currentBidder;
      GameLogger.instance.game28BidPlaced(
        roomId: state.roomId,
        playerId: playerId,
        playerName: state.players[playerId]?.name ?? playerId,
        bidValue: bidValue,
        currentBid: state.currentBid,
      );
      if (holder != null && holder != playerId) {
        final holderTeam = state.players[holder]?.teamIndex;
        final myTeam = state.players[playerId]?.teamIndex;
        if (holderTeam != null && myTeam != null &&
            holderTeam == myTeam && bidValue < 20) return;
      }

      // Update current bid holder
      final newPassed = List<String>.from(passed); // keep existing passes
      final active = order
          .where((id) => !newPassed.contains(id) && id != playerId)
          .toList();

      if (active.isEmpty) {
        // This player is the only remaining bidder — they win
        await _ref(state.roomId).update({
          'currentBid': bidValue,
          'currentBidder': playerId,
          'passedPlayers': newPassed,
          'phase': Game28Phase.trumpSelection.index,
          'bidWinnerId': playerId,
          'bidWinnerTeam': state.players[playerId]!.teamIndex,
          'biddingTurn': null,
        });
        debugPrint('[28] bid won by $playerId at $bidValue');
        return;
      }

      // Find next bidder in order (skip passed players)
      final nextBidder = _nextActive(order, playerId, newPassed);
      await _ref(state.roomId).update({
        'currentBid': bidValue,
        'currentBidder': playerId,
        'passedPlayers': newPassed,
        'biddingTurn': nextBidder,
      });
    } else {
      // Passed — check if only one active bidder remains
      GameLogger.instance.game28BidPlaced(
        roomId: state.roomId,
        playerId: playerId,
        playerName: state.players[playerId]?.name ?? playerId,
        bidValue: null,
        currentBid: state.currentBid,
      );
      final active =
          order.where((id) => !passed.contains(id)).toList();

      if (active.length == 1) {
        // Last one wins (at current bid or minimum 14)
        final winnerId = active.first;
        final winBid = state.currentBid < 14 ? 14 : state.currentBid;
        await _ref(state.roomId).update({
          'passedPlayers': passed,
          'phase': Game28Phase.trumpSelection.index,
          'bidWinnerId': winnerId,
          'bidWinnerTeam': state.players[winnerId]!.teamIndex,
          'currentBid': winBid,
          'currentBidder': winnerId,
          'biddingTurn': null,
        });
        debugPrint('[28] bid won by $winnerId (others passed) at $winBid');
      } else {
        final nextBidder = _nextActive(order, playerId, passed);
        await _ref(state.roomId).update({
          'passedPlayers': passed,
          'biddingTurn': nextBidder,
        });
      }
    }
  }

  // ── Trump selection ───────────────────────────────────────────────────────

  Future<void> selectTrump(
      Game28State state, String playerId, int suitIndex) async {
    if (state.bidWinnerId != playerId) return;
    if (state.phase != Game28Phase.trumpSelection) return;

    // First trick leader = player after bidder in order
    final order = state.playerOrder;
    final bidIdx = order.indexOf(playerId);
    final firstLeader = order[(bidIdx + 1) % order.length];

    // Step 1: store trump in secrets path — hidden from opponents until revealed
    await _secretsRef(state.roomId).update({'trumpSuit': suitIndex});

    // Step 2: transition to playing phase (trumpSuit NOT written to main state yet)
    await _ref(state.roomId).update({
      'phase': Game28Phase.playing.index,
      'currentTurn': firstLeader,
      'leadPlayer': null,
      'currentTrick': {},
      'leadSuit': null,
    });

    // Step 2: deal remaining 4 cards to each player now that trump is set
    await _dealRemainingCards(state);
    GameLogger.instance.game28TrumpSelected(
      roomId: state.roomId,
      bidderId: playerId,
      bidderName: state.players[playerId]?.name ?? playerId,
      suitIndex: suitIndex,
      bidAmount: state.currentBid,
    );
    debugPrint('[28] trump = ${Suit.values[suitIndex]}, dealt second 4 cards — leads $firstLeader');
  }

  /// Distributes the stored pendingDeck (second 4 cards per player) and clears it.
  /// Guard: if pendingDeck is already empty, does nothing (prevents double-deal).
  Future<void> _dealRemainingCards(Game28State state) async {
    final pending = state.pendingDeck;
    if (pending.isEmpty) return;
    final order = state.playerOrder;
    final updatedPlayers = Map<String, Game28Player>.from(state.players);
    for (int i = 0; i < order.length; i++) {
      final secondHalf = pending.sublist(i * 4, i * 4 + 4);
      final fullHand = [...updatedPlayers[order[i]]!.hand, ...secondHalf];
      updatedPlayers[order[i]] =
          updatedPlayers[order[i]]!.copyWith(hand: fullHand);
    }
    await _ref(state.roomId).update({
      'pendingDeck': [],
      'players': updatedPlayers.map((k, v) => MapEntry(k, v.toMap())),
    });
  }

  // ── Ask for trump ─────────────────────────────────────────────────────────

  /// Called by a player to reveal the trump suit to all.
  /// Non-bid-winners must be void in the lead suit to call this.
  /// The bid winner may reveal at any time.
  /// Sets trumpRevealRequired so the engine enforces trump must be played next.
  /// [knownSuitIndex] lets callers bypass the Firebase secrets read (e.g. bots
  /// that already hold the suit in memory). Without it the read goes through
  /// security rules, which deny access when auth.uid ≠ bidWinnerId.
  Future<void> askForTrump(Game28State state, String playerId,
      {int? knownSuitIndex}) async {
    if (state.trumpRevealed) return;
    if (state.phase != Game28Phase.playing) return;

    // Use caller-supplied suit when available; fall back to secrets read.
    int? suitIndex = knownSuitIndex;
    if (suitIndex == null) {
      final snap =
          await _secretsRef(state.roomId).child('trumpSuit').get();
      suitIndex = (snap.value as num?)?.toInt();
    }
    if (suitIndex == null) return;

    final isBidWinner = playerId == state.bidWinnerId;
    if (!isBidWinner) {
      // Non-bid-winner must be void in the lead suit
      final leadSuit = state.leadSuit;
      if (leadSuit == null) return;
      final hand = state.players[playerId]?.hand ?? [];
      final hasSuit = hand.any((c) => c.suit.index == leadSuit);
      if (hasSuit) return;
    }

    // Write trumpSuit to main state for the first time alongside the reveal flags
    await _ref(state.roomId).update({
      'trumpSuit': suitIndex,
      'trumpRevealed': true,
      'trumpRevealRequired': true,
    });
    GameLogger.instance.game28TrumpRevealed(
      roomId: state.roomId,
      revealerId: playerId,
      revealer: state.players[playerId]?.name ?? playerId,
      trump: Suit.values[suitIndex].name,
      isBidWinner: isBidWinner,
    );
    debugPrint('[28] trump revealed by $playerId — ${Suit.values[suitIndex]}'
        '${isBidWinner ? ' (bid winner)' : ' (void in lead)'}');
  }

  // ── Card play ─────────────────────────────────────────────────────────────

  Future<void> playCard(
      Game28State state, String playerId, int cardIndex) async {
    if (state.currentTurn != playerId) return;
    final player = state.players[playerId]!;
    if (cardIndex >= player.hand.length) return;

    final card = player.hand[cardIndex];
    final newHand = List<PlayingCard>.from(player.hand)..removeAt(cardIndex);
    final newTrick =
        Map<String, PlayingCard>.from(state.currentTrick)..[playerId] = card;

    final isLeader = state.leadSuit == null && state.currentTrick.isEmpty;
    final leadSuit = isLeader ? card.suit.index : state.leadSuit!;

    // ── Server-side card legality ─────────────────────────────────────────
    if (!isLeader) {
      final hasSuit = player.hand.any((c) => c.suit.index == leadSuit);
      if (hasSuit && card.suit.index != leadSuit) return; // must follow lead
    }

    // ── Forced trump after reveal ─────────────────────────────────────────
    // Triggered only when this player called askForTrump this turn.
    // They must be void in the lead suit and must play trump if they hold it.
    if (state.trumpRevealRequired && !isLeader && state.trumpSuit != null) {
      final isVoid = !player.hand.any((c) => c.suit.index == leadSuit);
      if (isVoid) {
        final hasTrump =
            player.hand.any((c) => c.suit.index == state.trumpSuit);
        if (hasTrump && card.suit.index != state.trumpSuit) return;
      }
    }

    GameLogger.instance.game28CardPlayed(
      roomId: state.roomId,
      playerId: playerId,
      playerName: player.name,
      card: card,
      trickNumber: state.trickNumber,
      isLeader: isLeader,
      trumpRevealed: state.trumpRevealed,
    );

    // Update player hand
    final updatedPlayers =
        Map<String, Game28Player>.from(state.players);
    updatedPlayers[playerId] = player.copyWith(hand: newHand);

    // Determine next turn
    final order = state.playerOrder;
    final notYetPlayed =
        order.where((id) => !newTrick.containsKey(id)).toList();

    final orderAfterCurrent = [
      ...order.skipWhile((id) => id != playerId).skip(1),
      ...order.takeWhile((id) => id != playerId),
    ];
    final nextTurn = notYetPlayed.isEmpty
        ? null
        : orderAfterCurrent.firstWhere(
            (id) => notYetPlayed.contains(id),
            orElse: () => '',
          );

    await _ref(state.roomId).update({
      'players/${playerId}/hand': newHand.map((c) => c.toMap()).toList(),
      'currentTrick': newTrick.map((k, v) => MapEntry(k, v.toMap())),
      'leadSuit': leadSuit,
      'leadPlayer': isLeader ? playerId : state.leadPlayer,
      'currentTurn': nextTurn,
      'trumpRevealed': state.trumpRevealed,
      'trumpRevealRequired': false,
    });

    // All 4 played — resolve
    if (notYetPlayed.isEmpty) {
      await _resolveTrick(state, newTrick, leadSuit, updatedPlayers);
    }
  }

  Future<void> _resolveTrick(
    Game28State state,
    Map<String, PlayingCard> trick,
    int leadSuit,
    Map<String, Game28Player> updatedPlayers,
  ) async {
    final trumpSuit = state.trumpSuit;

    // Find winner
    String? winnerId;
    int winStrength = -1;

    final hasTrump = trumpSuit != null &&
        state.trumpRevealed &&
        trick.values.any((c) => c.suit.index == trumpSuit);

    if (hasTrump) {
      for (final entry in trick.entries) {
        if (entry.value.suit.index == trumpSuit) {
          final s = rankStrength28(entry.value.rank);
          if (s > winStrength) {
            winStrength = s;
            winnerId = entry.key;
          }
        }
      }
    } else {
      for (final entry in trick.entries) {
        if (entry.value.suit.index == leadSuit) {
          final s = rankStrength28(entry.value.rank);
          if (s > winStrength) {
            winStrength = s;
            winnerId = entry.key;
          }
        }
      }
    }

    winnerId ??= state.playerOrder.first;
    final winnerTeam = updatedPlayers[winnerId]!.teamIndex;

    // Sum card points in this trick
    final trickPts =
        trick.values.fold(0, (sum, c) => sum + cardPoints28(c.rank));

    final newTrickPoints = Map<String, int>.from(state.teamTrickPoints);
    newTrickPoints['t$winnerTeam'] =
        (newTrickPoints['t$winnerTeam'] ?? 0) + trickPts;

    GameLogger.instance.game28TrickWon(
      roomId: state.roomId,
      winnerId: winnerId,
      winnerName: updatedPlayers[winnerId]!.name,
      trickNumber: state.trickNumber,
      trickPoints: trickPts,
      teamTrickPoints: newTrickPoints,
    );
    debugPrint(
        '[28] trick ${state.trickNumber} won by $winnerId (team $winnerTeam, +$trickPts pts)');

    if (state.trickNumber >= 8) {
      // Round over
      await _resolveRound(state, newTrickPoints, trick);
    } else {
      await _ref(state.roomId).update({
        'phase': Game28Phase.trickEnd.index,
        'trickNumber': state.trickNumber + 1,
        'teamTrickPoints': newTrickPoints,
        'currentTurn': winnerId,
        'leadPlayer': null,
        'currentTrick': trick.map((k, v) => MapEntry(k, v.toMap())),
        'trumpRevealed': state.trumpRevealed,
      });
    }
  }

  Future<void> _resolveRound(
    Game28State state,
    Map<String, int> finalTrickPoints,
    Map<String, PlayingCard> lastTrick,
  ) async {
    final bidTeam = state.bidWinnerTeam!;
    final otherTeam = 1 - bidTeam;
    final bidTeamPts = finalTrickPoints['t$bidTeam'] ?? 0;
    final bidMet = bidTeamPts >= state.currentBid;
    final isThani = bidTeamPts == 28; // bidding team won every card point

    // Scoring multipliers
    // Thani (+3): bidding team swept all 28 points
    // High bid (+2): bid ≥ 20 succeeded, or defending team stopped one
    // Standard (+1): everything else
    final int gamePointsToAward;
    if (bidMet) {
      gamePointsToAward = isThani ? 3 : (state.currentBid >= 20 ? 2 : 1);
    } else {
      gamePointsToAward = state.currentBid >= 20 ? 2 : 1;
    }

    final newGamePoints = Map<String, int>.from(state.teamGamePoints);
    if (bidMet) {
      newGamePoints['t$bidTeam'] =
          (newGamePoints['t$bidTeam'] ?? 0) + gamePointsToAward;
    } else {
      newGamePoints['t$otherTeam'] =
          (newGamePoints['t$otherTeam'] ?? 0) + gamePointsToAward;
    }

    GameLogger.instance.game28RoundEnd(
      roomId: state.roomId,
      roundNumber: state.roundNumber,
      bid: state.currentBid,
      bidMet: bidMet,
      isThani: isThani,
      gamePointsAwarded: gamePointsToAward,
      teamGamePoints: newGamePoints,
    );
    debugPrint('[28] round ${state.roundNumber} end — bid=$bidMet '
        'bidTeam=$bidTeam pts=$bidTeamPts/${state.currentBid} '
        '+${gamePointsToAward}gp${isThani ? ' THANI' : ''} '
        'gamePoints=$newGamePoints');

    final gameOver = newGamePoints.values.any((p) => p >= state.targetScore);

    await _ref(state.roomId).update({
      'phase': gameOver
          ? Game28Phase.gameOver.index
          : Game28Phase.roundEnd.index,
      'teamTrickPoints': finalTrickPoints,
      'teamGamePoints': newGamePoints,
      'currentTrick': lastTrick.map((k, v) => MapEntry(k, v.toMap())),
      'trumpRevealed': true,
    });
  }

  // ── Next trick ────────────────────────────────────────────────────────────

  Future<void> startNextTrick(Game28State state) async {
    final leader = state.currentTurn ?? state.playerOrder.first;
    await _ref(state.roomId).update({
      'phase': Game28Phase.playing.index,
      'currentTrick': {},
      'leadSuit': null,
      'leadPlayer': null,
      'currentTurn': leader,
      'trumpRevealRequired': false,
    });
  }

  // ── Next round ────────────────────────────────────────────────────────────

  Future<void> startNextRound(Game28State state) async {
    await startGame(state);
  }

  // ── Stream ────────────────────────────────────────────────────────────────

  Stream<Game28State?> roomStream(String roomId) =>
      _ref(roomId).onValue.map((event) {
        if (!event.snapshot.exists) return null;
        return Game28State.fromMap(
            event.snapshot.value as Map<dynamic, dynamic>);
      });

  Future<Game28State?> getFreshState(String roomId) async {
    final snap = await _ref(roomId).get();
    if (!snap.exists) return null;
    return Game28State.fromMap(snap.value as Map<dynamic, dynamic>);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _nextActive(
      List<String> order, String current, List<String> passed) {
    final after = [
      ...order.skipWhile((id) => id != current).skip(1),
      ...order.takeWhile((id) => id != current),
    ];
    return after.firstWhere((id) => !passed.contains(id),
        orElse: () => order.first);
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return List.generate(4, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}

const _botNames = [
  'Arjun', 'Priya', 'Rahul', 'Ananya', 'Vikram', 'Sneha',
  'Karthik', 'Divya', 'Rohan', 'Meera', 'Aditya', 'Kavya',
  'Alex', 'Emma', 'Jake', 'Olivia', 'Liam', 'Sophia',
  'Noah', 'Ava', 'Ethan', 'Mia', 'Mason', 'Chloe',
];
