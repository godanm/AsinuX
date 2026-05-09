import 'dart:async';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/tambola_models.dart';
import '../utils/game_session_tracker.dart';
import 'error_log_service.dart';

List<dynamic> _fbList(dynamic v) {
  if (v is List) return v;
  if (v is Map) return v.values.toList();
  return [];
}

class TambolaService with GameGuard {
  static final TambolaService _instance = TambolaService._();
  static TambolaService get instance => _instance;
  TambolaService._();

  @override
  String get gameName => 'tambola';

  final _db = FirebaseDatabase.instance;
  final _rng = Random();

  DatabaseReference _roomRef(String roomId) =>
      _db.ref('tambola_rooms/$roomId');
  DatabaseReference _gameRef(String roomId) =>
      _db.ref('tambola_games/$roomId');
  DatabaseReference _ticketRef(String roomId, String playerId) =>
      _db.ref('tambola_tickets/$roomId/$playerId');

  // ── Find or create room ───────────────────────────────────────────────────

  Future<String> findOrCreateRoom({
    required String playerId,
    required String playerName,
    required int maxPlayers,
  }) async {
    final snap = await _db
        .ref('tambola_rooms')
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
          GameSessionTracker.record('tambola', entry.key);
          return entry.key;
        }
      }
    }
    final newRoomId = await _createRoom(playerId, playerName, maxPlayers);
    GameSessionTracker.record('tambola', newRoomId);
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
    final roomId = _db.ref('tambola_rooms').push().key!;
    await _roomRef(roomId).set({
      'hostId': playerId,
      'maxPlayers': maxPlayers,
      'status': 'waiting',
      'players': {
        playerId: {'name': playerName},
      },
    });
    debugPrint('[Tambola] created room $roomId');
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
    debugPrint('[Tambola] filled $botsNeeded bots in $roomId');
  }

  // ── Start game ────────────────────────────────────────────────────────────

  Future<void> startGame(String roomId) => guarded('startGame', () async {
    final roomSnap = await _roomRef(roomId).get();
    if (!roomSnap.exists) return;
    final room = Map<String, dynamic>.from(roomSnap.value as Map);
    final players = Map<String, dynamic>.from(room['players'] as Map);
    final hostId = room['hostId'] as String;

    // Generate a ticket for every player
    final ticketOps = players.keys.map((pid) async {
      final ticket = TambolaTicket.generate(_rng);
      await _ticketRef(roomId, pid).set(ticket.toMap());
    });
    await Future.wait(ticketOps);

    // Shuffle all 90 numbers as the draw pool
    final pool = List.generate(90, (i) => i + 1)..shuffle(_rng);

    await _gameRef(roomId).set({
      'phase': 'playing',
      'calledNumbers': [],
      'remainingNumbers': pool,
      'prizeWinners': {},
      'hostId': hostId,
      'players': {
        for (final e in players.entries) e.key: {'name': e.value['name']},
      },
    });

    await _roomRef(roomId).update({'status': 'started'});
    debugPrint('[Tambola] game started in $roomId');
  });

  // ── Call next number (host only) ──────────────────────────────────────────

  Future<void> callNextNumber(String roomId) => guarded('callNextNumber', () async {
    final snap = await _gameRef(roomId).get();
    if (!snap.exists) return;
    final data = Map<String, dynamic>.from(snap.value as Map);
    if (data['phase'] != 'playing') return;

    final remaining = _fbList(data['remainingNumbers'])
        .map((n) => (n as num).toInt())
        .toList();
    if (remaining.isEmpty) {
      await _gameRef(roomId).update({'phase': 'gameOver'});
      return;
    }

    final number = remaining.removeLast();
    final called = _fbList(data['calledNumbers'])
        .map((n) => (n as num).toInt())
        .toList()
      ..add(number);

    await _gameRef(roomId).update({
      'calledNumbers': called,
      'remainingNumbers': remaining,
    });
    debugPrint('[Tambola] called $number ($roomId)');
  });

  // ── Pause / Resume ────────────────────────────────────────────────────────

  Future<void> pauseGame(String roomId) =>
      _gameRef(roomId).update({'phase': 'paused'});

  Future<void> resumeGame(String roomId) =>
      _gameRef(roomId).update({'phase': 'playing'});

  // ── Claim prize ───────────────────────────────────────────────────────────

  Future<String?> claimPrize({
    required String roomId,
    required String playerId,
    required TambolaPrize prize,
    required TambolaTicket ticket,
  }) async {
    // Validate eligibility before entering the transaction (cheap read, no write).
    final snap = await _gameRef(roomId).get();
    if (!snap.exists) return 'Game not found';
    final data = Map<String, dynamic>.from(snap.value as Map);
    if (data['phase'] != 'playing') return 'Game is not active';

    final called = _fbList(data['calledNumbers'])
        .map((n) => (n as num).toInt())
        .toList();

    final valid = switch (prize) {
      TambolaPrize.earlyFive => ticket.isEarlyFive(called),
      TambolaPrize.topLine => ticket.isRowComplete(0, called),
      TambolaPrize.middleLine => ticket.isRowComplete(1, called),
      TambolaPrize.bottomLine => ticket.isRowComplete(2, called),
      TambolaPrize.fullHouse => ticket.isFullHouse(called),
    };
    if (!valid) return 'Not valid — not all numbers have been called yet';

    // Atomic write: abort if another client already claimed this prize.
    String? error;
    await _gameRef(roomId).runTransaction((current) {
      if (current == null) {
        error = 'Game not found';
        return Transaction.abort();
      }
      final game = Map<String, dynamic>.from(current as Map);
      if (game['phase'] != 'playing') {
        error = 'Game is not active';
        return Transaction.abort();
      }
      final winners = game['prizeWinners'] != null
          ? Map<String, dynamic>.from(game['prizeWinners'] as Map)
          : <String, dynamic>{};
      if (winners.containsKey(prize.key)) {
        error = 'Prize already claimed';
        return Transaction.abort();
      }
      winners[prize.key] = playerId;
      game['prizeWinners'] = winners;
      if (prize == TambolaPrize.fullHouse) game['phase'] = 'gameOver';
      return Transaction.success(game);
    });

    if (error != null) return error;
    debugPrint('[Tambola] $playerId claimed ${prize.label} in $roomId');
    return null;
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

  Stream<TambolaGameState?> gameStream(String roomId) =>
      _gameRef(roomId).onValue.map((e) {
        if (!e.snapshot.exists) return null;
        try {
          return TambolaGameState.fromMap(
              roomId, Map<dynamic, dynamic>.from(e.snapshot.value as Map));
        } catch (err) {
          debugPrint('[Tambola] gameStream error: $err');
          ErrorLogService.instance.logAuto(game: 'tambola', error: 'gameStream: $err');
          return null;
        }
      });

  Future<Map<String, TambolaTicket>> readAllTickets(String roomId) async {
    final snap = await _db.ref('tambola_tickets/$roomId').get();
    if (!snap.exists) return {};
    final raw = Map<String, dynamic>.from(snap.value as Map);
    return {
      for (final e in raw.entries)
        e.key: TambolaTicket.fromMap(Map<dynamic, dynamic>.from(e.value as Map)),
    };
  }

  Stream<TambolaTicket?> ticketStream(String roomId, String playerId) =>
      _ticketRef(roomId, playerId).onValue.map((e) {
        if (!e.snapshot.exists) return null;
        try {
          return TambolaTicket.fromMap(
              Map<dynamic, dynamic>.from(e.snapshot.value as Map));
        } catch (err) {
          debugPrint('[Tambola] ticketStream error: $err');
          ErrorLogService.instance.logAuto(game: 'tambola', error: 'ticketStream: $err');
          return null;
        }
      });
}
