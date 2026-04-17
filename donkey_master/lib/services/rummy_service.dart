import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/rummy_models.dart';
import 'rummy_bot_service.dart';

class RummyService {
  static final RummyService _instance = RummyService._();
  static RummyService get instance => _instance;
  RummyService._();

  final _db = FirebaseDatabase.instance;
  final _rng = Random();

  DatabaseReference _roomRef(String roomId) =>
      _db.ref('rummy_rooms/$roomId');

  DatabaseReference _gameRef(String roomId) =>
      _db.ref('rummy_games/$roomId');

  // ── Find or create a waiting room ─────────────────────────────

  Future<String> findOrCreateRoom({
    required String playerId,
    required String playerName,
    required int maxPlayers,
  }) async {
    debugPrint('[Rummy] findOrCreateRoom playerId=$playerId maxPlayers=$maxPlayers');
    final snap = await _db
        .ref('rummy_rooms')
        .orderByChild('status')
        .equalTo('waiting')
        .get()
        .catchError((e) {
      debugPrint('[Rummy] ERROR querying rummy_rooms: $e');
      throw e;
    });

    debugPrint('[Rummy] query result: exists=${snap.exists}');
    if (snap.exists) {
      final rooms = Map<String, dynamic>.from(snap.value as Map);
      debugPrint('[Rummy] found ${rooms.length} waiting room(s)');
      for (final entry in rooms.entries) {
        final room = Map<String, dynamic>.from(entry.value as Map);
        final players = room['players'] != null
            ? Map<String, dynamic>.from(room['players'] as Map)
            : <String, dynamic>{};
        debugPrint('[Rummy] checking room ${entry.key}: maxPlayers=${room['maxPlayers']} players=${players.length}');
        if (room['maxPlayers'] != maxPlayers) continue;
        if (players.length >= maxPlayers) continue;
        debugPrint('[Rummy] joining existing room ${entry.key}');
        await _joinRoom(
          roomId: entry.key,
          playerId: playerId,
          playerName: playerName,
          currentCount: players.length,
          maxPlayers: maxPlayers,
        );
        return entry.key;
      }
    }

    debugPrint('[Rummy] no suitable room found — creating new one');
    return _createRoom(
      playerId: playerId,
      playerName: playerName,
      maxPlayers: maxPlayers,
    );
  }

  Future<String> _createRoom({
    required String playerId,
    required String playerName,
    required int maxPlayers,
  }) async {
    final roomId = _db.ref('rummy_rooms').push().key!;
    debugPrint('[Rummy] creating room $roomId (max=$maxPlayers)');
    await _roomRef(roomId).set({
      'roomId': roomId,
      'hostId': playerId,
      'maxPlayers': maxPlayers,
      'status': 'waiting',
      'createdAt': ServerValue.timestamp,
      'players': {
        playerId: {
          'id': playerId,
          'name': playerName,
          'isHost': true,
          'joinedAt': ServerValue.timestamp,
        },
      },
    }).catchError((e) {
      debugPrint('[Rummy] ERROR creating room $roomId: $e');
      throw e;
    });
    debugPrint('[Rummy] room $roomId created successfully');
    return roomId;
  }

  Future<void> _joinRoom({
    required String roomId,
    required String playerId,
    required String playerName,
    required int currentCount,
    required int maxPlayers,
  }) async {
    debugPrint('[Rummy] joining room $roomId ($currentCount/$maxPlayers)');
    await _roomRef(roomId).child('players/$playerId').set({
      'id': playerId,
      'name': playerName,
      'isHost': false,
      'joinedAt': ServerValue.timestamp,
    });
    if (currentCount + 1 >= maxPlayers) {
      await _roomRef(roomId).child('status').set('ready');
    }
  }

  // ── Fill remaining seats with bots ────────────────────────────

  Future<void> fillRoomWithBots({
    required String roomId,
    required int maxPlayers,
    required int currentCount,
  }) async {
    debugPrint('[Rummy] filling ${maxPlayers - currentCount} bot seats in $roomId');
    final updates = <String, dynamic>{};
    for (int i = 0; i < maxPlayers - currentCount; i++) {
      final id = RummyBotService.botId(i);
      updates['players/$id'] = {
        'id': id,
        'name': RummyBotService.botName(i),
        'isHost': false,
        'joinedAt': ServerValue.timestamp,
      };
    }
    updates['status'] = 'ready';
    await _roomRef(roomId).update(updates);
    debugPrint('[Rummy] bots added, room marked ready');
  }

  // ── Leave a room ───────────────────────────────────────────────

  Future<void> leaveRoom(String roomId, String playerId) async {
    final snap = await _roomRef(roomId).get();
    if (!snap.exists) return;

    final room = Map<String, dynamic>.from(snap.value as Map);
    final players = room['players'] != null
        ? Map<String, dynamic>.from(room['players'] as Map)
        : <String, dynamic>{};

    players.remove(playerId);

    if (players.isEmpty) {
      await _roomRef(roomId).remove();
      return;
    }

    await _roomRef(roomId).child('players/$playerId').remove();

    if (room['hostId'] == playerId) {
      final newHostId = players.keys.first;
      await _roomRef(roomId).child('hostId').set(newHostId);
      await _roomRef(roomId).child('players/$newHostId/isHost').set(true);
    }

    if (room['status'] == 'ready') {
      await _roomRef(roomId).child('status').set('waiting');
    }
  }

  // ── Start game (called by host) ────────────────────────────────

  Future<void> startGame({
    required String roomId,
    required Map<String, String> playerNames, // id → name
    required List<String> turnOrder,
  }) async {
    debugPrint('[Rummy] startGame roomId=$roomId players=${turnOrder.length}');

    // Build and shuffle deck
    final deck = buildRummyDeck()..shuffle(_rng);

    // Pull wild joker — first card that is NOT a printed joker
    RummyCard wildJoker = const RummyCard(rank: 0, suit: -1, isPrintedJoker: true);
    int wildIdx = 0;
    for (int i = 0; i < deck.length; i++) {
      if (!deck[i].isPrintedJoker) {
        wildJoker = deck[i];
        wildIdx = i;
        break;
      }
    }
    deck.removeAt(wildIdx);

    // Deal 13 cards to each player
    final hands = <String, List<RummyCard>>{};
    for (final id in turnOrder) {
      hands[id] = deck.sublist(0, 13);
      deck.removeRange(0, 13);
    }

    // Flip one card to open deck
    final firstOpen = deck.removeAt(0);

    // Build player meta map (no hands — stored separately)
    final playersMeta = {
      for (final id in turnOrder)
        id: {
          'id': id,
          'name': playerNames[id] ?? id,
          'handSize': 13,
          'hasDropped': false,
        }
    };

    // Build hands map for Firebase
    final handsMap = {
      for (final entry in hands.entries)
        entry.key: entry.value.map((c) => c.toMap()).toList()
    };

    // Write game state
    await _gameRef(roomId).set({
      'roomId': roomId,
      'phase': 'draw',
      'currentTurn': turnOrder.first,
      'turnOrder': turnOrder,
      'wildJoker': wildJoker.toMap(),
      'openDeck': [firstOpen.toMap()],
      'closedDeck': deck.map((c) => c.toMap()).toList(),
      'closedDeckCount': deck.length,
      'players': playersMeta,
      'hands': handsMap,
    });

    // Mark room as started so lobby screens navigate
    await _roomRef(roomId).child('status').set('started');
    debugPrint('[Rummy] game started — wild joker: $wildJoker');
  }

  // ── Draw from closed deck ──────────────────────────────────────

  Future<void> drawFromClosed(String roomId, String playerId) async {
    debugPrint('[Rummy] $playerId drawing from closed deck');
    final snap = await _gameRef(roomId).get();
    if (!snap.exists) return;
    final data = Map<String, dynamic>.from(snap.value as Map);

    final closedRaw = (data['closedDeck'] as List?)?.cast<dynamic>() ?? [];
    if (closedRaw.isEmpty) {
      await _reshuffleOpenIntoClosed(roomId, data);
      return drawFromClosed(roomId, playerId);
    }

    final closedDeck = closedRaw.map((c) => RummyCard.fromMap(c as Map)).toList();
    final drawn = closedDeck.removeAt(0);

    final handRaw = ((data['hands'] as Map)[playerId] as List?)?.cast<dynamic>() ?? [];
    final hand = handRaw.map((c) => RummyCard.fromMap(c as Map)).toList();
    hand.add(drawn);

    await _gameRef(roomId).update({
      'closedDeck': closedDeck.map((c) => c.toMap()).toList(),
      'closedDeckCount': closedDeck.length,
      'hands/$playerId': hand.map((c) => c.toMap()).toList(),
      'players/$playerId/handSize': hand.length,
      'phase': 'discard',
    });
    debugPrint('[Rummy] $playerId drew $drawn from closed deck');
  }

  // ── Draw from open deck ────────────────────────────────────────

  Future<void> drawFromOpen(String roomId, String playerId) async {
    debugPrint('[Rummy] $playerId drawing from open deck');
    final snap = await _gameRef(roomId).get();
    if (!snap.exists) return;
    final data = Map<String, dynamic>.from(snap.value as Map);

    final openRaw = (data['openDeck'] as List?)?.cast<dynamic>() ?? [];
    if (openRaw.isEmpty) return;

    final openDeck = openRaw.map((c) => RummyCard.fromMap(c as Map)).toList();
    final drawn = openDeck.removeLast(); // top card

    final handRaw = ((data['hands'] as Map)[playerId] as List?)?.cast<dynamic>() ?? [];
    final hand = handRaw.map((c) => RummyCard.fromMap(c as Map)).toList();
    hand.add(drawn);

    await _gameRef(roomId).update({
      'openDeck': openDeck.map((c) => c.toMap()).toList(),
      'hands/$playerId': hand.map((c) => c.toMap()).toList(),
      'players/$playerId/handSize': hand.length,
      'phase': 'discard',
    });
    debugPrint('[Rummy] $playerId drew $drawn from open deck');
  }

  // ── Discard a card ─────────────────────────────────────────────

  Future<void> discardCard(String roomId, String playerId, int cardIndex) async {
    debugPrint('[Rummy] $playerId discarding card at index $cardIndex');
    final snap = await _gameRef(roomId).get();
    if (!snap.exists) return;
    final data = Map<String, dynamic>.from(snap.value as Map);

    final handRaw = ((data['hands'] as Map)[playerId] as List?)?.cast<dynamic>() ?? [];
    final hand = handRaw.map((c) => RummyCard.fromMap(c as Map)).toList();
    if (cardIndex >= hand.length) return;

    final discarded = hand.removeAt(cardIndex);

    final openRaw = (data['openDeck'] as List?)?.cast<dynamic>() ?? [];
    final openDeck = openRaw.map((c) => RummyCard.fromMap(c as Map)).toList();
    openDeck.add(discarded);

    // Advance turn
    final turnOrder = (data['turnOrder'] as List).map((e) => e.toString()).toList();
    final currentIdx = turnOrder.indexOf(playerId);
    final nextIdx = (currentIdx + 1) % turnOrder.length;
    final nextPlayer = turnOrder[nextIdx];

    await _gameRef(roomId).update({
      'openDeck': openDeck.map((c) => c.toMap()).toList(),
      'hands/$playerId': hand.map((c) => c.toMap()).toList(),
      'players/$playerId/handSize': hand.length,
      'currentTurn': nextPlayer,
      'phase': 'draw',
    });
    debugPrint('[Rummy] $playerId discarded $discarded — next turn: $nextPlayer');
  }

  // ── Reshuffle open deck into closed ───────────────────────────

  Future<void> _reshuffleOpenIntoClosed(
      String roomId, Map<String, dynamic> data) async {
    debugPrint('[Rummy] reshuffling open deck into closed deck');
    final openRaw = (data['openDeck'] as List?)?.cast<dynamic>() ?? [];
    final openDeck = openRaw.map((c) => RummyCard.fromMap(c as Map)).toList();
    if (openDeck.length <= 1) return;

    final top = openDeck.removeLast();
    openDeck.shuffle(_rng);

    await _gameRef(roomId).update({
      'closedDeck': openDeck.map((c) => c.toMap()).toList(),
      'closedDeckCount': openDeck.length,
      'openDeck': [top.toMap()],
    });
  }

  // ── Drop player ───────────────────────────────────────────────

  Future<void> dropPlayer(String roomId, String playerId) async {
    debugPrint('[Rummy] $playerId dropping');
    final snap = await _gameRef(roomId).get();
    if (!snap.exists) return;
    final data = Map<String, dynamic>.from(snap.value as Map);

    final phase = data['phase'] as String? ?? 'draw';
    final penalty = phase == 'draw' ? 20 : 40;

    final turnOrder = (data['turnOrder'] as List)
        .map((e) => e.toString())
        .toList()
      ..remove(playerId);

    final updates = <String, dynamic>{
      'turnOrder': turnOrder,
      'scores/$playerId': penalty,
      'players/$playerId/hasDropped': true,
    };

    // Advance turn if it was this player's turn
    if (data['currentTurn'] == playerId && turnOrder.isNotEmpty) {
      updates['currentTurn'] = turnOrder.first;
      updates['phase'] = 'draw';
    }

    // Only 1 player left → they win
    if (turnOrder.length == 1) {
      final winnerId = turnOrder.first;
      updates['phase'] = 'gameOver';
      updates['winnerId'] = winnerId;
      updates['scores/$winnerId'] = 0;
    }

    await _gameRef(roomId).update(updates);
    debugPrint('[Rummy] $playerId dropped with $penalty pts');
  }

  // ── Declare game ───────────────────────────────────────────────

  /// Returns null on success, error string on validation failure.
  Future<String?> declareGame(
    String roomId,
    String playerId,
    List<List<RummyCard>> melds,
  ) async {
    debugPrint('[Rummy] $playerId declaring');
    final snap = await _gameRef(roomId).get();
    if (!snap.exists) return 'Game not found';
    final data = Map<String, dynamic>.from(snap.value as Map);

    final wildJokerRaw = data['wildJoker'] as Map;
    final wildRank = (wildJokerRaw['rank'] as num).toInt();

    final error = validateDeclaration(melds, wildRank);
    if (error != null) {
      debugPrint('[Rummy] invalid declaration: $error');
      // 80-point penalty for wrong declaration
      await _gameRef(roomId).update({'scores/$playerId': 80});
      return error;
    }

    // Build scores: winner = 0, others = deadwood capped at 80
    final handsRaw = data['hands'] != null
        ? Map<String, dynamic>.from(data['hands'] as Map)
        : <String, dynamic>{};

    final scores = <String, int>{playerId: 0};
    for (final entry in handsRaw.entries) {
      if (entry.key == playerId) continue;
      final cards = (entry.value as List)
          .map((c) => RummyCard.fromMap(c as Map))
          .toList();
      final deadwood = cards.fold(0, (s, c) => s + c.points);
      scores[entry.key] = deadwood.clamp(0, 80);
    }

    await _gameRef(roomId).update({
      'phase': 'gameOver',
      'winnerId': playerId,
      'scores': scores,
    });
    debugPrint('[Rummy] $playerId declared — scores: $scores');
    return null;
  }

  // ── Game stream ────────────────────────────────────────────────

  Stream<RummyGameState?> gameStream(String roomId) {
    return _gameRef(roomId).onValue.map((event) {
      if (!event.snapshot.exists) return null;
      try {
        final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        final handsRaw = data['hands'] != null
            ? Map<String, dynamic>.from(data['hands'] as Map)
            : <String, dynamic>{};
        final hands = <String, List<RummyCard>>{};
        for (final entry in handsRaw.entries) {
          final cardList = (entry.value as List?)?.cast<dynamic>() ?? [];
          hands[entry.key] =
              cardList.map((c) => RummyCard.fromMap(c as Map)).toList();
        }
        return RummyGameState.fromMap(roomId, data, hands);
      } catch (e) {
        debugPrint('[Rummy] gameStream parse error: $e');
        return null;
      }
    });
  }

  // ── Room stream ────────────────────────────────────────────────

  Stream<Map<String, dynamic>?> roomStream(String roomId) {
    return _roomRef(roomId).onValue.map((event) {
      if (!event.snapshot.exists) return null;
      return Map<String, dynamic>.from(event.snapshot.value as Map);
    });
  }
}
