import 'dart:async';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/wildcard_models.dart';
import '../utils/game_session_tracker.dart';
import 'error_log_service.dart';

class WildCardService with GameGuard {
  static final WildCardService _instance = WildCardService._();
  static WildCardService get instance => _instance;
  WildCardService._();

  @override
  String get gameName => 'wildcard';

  final _db = FirebaseDatabase.instance;
  final _rng = Random();

  DatabaseReference _roomRef(String roomId) =>
      _db.ref('wildcard_rooms/$roomId');
  DatabaseReference _gameRef(String roomId) =>
      _db.ref('wildcard_games/$roomId');
  DatabaseReference _handRef(String roomId, String playerId) =>
      _db.ref('wildcard_hands/$roomId/$playerId');

  // Firebase returns arrays as Maps with int keys in some SDK versions.
  List<dynamic> _fbList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value;
    if (value is Map) return value.values.toList();
    return [];
  }

  // ── Find or create room ───────────────────────────────────────────────────

  Future<String> findOrCreateRoom({
    required String playerId,
    required String playerName,
    required int maxPlayers,
  }) async {
    final snap = await _db
        .ref('wildcard_rooms')
        .orderByChild('status')
        .equalTo('waiting')
        .limitToFirst(10)
        .get();

    if (snap.exists) {
      final rooms = Map<String, dynamic>.from(snap.value as Map);
      for (final entry in rooms.entries) {
        final room = Map<String, dynamic>.from(entry.value as Map);
        if (room['maxPlayers'] != maxPlayers) continue;
        final joined = await _tryJoinRoom(
            entry.key, playerId, playerName, maxPlayers);
        if (joined) {
          GameSessionTracker.record('wildcard', entry.key);
          return entry.key;
        }
      }
    }
    final newRoomId = await _createRoom(playerId, playerName, maxPlayers);
    GameSessionTracker.record('wildcard', newRoomId);
    return newRoomId;
  }

  Future<bool> _tryJoinRoom(
      String roomId, String playerId, String playerName, int maxPlayers) async {
    bool joined = false;
    await _roomRef(roomId).runTransaction((data) {
      if (data == null) return Transaction.abort();
      final room = Map<String, dynamic>.from(data as Map);
      if (room['status'] != 'waiting') return Transaction.abort();
      final players = room['players'] != null
          ? Map<String, dynamic>.from(room['players'] as Map)
          : <String, dynamic>{};
      if (players.length >= maxPlayers) return Transaction.abort();
      players[playerId] = {'name': playerName};
      room['players'] = players;
      if (players.length >= maxPlayers) room['status'] = 'full';
      joined = true;
      return Transaction.success(room);
    });
    return joined;
  }

  Future<String> _createRoom(
      String playerId, String playerName, int maxPlayers) async {
    final roomId = _db.ref('wildcard_rooms').push().key!;
    await _roomRef(roomId).set({
      'hostId': playerId,
      'maxPlayers': maxPlayers,
      'status': 'waiting',
      'players': {
        playerId: {'name': playerName},
      },
    });
    debugPrint('[WildCard] created room $roomId');
    return roomId;
  }

  // ── Fill with bots ────────────────────────────────────────────────────────

  Future<void> fillRoomWithBots({
    required String roomId,
    required int maxPlayers,
    required int currentCount,
  }) async {
    const names = ['Priya', 'Arjun', 'Meera', 'Karthik', 'Divya', 'Rajan'];
    final botsNeeded = maxPlayers - currentCount;
    if (botsNeeded <= 0) return;
    final updates = <String, dynamic>{};
    for (int i = 0; i < botsNeeded; i++) {
      updates['players/bot_$i/name'] = names[i % names.length];
    }
    await _roomRef(roomId).update(updates);
    debugPrint('[WildCard] filled $botsNeeded bots in $roomId');
  }

  // ── Start game ────────────────────────────────────────────────────────────

  Future<void> startGame(String roomId) async {
    final roomSnap = await _roomRef(roomId).get();
    if (!roomSnap.exists) return;
    final room = Map<String, dynamic>.from(roomSnap.value as Map);
    final players = Map<String, dynamic>.from(room['players'] as Map);
    final hostId = room['hostId'] as String;

    final playerOrder = players.keys.toList()..shuffle(_rng);
    final playerNames = {
      for (final e in players.entries) e.key: e.value['name'] as String,
    };

    final deck = generateDeck(_rng);
    final cardCounts = <String, int>{};

    for (final pid in playerOrder) {
      final hand = deck.sublist(0, 7);
      deck.removeRange(0, 7);
      await _handRef(roomId, pid).set(hand.map((c) => c.toMap()).toList());
      cardCounts[pid] = 7;
    }

    WildPlayCard discardTop;
    do {
      discardTop = deck.removeAt(0);
    } while (discardTop.type == WildCardType.wild ||
        discardTop.type == WildCardType.wildDraw4);

    await _gameRef(roomId).set({
      'phase': 'playing',
      'playerOrder': playerOrder,
      'currentPlayerIdx': 0,
      'currentTurnId': playerOrder[0],
      'direction': 1,
      'currentColor': WildPlayCard.colorKey(discardTop.color),
      'discardTop': discardTop.toMap(),
      'deck': deck.map((c) => c.toMap()).toList(),
      'discardPile': [discardTop.toMap()],
      'cardCounts': cardCounts,
      'playerNames': playerNames,
      'hostId': hostId,
      'winner': null,
      'pendingDraw': null,
    });

    await _roomRef(roomId).update({'status': 'started'});
    debugPrint('[WildCard] game started in $roomId');
  }

  // ── Play card ─────────────────────────────────────────────────────────────

  Future<String?> playCard({
    required String roomId,
    required String playerId,
    required WildPlayCard card,
    WildCardColor? chosenColor,
  }) async {
    debugPrint('[WildCard] playCard: $playerId playing ${card.label} in $roomId');
    final gameSnap = await _gameRef(roomId).get();
    if (!gameSnap.exists) {
      debugPrint('[WildCard] playCard: game not found');
      return 'Game not found';
    }
    final data = Map<String, dynamic>.from(gameSnap.value as Map);
    if (data['phase'] != 'playing') {
      debugPrint('[WildCard] playCard: phase=${data['phase']}, not playing');
      return 'Game not active';
    }

    final state = WildCardGameState.fromMap(roomId, data);
    if (state.currentPlayerId != playerId) {
      debugPrint('[WildCard] playCard: not your turn — current=${state.currentPlayerId}, tried=$playerId');
      return 'Not your turn';
    }

    if (!card.canPlayOn(state.discardTop, state.currentColor)) {
      debugPrint('[WildCard] playCard: card cannot be played — top=${state.discardTop.label} color=${state.currentColor}');
      return 'Card cannot be played';
    }

    final handSnap = await _handRef(roomId, playerId).get();
    if (!handSnap.exists) {
      debugPrint('[WildCard] playCard: hand not found for $playerId');
      return 'Hand not found';
    }
    final hand = _fbList(handSnap.value)
        .map((e) => WildPlayCard.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
    debugPrint('[WildCard] playCard: hand size=${hand.length}');

    final idx = hand.indexWhere((c) =>
        c.color == card.color && c.type == card.type && c.value == card.value);
    if (idx < 0) {
      debugPrint('[WildCard] playCard: card not in hand — looking for ${card.label}, hand=${hand.map((c) => c.label).join(", ")}');
      return 'Card not in hand';
    }
    hand.removeAt(idx);

    final newColor = (card.type == WildCardType.wild ||
            card.type == WildCardType.wildDraw4)
        ? (chosenColor ?? WildCardColor.red)
        : card.color;

    var deckList = _fbList(data['deck'])
        .map((e) => WildPlayCard.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
    var discardPile = _fbList(data['discardPile'])
        .map((e) => WildPlayCard.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
    discardPile.add(card);

    final cardCounts = Map<String, int>.from({
      for (final e in (Map<String, dynamic>.from(data['cardCounts'] as Map)).entries)
        e.key: (e.value as num).toInt(),
    });
    cardCounts[playerId] = hand.length;

    if (hand.isEmpty) {
      await _handRef(roomId, playerId).set([]);
      await _gameRef(roomId).update({
        'phase': 'gameOver',
        'winner': playerId,
        'discardTop': card.toMap(),
        'discardPile': discardPile.map((c) => c.toMap()).toList(),
        'currentColor': WildPlayCard.colorKey(newColor),
        'cardCounts': cardCounts,
      });
      debugPrint('[WildCard] $playerId won in $roomId');
      return null;
    }

    await _handRef(roomId, playerId).set(hand.map((c) => c.toMap()).toList());

    int nextIdx = state.nextPlayerIdx();
    int newDirection = state.direction;
    int? pendingDraw;

    if (card.type == WildCardType.reverse) {
      newDirection = -state.direction;
      nextIdx = (state.currentPlayerIdx + newDirection + state.playerOrder.length) %
          state.playerOrder.length;
    } else if (card.type == WildCardType.skip) {
      nextIdx = state.nextPlayerIdx(skip: 1);
    } else if (card.type == WildCardType.draw2) {
      final targetPid = state.playerOrder[nextIdx];
      final drawn = _drawFromDeck(deckList, discardPile, 2);
      deckList = drawn.$1;
      discardPile = drawn.$2;
      final targetHandSnap = await _handRef(roomId, targetPid).get();
      final targetHand = _fbList(targetHandSnap.exists ? targetHandSnap.value : null)
          .map((e) => WildPlayCard.fromMap(Map<dynamic, dynamic>.from(e as Map)))
          .toList();
      targetHand.addAll(drawn.$3);
      await _handRef(roomId, targetPid)
          .set(targetHand.map((c) => c.toMap()).toList());
      cardCounts[targetPid] = targetHand.length;
      nextIdx = (state.currentPlayerIdx +
              newDirection * 2 +
              state.playerOrder.length * 2) %
          state.playerOrder.length;
    } else if (card.type == WildCardType.wildDraw4) {
      final targetPid = state.playerOrder[nextIdx];
      final drawn = _drawFromDeck(deckList, discardPile, 4);
      deckList = drawn.$1;
      discardPile = drawn.$2;
      final targetHandSnap = await _handRef(roomId, targetPid).get();
      final targetHand = _fbList(targetHandSnap.exists ? targetHandSnap.value : null)
          .map((e) => WildPlayCard.fromMap(Map<dynamic, dynamic>.from(e as Map)))
          .toList();
      targetHand.addAll(drawn.$3);
      await _handRef(roomId, targetPid)
          .set(targetHand.map((c) => c.toMap()).toList());
      cardCounts[targetPid] = targetHand.length;
      nextIdx = (state.currentPlayerIdx +
              newDirection * 2 +
              state.playerOrder.length * 2) %
          state.playerOrder.length;
    }

    await _gameRef(roomId).update({
      'discardTop': card.toMap(),
      'discardPile': discardPile.map((c) => c.toMap()).toList(),
      'deck': deckList.map((c) => c.toMap()).toList(),
      'currentColor': WildPlayCard.colorKey(newColor),
      'direction': newDirection,
      'currentPlayerIdx': nextIdx,
      'currentTurnId': state.playerOrder[nextIdx],
      'cardCounts': cardCounts,
      'pendingDraw': pendingDraw,
    });
    debugPrint('[WildCard] playCard: done — next player idx=$nextIdx (${state.playerOrder.length > nextIdx ? state.playerOrder[nextIdx] : "?"})');
    return null;
  }

  // ── Draw card ─────────────────────────────────────────────────────────────

  Future<WildPlayCard?> drawCard(String roomId, String playerId) async {
    debugPrint('[WildCard] drawCard: $playerId drawing in $roomId');
    final gameSnap = await _gameRef(roomId).get();
    if (!gameSnap.exists) {
      debugPrint('[WildCard] drawCard: game not found');
      return null;
    }
    final data = Map<String, dynamic>.from(gameSnap.value as Map);
    if (data['phase'] != 'playing') {
      debugPrint('[WildCard] drawCard: phase=${data['phase']}, aborting');
      return null;
    }

    final state = WildCardGameState.fromMap(roomId, data);
    if (state.currentPlayerId != playerId) {
      debugPrint('[WildCard] drawCard: not your turn — current=${state.currentPlayerId}, tried=$playerId');
      return null;
    }

    var deckList = _fbList(data['deck'])
        .map((e) => WildPlayCard.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
    var discardPile = _fbList(data['discardPile'])
        .map((e) => WildPlayCard.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();

    final drawn = _drawFromDeck(deckList, discardPile, 1);
    deckList = drawn.$1;
    discardPile = drawn.$2;
    final drawnCard = drawn.$3.first;

    final handSnap = await _handRef(roomId, playerId).get();
    final hand = _fbList(handSnap.exists ? handSnap.value : null)
        .map((e) => WildPlayCard.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
    hand.add(drawnCard);

    final cardCounts = Map<String, int>.from({
      for (final e in (Map<String, dynamic>.from(data['cardCounts'] as Map)).entries)
        e.key: (e.value as num).toInt(),
    });
    cardCounts[playerId] = hand.length;

    final nextIdx = state.nextPlayerIdx();

    await _handRef(roomId, playerId).set(hand.map((c) => c.toMap()).toList());
    await _gameRef(roomId).update({
      'deck': deckList.map((c) => c.toMap()).toList(),
      'discardPile': discardPile.map((c) => c.toMap()).toList(),
      'cardCounts': cardCounts,
      'currentPlayerIdx': nextIdx,
      'currentTurnId': state.playerOrder[nextIdx],
    });

    debugPrint('[WildCard] drawCard: $playerId drew ${drawnCard.label}, next idx=$nextIdx (${state.playerOrder.length > nextIdx ? state.playerOrder[nextIdx] : "?"})');
    return drawnCard;
  }

  // ── Internal: draw N cards, reshuffling discard if needed ─────────────────

  (List<WildPlayCard>, List<WildPlayCard>, List<WildPlayCard>) _drawFromDeck(
      List<WildPlayCard> deck,
      List<WildPlayCard> discardPile,
      int count) {
    if (deck.length < count && discardPile.length > 1) {
      final top = discardPile.removeLast();
      deck.addAll(discardPile..shuffle(_rng));
      discardPile = [top];
    }
    final drawn = <WildPlayCard>[];
    for (int i = 0; i < count && deck.isNotEmpty; i++) {
      drawn.add(deck.removeAt(0));
    }
    return (deck, discardPile, drawn);
  }

  // ── Bot play turn ─────────────────────────────────────────────────────────

  Future<void> botPlayTurn(String roomId) async {
    debugPrint('[WildCard] botPlayTurn: starting for $roomId');
    await Future.delayed(const Duration(milliseconds: 1200));

    final gameSnap = await _gameRef(roomId).get();
    if (!gameSnap.exists) {
      debugPrint('[WildCard] botPlayTurn: game not found');
      return;
    }
    final data = Map<String, dynamic>.from(gameSnap.value as Map);
    if (data['phase'] != 'playing') {
      debugPrint('[WildCard] botPlayTurn: phase=${data['phase']}, skipping');
      return;
    }

    final state = WildCardGameState.fromMap(roomId, data);
    final botId = state.currentPlayerId;
    debugPrint('[WildCard] botPlayTurn: currentPlayer=$botId, playerOrder=${state.playerOrder}, idx=${state.currentPlayerIdx}');
    if (!botId.startsWith('bot_')) {
      debugPrint('[WildCard] botPlayTurn: not a bot turn, skipping');
      return;
    }

    final handSnap = await _handRef(roomId, botId).get();
    if (!handSnap.exists) {
      debugPrint('[WildCard] botPlayTurn: hand not found for $botId');
      return;
    }
    final rawHandValue = handSnap.value;
    debugPrint('[WildCard] botPlayTurn: hand value type=${rawHandValue.runtimeType}');
    final hand = _fbList(rawHandValue)
        .map((e) => WildPlayCard.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();
    debugPrint('[WildCard] botPlayTurn: $botId has ${hand.length} cards: ${hand.map((c) => c.label).join(", ")}');
    debugPrint('[WildCard] botPlayTurn: discardTop=${state.discardTop.label}, currentColor=${state.currentColor}');

    final playable = hand
        .where((c) => c.canPlayOn(state.discardTop, state.currentColor))
        .toList();
    debugPrint('[WildCard] botPlayTurn: ${playable.length} playable cards: ${playable.map((c) => c.label).join(", ")}');

    if (playable.isEmpty) {
      debugPrint('[WildCard] botPlayTurn: no playable cards, drawing');
      await drawCard(roomId, botId);
      return;
    }

    final nonWild = playable
        .where((c) =>
            c.type != WildCardType.wild && c.type != WildCardType.wildDraw4)
        .toList();
    final chosen = nonWild.isNotEmpty ? nonWild.first : playable.first;
    debugPrint('[WildCard] botPlayTurn: $botId chose ${chosen.label}');

    WildCardColor? chosenColor;
    if (chosen.type == WildCardType.wild ||
        chosen.type == WildCardType.wildDraw4) {
      chosenColor = _mostCommonColor(hand);
      debugPrint('[WildCard] botPlayTurn: wild chosen, picking color=$chosenColor');
    }

    final err = await playCard(
      roomId: roomId,
      playerId: botId,
      card: chosen,
      chosenColor: chosenColor,
    );
    if (err != null) {
      debugPrint('[WildCard] botPlayTurn: playCard returned error: $err');
    } else {
      debugPrint('[WildCard] botPlayTurn: $botId played ${chosen.label} successfully');
    }
  }

  WildCardColor _mostCommonColor(List<WildPlayCard> hand) {
    final counts = <WildCardColor, int>{};
    for (final c in hand) {
      if (c.color != WildCardColor.wild) {
        counts[c.color] = (counts[c.color] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return WildCardColor.red;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  // ── Leave room ────────────────────────────────────────────────────────────

  Future<void> leaveRoom(String roomId, String playerId) async {
    await _roomRef(roomId).child('players/$playerId').remove();
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  Stream<Map<String, dynamic>?> roomStream(String roomId) =>
      _roomRef(roomId).onValue.map((e) {
        if (!e.snapshot.exists) return null;
        return Map<String, dynamic>.from(e.snapshot.value as Map);
      });

  Stream<WildCardGameState?> gameStream(String roomId) =>
      _gameRef(roomId).onValue.map((e) {
        if (!e.snapshot.exists) return null;
        try {
          return WildCardGameState.fromMap(
              roomId, Map<dynamic, dynamic>.from(e.snapshot.value as Map));
        } catch (err) {
          debugPrint('[WildCard] gameStream error: $err');
          ErrorLogService.instance.logAuto(game: 'wildcard', error: 'gameStream: $err');
          return null;
        }
      });

  Stream<List<WildPlayCard>?> handStream(String roomId, String playerId) =>
      _handRef(roomId, playerId).onValue.map((e) {
        if (!e.snapshot.exists) return null;
        try {
          return _fbList(e.snapshot.value)
              .map((c) =>
                  WildPlayCard.fromMap(Map<dynamic, dynamic>.from(c as Map)))
              .toList();
        } catch (err) {
          debugPrint('[WildCard] handStream error: $err');
          ErrorLogService.instance.logAuto(game: 'wildcard', error: 'handStream: $err');
          return null;
        }
      });
}
