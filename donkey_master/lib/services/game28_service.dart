import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/card_model.dart';
import '../models/game28_state.dart';

class Game28Service {
  static final Game28Service _instance = Game28Service._();
  static Game28Service get instance => _instance;
  Game28Service._();

  final _db = FirebaseDatabase.instance;
  DatabaseReference _ref(String roomId) => _db.ref('game28_rooms/$roomId');

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
    // Deal 8 cards to each of the 4 players
    final updatedPlayers =
        Map<String, Game28Player>.from(state.players);
    for (int i = 0; i < order.length; i++) {
      final hand = deck.sublist(i * 8, i * 8 + 8);
      updatedPlayers[order[i]] =
          updatedPlayers[order[i]]!.copyWith(hand: hand);
    }
    // Bidding starts with player at seat 0 (host)
    final firstBidder = order[0];
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
      'teamTrickPoints': {'t0': 0, 't1': 0},
      'players': updatedPlayers.map((k, v) => MapEntry(k, v.toMap())),
    });
    debugPrint('[28] startGame — round ${state.roundNumber + 1}');
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
    // Trump is stored in DB. UI only shows it to the bidder.
    // First trick leader = player after bidder in order.
    final order = state.playerOrder;
    final bidIdx = order.indexOf(playerId);
    final firstLeader = order[(bidIdx + 1) % order.length];
    await _ref(state.roomId).update({
      'trumpSuit': suitIndex,
      'phase': Game28Phase.playing.index,
      'currentTurn': firstLeader,
      'leadPlayer': null,
      'currentTrick': {},
      'leadSuit': null,
    });
    debugPrint('[28] trump = ${Suit.values[suitIndex]} — $playerId leads $firstLeader');
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

    // Detect trump reveal
    final isTrump =
        state.trumpSuit != null && card.suit.index == state.trumpSuit;
    final trumpRevealed = state.trumpRevealed || isTrump;

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
      'trumpRevealed': trumpRevealed,
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

    final hasTrump =
        trumpSuit != null && trick.values.any((c) => c.suit.index == trumpSuit);

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
        'trumpRevealed': state.trumpRevealed || hasTrump,
      });
    }
  }

  Future<void> _resolveRound(
    Game28State state,
    Map<String, int> finalTrickPoints,
    Map<String, PlayingCard> lastTrick,
  ) async {
    final bidTeam = state.bidWinnerTeam!;
    final bidTeamPts = finalTrickPoints['t$bidTeam'] ?? 0;
    final bidMet = bidTeamPts >= state.currentBid;

    final newGamePoints = Map<String, int>.from(state.teamGamePoints);
    if (bidMet) {
      newGamePoints['t$bidTeam'] = (newGamePoints['t$bidTeam'] ?? 0) + 1;
    } else {
      final otherTeam = 1 - bidTeam;
      newGamePoints['t$otherTeam'] = (newGamePoints['t$otherTeam'] ?? 0) + 1;
    }

    debugPrint('[28] round ${state.roundNumber} end — bid=$bidMet '
        'bidTeam=$bidTeam pts=$bidTeamPts/${state.currentBid} '
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
