import 'dart:async';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
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

  DatabaseReference _handRef(String roomId, String playerId) =>
      _db.ref('rummy_hands/$roomId/$playerId');

  // ── Find or create a waiting room ─────────────────────────────
  //
  // Uses a Firebase transaction to atomically claim a seat. This prevents
  // the TOCTOU race where N clients all see the same "not full" snapshot
  // and simultaneously join, overcrowding the room.
  //
  // Flow:
  //   1. Query for waiting rooms (read-only, cheap).
  //   2. For each candidate, run a transaction on the full room node.
  //      The transaction handler is retried automatically if another
  //      client commits a write between our read and our write.
  //   3. If the transaction commits → we have a seat, done.
  //   4. If every candidate is full by the time we transact → create a
  //      new room (single writer, no contention).

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
        final roomId = entry.key;
        final room = Map<String, dynamic>.from(entry.value as Map);
        if (room['maxPlayers'] != maxPlayers) continue;

        debugPrint('[Rummy] attempting transactional join of $roomId');
        final joined = await _tryJoinRoom(
          roomId: roomId,
          playerId: playerId,
          playerName: playerName,
          maxPlayers: maxPlayers,
        );
        if (joined) {
          debugPrint('[Rummy] successfully joined $roomId via transaction');
          return roomId;
        }
        debugPrint('[Rummy] room $roomId was full or gone — trying next');
      }
    }

    debugPrint('[Rummy] no suitable room found — creating new one');
    return _createRoom(
      playerId: playerId,
      playerName: playerName,
      maxPlayers: maxPlayers,
    );
  }

  /// Atomically joins [roomId]. Returns true if the seat was claimed,
  /// false if the room was full, wrong size, or no longer waiting.
  Future<bool> _tryJoinRoom({
    required String roomId,
    required String playerId,
    required String playerName,
    required int maxPlayers,
  }) async {
    final result = await _roomRef(roomId).runTransaction((data) {
      if (data == null) return Transaction.abort();

      final room = Map<String, dynamic>.from(data as Map);

      // Re-validate inside the transaction — the snapshot from the query
      // may already be stale by the time we get here.
      if (room['status'] != 'waiting') return Transaction.abort();
      if (room['maxPlayers'] != maxPlayers) return Transaction.abort();

      final players = room['players'] != null
          ? Map<String, dynamic>.from(room['players'] as Map)
          : <String, dynamic>{};

      if (players.length >= maxPlayers) return Transaction.abort();
      if (players.containsKey(playerId)) return Transaction.abort();

      players[playerId] = {
        'id': playerId,
        'name': playerName,
        'isHost': false,
        'joinedAt': ServerValue.timestamp,
      };

      room['players'] = players;
      if (players.length >= maxPlayers) room['status'] = 'ready';

      return Transaction.success(room);
    });

    return result.committed;
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

    // Build one atomic update so all changes land in a single write.
    // The rule is evaluated against pre-write data, so auth.uid is still
    // in players when Firebase checks the permission.
    final updates = <String, dynamic>{
      'players/$playerId': null, // removes the slot
    };

    if (room['hostId'] == playerId) {
      final newHostId = players.keys.first;
      updates['hostId'] = newHostId;
      updates['players/$newHostId/isHost'] = true;
    }

    if (room['status'] == 'ready') {
      updates['status'] = 'waiting';
    }

    await _roomRef(roomId).update(updates);
  }

  // ── Start game (host triggers server-side deal) ────────────────
  //
  // Dealing is done entirely in the `dealRummyGame` Cloud Function so
  // that no client ever receives the full deck or any other player's
  // hand. The function writes each hand to rummy_hands/{roomId}/{uid}
  // using the Admin SDK, which bypasses the per-player read rules.

  Future<void> startGame({required String roomId, int targetScore = 0}) async {
    debugPrint('[Rummy] startGame — calling dealRummyGame CF for $roomId (target=$targetScore)');
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('dealRummyGame');
      final result = await callable.call({
        'roomId': roomId,
        'targetScore': targetScore,
        'sessionScores': <String, int>{},
        'round': 1,
      });
      debugPrint('[Rummy] startGame CF returned: ${result.data}');
    } catch (e, st) {
      debugPrint('[Rummy] startGame CF threw: $e\n$st');
      rethrow;
    }
  }

  Future<void> startNextRound(String roomId, RummyGameState state) async {
    debugPrint('[Rummy] startNextRound — round ${state.round + 1} in $roomId');
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('dealRummyGame');
      final result = await callable.call({
        'roomId': roomId,
        'targetScore': state.targetScore,
        'sessionScores': state.sessionScores,
        'round': state.round + 1,
        'nextRound': true,
      });
      debugPrint('[Rummy] startNextRound CF returned: ${result.data}');
    } catch (e, st) {
      debugPrint('[Rummy] startNextRound CF threw: $e\n$st');
      rethrow;
    }
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

    // Read hand from private path, not the shared game state
    final handSnap = await _handRef(roomId, playerId).get();
    final hand = handSnap.exists
        ? ((handSnap.value as List).cast<dynamic>())
            .map((c) => RummyCard.fromMap(c as Map))
            .toList()
        : <RummyCard>[];
    hand.add(drawn);

    await Future.wait([
      _gameRef(roomId).update({
        'closedDeck': closedDeck.map((c) => c.toMap()).toList(),
        'closedDeckCount': closedDeck.length,
        'players/$playerId/handSize': hand.length,
        'phase': 'discard',
      }),
      _handRef(roomId, playerId).set(hand.map((c) => c.toMap()).toList()),
    ]);
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
    final drawn = openDeck.removeLast();

    final handSnap = await _handRef(roomId, playerId).get();
    final hand = handSnap.exists
        ? ((handSnap.value as List).cast<dynamic>())
            .map((c) => RummyCard.fromMap(c as Map))
            .toList()
        : <RummyCard>[];
    hand.add(drawn);

    await Future.wait([
      _gameRef(roomId).update({
        'openDeck': openDeck.map((c) => c.toMap()).toList(),
        'players/$playerId/handSize': hand.length,
        'phase': 'discard',
      }),
      _handRef(roomId, playerId).set(hand.map((c) => c.toMap()).toList()),
    ]);
    debugPrint('[Rummy] $playerId drew $drawn from open deck');
  }

  // ── Discard a card ─────────────────────────────────────────────

  Future<void> discardCard(String roomId, String playerId, int cardIndex) async {
    debugPrint('[Rummy] $playerId discarding card at index $cardIndex');
    final snap = await _gameRef(roomId).get();
    if (!snap.exists) return;
    final data = Map<String, dynamic>.from(snap.value as Map);

    final handSnap = await _handRef(roomId, playerId).get();
    if (!handSnap.exists) return;
    final hand = ((handSnap.value as List).cast<dynamic>())
        .map((c) => RummyCard.fromMap(c as Map))
        .toList();
    if (cardIndex >= hand.length) return;

    final discarded = hand.removeAt(cardIndex);

    final openRaw = (data['openDeck'] as List?)?.cast<dynamic>() ?? [];
    final openDeck = openRaw.map((c) => RummyCard.fromMap(c as Map)).toList();
    openDeck.add(discarded);

    final turnOrder = (data['turnOrder'] as List).map((e) => e.toString()).toList();
    final nextPlayer = turnOrder[(turnOrder.indexOf(playerId) + 1) % turnOrder.length];

    await Future.wait([
      _gameRef(roomId).update({
        'openDeck': openDeck.map((c) => c.toMap()).toList(),
        'players/$playerId/handSize': hand.length,
        'currentTurn': nextPlayer,
        'phase': 'draw',
      }),
      _handRef(roomId, playerId).set(hand.map((c) => c.toMap()).toList()),
    ]);
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
  //
  // Validation and scoring run in the `declareRummyGame` Cloud Function:
  //   1. The server re-reads the player's hand from rummy_hands to ensure
  //      they cannot fabricate cards they don't hold.
  //   2. Deadwood is calculated from the other players' server-held hands,
  //      so scores cannot be tampered with client-side.
  //
  // Returns null on success, an error string on invalid declaration.

  Future<String?> declareGame(
    String roomId,
    String playerId,
    List<List<RummyCard>> melds,
  ) async {
    debugPrint('[Rummy] $playerId declaring via CF');
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('declareRummyGame');
      final result = await callable.call({
        'roomId': roomId,
        'melds': melds
            .map((meld) => meld.map((c) => c.toMap()).toList())
            .toList(),
      });
      final error = (result.data as Map<dynamic, dynamic>)['error'] as String?;
      if (error != null) debugPrint('[Rummy] declaration rejected: $error');
      return error;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[Rummy] declareGame CF error: ${e.code} ${e.message}');
      return e.message ?? 'Declaration failed';
    }
  }

  // ── Game stream ────────────────────────────────────────────────
  //
  // Merges two Firebase streams:
  //   • rummy_games/{roomId}          — shared state (no hand data)
  //   • rummy_hands/{roomId}/{id}     — own hand + one stream per bot
  //
  // Each client only subscribes to their own hand slot.  The host also
  // subscribes to bot hand slots so it can drive bot moves.
  // Emits a new RummyGameState whenever either source updates.

  Stream<RummyGameState?> gameStream(
    String roomId,
    String playerId,
    List<String> botIds,
  ) {
    final controller = StreamController<RummyGameState?>();
    Map<dynamic, dynamic>? latestGameData;
    final hands = <String, List<RummyCard>>{};
    final subs = <StreamSubscription<dynamic>>[];

    List<RummyCard> parseHand(DataSnapshot snap) {
      if (!snap.exists) return [];
      return ((snap.value as List).cast<dynamic>())
          .map((c) => RummyCard.fromMap(c as Map))
          .toList();
    }

    void emit() {
      if (latestGameData == null) return;
      try {
        controller.add(
          RummyGameState.fromMap(roomId, latestGameData!, Map.from(hands)),
        );
      } catch (e) {
        debugPrint('[Rummy] gameStream emit error: $e');
      }
    }

    void onPermissionError(Object e) {
      // Expected when the player leaves the room and the listener is still
      // briefly active — treat as game-gone rather than an unhandled error.
      debugPrint('[Rummy] gameStream permission error (leaving): $e');
      if (!controller.isClosed) controller.add(null);
    }

    // Shared game state
    subs.add(_gameRef(roomId).onValue.listen((event) {
      if (!event.snapshot.exists) {
        controller.add(null);
        return;
      }
      latestGameData =
          Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      emit();
    }, onError: onPermissionError));

    // Own hand (private path)
    subs.add(_handRef(roomId, playerId).onValue.listen((event) {
      hands[playerId] = parseHand(event.snapshot);
      emit();
    }, onError: onPermissionError));

    // Bot hands (host only — rule allows host to read bot_* slots)
    for (final botId in botIds) {
      subs.add(_handRef(roomId, botId).onValue.listen((event) {
        hands[botId] = parseHand(event.snapshot);
        emit();
      }, onError: onPermissionError));
    }

    controller.onCancel = () {
      for (final s in subs) {
        s.cancel();
      }
    };

    return controller.stream;
  }

  // ── Room stream ────────────────────────────────────────────────

  Stream<Map<String, dynamic>?> roomStream(String roomId) {
    return _roomRef(roomId).onValue.map((event) {
      if (!event.snapshot.exists) return null;
      return Map<String, dynamic>.from(event.snapshot.value as Map);
    });
  }
}
