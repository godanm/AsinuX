import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/game_state.dart';
import '../models/player_model.dart';
import '../models/card_model.dart';
import '../models/chat_message.dart';
import '../utils/game_logic.dart';
import 'stats_service.dart';
import 'game_logger.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._();
  static FirebaseService get instance => _instance;
  FirebaseService._();

  final _db = FirebaseDatabase.instance;
  DatabaseReference _roomRef(String roomId) => _db.ref('rooms/$roomId');

  // ── Room Management ─────────────────────────────────────────

  Future<GameState> createRoom({
    required String playerId,
    required String playerName,
  }) async {
    final code = GameLogic.generateRoomCode();
    final roomId = _db.ref('rooms').push().key!;

    final host = Player(
      id: playerId,
      name: playerName,
      isHost: true,
    );

    final state = GameState(
      roomId: roomId,
      roomCode: code,
      players: {playerId: host},
      phase: GamePhase.waiting,
      hostId: playerId,
      playerOrder: [playerId],
    );

    await _roomRef(roomId).set(state.toMap());
    await _db.ref('roomCodes/$code').set(roomId);
    return state;
  }

  Future<GameState?> joinRoom({
    required String code,
    required String playerId,
    required String playerName,
  }) async {
    final codeSnap = await _db.ref('roomCodes/$code').get();
    if (!codeSnap.exists) return null;
    final roomId = codeSnap.value as String;
    final roomSnap = await _roomRef(roomId).get();
    if (!roomSnap.exists) return null;
    final state = GameState.fromMap(roomSnap.value as Map<dynamic, dynamic>);
    if (state.phase != GamePhase.waiting) return null;
    if (state.players.length >= 8) return null;

    final newPlayer = Player(id: playerId, name: playerName);
    await _roomRef(roomId).child('players/$playerId').set(newPlayer.toMap());
    await _roomRef(roomId)
        .child('playerOrder')
        .set([...state.playerOrder, playerId]);

    final snap = await _roomRef(roomId).get();
    return GameState.fromMap(snap.value as Map<dynamic, dynamic>);
  }

  Future<void> leaveRoom(String roomId, String playerId) async {
    // Mark player as disconnected first (future real-player support: others can
    // detect the disconnect and optionally replace with a bot).
    await _roomRef(roomId)
        .child('players/$playerId/disconnectedAt')
        .set(ServerValue.timestamp);

    final snap = await _roomRef(roomId).get();
    if (!snap.exists) return;
    final state = GameState.fromMap(snap.value as Map<dynamic, dynamic>);

    // Determine remaining human players (non-bot ids) after this player leaves.
    final remainingHumans = state.playerOrder
        .where((id) => id != playerId && !id.startsWith('bot_'))
        .toList();

    if (remainingHumans.isEmpty) {
      // No real players left — tear down the room entirely.
      await _roomRef(roomId).remove();
      if (state.roomCode.isNotEmpty) {
        await _db.ref('roomCodes/${state.roomCode}').remove();
      }
    } else {
      // Real players remain — remove only this player's node and fix host.
      await _roomRef(roomId).child('players/$playerId').remove();
      final newOrder =
          state.playerOrder.where((id) => id != playerId).toList();
      await _roomRef(roomId).child('playerOrder').set(newOrder);
      if (state.hostId == playerId) {
        // Hand host to the first remaining human so a real player drives the game.
        final newHost = remainingHumans.first;
        await _roomRef(roomId).child('hostId').set(newHost);
        await _roomRef(roomId).child('players/$newHost/isHost').set(true);
      }

      // Fix turn/leader state so the game doesn't stall after the player leaves.
      // Without this, currentTurn/currentLeader remain set to the removed player's
      // ID, bots see a null player and return early, and the game locks up.
      if (state.phase == GamePhase.playing || state.phase == GamePhase.trickEnd) {
        // Find the player who comes next after the leaving player in rotation.
        // Using rotation order (not just newOrder.first) keeps the "who leads next"
        // semantics correct — the player right after the leaver inherits their role.
        final afterLeaving = [
          ...state.playerOrder
              .skipWhile((id) => id != playerId)
              .skip(1),
          ...state.playerOrder
              .takeWhile((id) => id != playerId),
        ].where((id) => newOrder.contains(id)).toList();

        final nextValidPlayer = afterLeaving.firstWhere(
          (id) {
            final p = state.players[id];
            return p != null && !p.isEliminated && p.hand.isNotEmpty;
          },
          orElse: () => newOrder.firstWhere(
            (id) {
              final p = state.players[id];
              return p != null && !p.isEliminated && p.hand.isNotEmpty;
            },
            orElse: () => newOrder.isNotEmpty ? newOrder.first : '',
          ),
        );

        if (nextValidPlayer.isNotEmpty) {
          // Transfer leadership when the leaving player was the designated leader.
          if (state.currentLeader == playerId) {
            await _roomRef(roomId).child('currentLeader').set(nextValidPlayer);
            // For trickEnd, also fix currentTurn so startNextTrick picks correctly.
            if (state.phase == GamePhase.trickEnd) {
              await _roomRef(roomId).child('currentTurn').set(nextValidPlayer);
            }
          }

          // Advance currentTurn if it was the leaving player's turn to play.
          if (state.phase == GamePhase.playing && state.currentTurn == playerId) {
            final played = state.playedCards.keys.toSet();
            final stillNeedToPlay = afterLeaving.where((id) {
              if (played.contains(id)) return false;
              final p = state.players[id];
              return p != null && !p.isEliminated && p.hand.isNotEmpty;
            }).toList();

            if (stillNeedToPlay.isNotEmpty) {
              // Others still need to play — advance to the next in rotation.
              await _roomRef(roomId).child('currentTurn').set(stillNeedToPlay.first);
            } else if (state.currentSuit != null && state.playedCards.isNotEmpty) {
              // All remaining players have already played — resolve the trick now,
              // treating the leaving player as having forfeited their turn.
              final mergedPlayers = Map<String, Player>.from(state.players)
                ..remove(playerId);
              final mergedState = state.copyWith(
                playerOrder: newOrder,
                players: mergedPlayers,
              );
              await _resolveTrick(
                mergedState,
                Map<String, PlayingCard>.from(state.playedCards),
                List<String>.from(state.finishOrder),
                mergedPlayers,
                state.currentSuit!,
              );
            } else {
              // No cards played yet — transfer both leader and turn.
              await _roomRef(roomId).child('currentLeader').set(nextValidPlayer);
              await _roomRef(roomId).child('currentTurn').set(nextValidPlayer);
            }
          }
        }
      }
    }
  }

  // ── Game Start ───────────────────────────────────────────────

  Future<void> startGame(GameState state) async {
    await _dealAndStart(state, isNewGame: true);
  }

  Future<void> startNextRound(GameState state) async {
    await _dealAndStart(state, isNewGame: false);
  }

  Future<void> _dealAndStart(GameState state, {required bool isNewGame}) async {
    final activeIds = state.activePlayers.map((p) => p.id).toList();
    final dealt = GameLogic.dealCards(activeIds);

    final updatedPlayers = Map<String, Player>.from(state.players);
    for (final id in activeIds) {
      updatedPlayers[id] = updatedPlayers[id]!.copyWith(
        hand: dealt.players[id]!.hand,
        finishPosition: 0,
      );
    }

    // Ace of Spades holder leads first — can play ANY card (sets the suit)
    final firstLeader = dealt.aceOfSpadesHolder;

    await _roomRef(state.roomId).update({
      'phase': GamePhase.playing.index,
      'roundNumber': isNewGame ? 1 : state.roundNumber + 1,
      'trickNumber': 1,
      'drawPile': [],
      'currentSuit': null,
      'currentLeader': firstLeader,
      'currentTurn': firstLeader,
      'playedCards': {},
      'trickWinnerId': null,
      'donkeyId': null,
      'finishOrder': [],
      'tournamentWinnerId': null,
      'players': updatedPlayers.map((k, v) => MapEntry(k, v.toMap())),
    });
  }

  // ── Player Actions ───────────────────────────────────────────

  /// Play a card.
  /// - Leader's card sets the suit.
  /// - If a follower cuts, trick ends IMMEDIATELY.
  /// - Otherwise trick continues until all have played.
  Future<void> playCard({
    required GameState state,
    required String playerId,
    required int cardIndex,
  }) async {
    final player = state.players[playerId]!;
    if (cardIndex >= player.hand.length) return;

    final card = player.hand[cardIndex];
    final newHand = List<PlayingCard>.from(player.hand)..removeAt(cardIndex);

    final newPlayedCards = Map<String, PlayingCard>.from(state.playedCards);
    newPlayedCards[playerId] = card;

    final isLeader = state.currentSuit == null;
    final leadSuit = isLeader ? card.suit.index : state.currentSuit!;
    final isCut = !isLeader && card.suit.index != leadSuit;

    final updatedPlayers = Map<String, Player>.from(state.players);
    updatedPlayers[playerId] = player.copyWith(hand: newHand);

    // Log card played
    GameLogger.instance.cardPlayed(
      roomId: state.roomId,
      playerId: playerId,
      playerName: player.name,
      card: card,
      handBefore: player.hand,
      handAfter: newHand,
      isLeader: isLeader,
      isCut: isCut,
      leadSuit: isLeader ? null : state.currentSuit,
      trickNumber: state.trickNumber,
    );

    final newFinishOrder = List<String>.from(state.finishOrder);
    if (newHand.isEmpty) newFinishOrder.add(playerId);

    if (isCut) {
      // Write played card then immediately resolve — single logical flow
      await _roomRef(state.roomId).update({
        'players/$playerId/hand': newHand.map((c) => c.toMap()).toList(),
        'playedCards': newPlayedCards.map((k, v) => MapEntry(k, v.toMap())),
        'currentSuit': leadSuit,
        'currentTurn': null,
        if (newHand.isEmpty) 'finishOrder': newFinishOrder,
      });
      await _resolveTrick(state, newPlayedCards, newFinishOrder, updatedPlayers, leadSuit);
      return;
    }

    // Normal play — figure out who goes next BEFORE writing
    final trickParticipants = state.playerOrder.where((id) {
      final p = updatedPlayers[id];
      if (p == null || p.isEliminated) return false;
      return p.hand.isNotEmpty || newPlayedCards.containsKey(id);
    }).toList();

    final notYetPlayed = trickParticipants
        .where((id) => !newPlayedCards.containsKey(id))
        .toList();

    final orderAfterCurrent = [
      ...state.playerOrder.skipWhile((id) => id != playerId).skip(1),
      ...state.playerOrder.takeWhile((id) => id != playerId),
    ];
    final nextTurn = notYetPlayed.isEmpty
        ? ''
        : orderAfterCurrent.firstWhere(
            (id) => notYetPlayed.contains(id),
            orElse: () => '',
          );

    // Single write with correct nextTurn already computed
    await _roomRef(state.roomId).update({
      'players/$playerId/hand': newHand.map((c) => c.toMap()).toList(),
      'playedCards': newPlayedCards.map((k, v) => MapEntry(k, v.toMap())),
      'currentSuit': leadSuit,
      'currentTurn': nextTurn.isEmpty ? null : nextTurn,
      if (newHand.isEmpty) 'finishOrder': newFinishOrder,
    });

    if (notYetPlayed.isEmpty) {
      await _resolveTrick(state, newPlayedCards, newFinishOrder, updatedPlayers, leadSuit);
    }
  }

  Future<void> _resolveTrick(
    GameState state,
    Map<String, PlayingCard> playedCards,
    List<String> finishOrder,
    Map<String, Player> updatedPlayers,
    int leadSuit,
  ) async {
    final result = GameLogic.resolveTrick(
      playedCards,
      leadSuit,
      state.playerOrder,
    );

    // Targeted player updates — avoids overwriting stale hand data for uninvolved players.
    // We only write fields that actually changed rather than the full players map.
    final Map<String, dynamic> playerFieldUpdates = {};

    List<PlayingCard>? pickupHand;
    if (result.hasCut && result.pickupId != null) {
      final pickupId = result.pickupId!;
      final allTableCards = playedCards.values.toList();

      // Fetch the pickup player's CURRENT hand from Firebase to avoid using
      // a stale local snapshot — this is the root cause of the "same card" replay bug.
      final freshSnap = await _roomRef(state.roomId)
          .child('players/$pickupId/hand')
          .get();
      final freshHand = freshSnap.exists
          ? (freshSnap.value as List<dynamic>)
              .map((c) => PlayingCard.fromMap(c as Map<dynamic, dynamic>))
              .toList()
          : (updatedPlayers[pickupId]?.hand ?? <PlayingCard>[]);

      pickupHand = [...freshHand, ...allTableCards];
      playerFieldUpdates['players/$pickupId/hand'] =
          pickupHand.map((c) => c.toMap()).toList();

      // Update in-memory so playersWithCards count is accurate
      updatedPlayers[pickupId] =
          updatedPlayers[pickupId]!.copyWith(hand: pickupHand);

      // Pickup player cannot be "finished" this trick
      finishOrder.remove(pickupId);

      // Log cut
      final cutterId = playedCards.entries
          .firstWhere((e) => e.value.suit.index != leadSuit,
              orElse: () => playedCards.entries.first)
          .key;
      GameLogger.instance.cutDetected(
        roomId: state.roomId,
        cutterId: cutterId,
        cutterName: state.players[cutterId]?.name ?? cutterId,
        pickupId: pickupId,
        pickupName: state.players[pickupId]?.name ?? pickupId,
        tableCards: allTableCards,
        pickupHandBefore: freshHand,
        pickupHandAfter: pickupHand,
        trickNumber: state.trickNumber,
      );
    }

    // How many active players still have cards?
    // Read both hands and finishOrder fresh from Firebase so we never use a
    // stale bot snapshot that predates a concurrent human escape write.
    final freshRoomSnap =
        await _roomRef(state.roomId).get();
    final freshPlayerMap = <String, Player>{};
    List<String> freshFinishOrder = List<String>.from(finishOrder);
    if (freshRoomSnap.exists) {
      final roomData = freshRoomSnap.value as Map<dynamic, dynamic>;
      final playersRaw = roomData['players'] as Map<dynamic, dynamic>? ?? {};
      playersRaw.forEach((k, v) {
        final id = k.toString();
        freshPlayerMap[id] =
            Player.fromMap(id, v as Map<dynamic, dynamic>);
      });
      // Firebase's finishOrder is authoritative for ordering — it was written
      // when each player's hand became empty, so it reflects the true sequence.
      // Start from Firebase's version and append anything only known in-memory
      // (the current trick's escapees not yet flushed to Firebase).
      final fbFinishOrder = (roomData['finishOrder'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      freshFinishOrder = fbFinishOrder;
      for (final id in finishOrder) {
        if (!freshFinishOrder.contains(id)) freshFinishOrder.add(id);
      }
    }
    // Overlay our in-memory changes (pickup hand) on top of fresh data
    for (final entry in playerFieldUpdates.entries) {
      // e.g. 'players/botId/hand' — extract the player id
      final parts = entry.key.split('/');
      if (parts.length == 3 && parts[2] == 'hand') {
        final pid = parts[1];
        if (freshPlayerMap.containsKey(pid)) {
          freshPlayerMap[pid] = freshPlayerMap[pid]!
              .copyWith(hand: updatedPlayers[pid]?.hand ?? []);
        }
      }
    }
    // If a pickup happened this trick, ensure the pickup player isn't in
    // finishOrder — they received cards back, so they haven't actually escaped.
    if (result.hasCut && result.pickupId != null) {
      freshFinishOrder.remove(result.pickupId);
    }
    // Use the merged finishOrder from now on
    finishOrder = freshFinishOrder;

    final playersWithCards = state.activePlayers
        .where((p) {
          final fp = freshPlayerMap[p.id];
          return fp != null && !fp.isEliminated && fp.hand.isNotEmpty;
        })
        .toList();

    if (playersWithCards.length <= 1) {
      // Round over — identify the donkey
      final donkeyId = playersWithCards.isNotEmpty
          ? playersWithCards.first.id
          : (state.activePlayers
                  .where((p) => !finishOrder.contains(p.id))
                  .firstOrNull
                  ?.id ??
              state.activePlayers.last.id);

      // Apply result using fresh data
      final mergedPlayers = Map<String, Player>.from(freshPlayerMap)
        ..addAll(updatedPlayers.map((k, v) =>
            MapEntry(k, freshPlayerMap[k]?.copyWith(hand: v.hand) ?? v)));

      final roundResult = GameLogic.applyRoundResult(
        players: mergedPlayers,
        donkeyId: donkeyId,
        finishOrder: finishOrder,
      );

      // Only write the fields that changed
      playerFieldUpdates['players/$donkeyId/isEliminated'] = true;
      if (finishOrder.isNotEmpty) {
        final firstEscapeId = finishOrder.first;
        final newScore = (freshPlayerMap[firstEscapeId]?.score ?? 0) + 1;
        playerFieldUpdates['players/$firstEscapeId/score'] = newScore;
      }

      await _roomRef(state.roomId).update({
        'phase': roundResult.tournamentWinnerId != null
            ? GamePhase.gameOver.index
            : GamePhase.trickEnd.index,
        'donkeyId': donkeyId,
        'finishOrder': finishOrder,
        'tournamentWinnerId': roundResult.tournamentWinnerId,
        'playedCards': playedCards.map((k, v) => MapEntry(k, v.toMap())),
        ...playerFieldUpdates,
      });

      GameLogger.instance.roundEnd(
        roomId: state.roomId,
        donkeyId: donkeyId,
        donkeyName: state.players[donkeyId]?.name ?? donkeyId,
        finishOrder: finishOrder,
        trickNumber: state.trickNumber,
      );

      // Guard: recover any escaped players dropped from finishOrder due to
      // race conditions in concurrent finishOrder writes (each player
      // overwrites the whole array from their local state snapshot, so a
      // fast bot write can clobber an earlier human escape entry).
      // Every active player who isn't the donkey must have escaped.
      for (final p in state.activePlayers) {
        if (p.id != donkeyId && !finishOrder.contains(p.id)) {
          debugPrint('[FirebaseService] recovering missing escapee ${p.name} (${p.id}) in finishOrder');
          finishOrder.add(p.id);
        }
      }

      debugPrint('[FirebaseService] round ended — donkey=$donkeyId '
          'winner=${roundResult.tournamentWinnerId} finishOrder=$finishOrder '
          'allPlayers=${state.playerOrder}');
      StatsService.instance.recordRound(
        allPlayerIds: state.playerOrder,
        escapedIds: finishOrder,
        donkeyId: donkeyId,
        winnerId: roundResult.tournamentWinnerId,
        isBot: false,
        playerNames: {
          for (final p in state.allPlayers) p.id: p.name,
        },
      ).catchError((e, st) {
        debugPrint('[FirebaseService] recordRound FAILED: $e\n$st');
      });
    } else {
      // Next trick — determine who leads
      String nextLeaderId;
      if (result.hasCut) {
        nextLeaderId = result.pickupId!;
      } else {
        final winnerId = result.winnerId;
        final winnerHasCards =
            (freshPlayerMap[winnerId]?.hand.isNotEmpty ?? false);
        if (winnerId != null && winnerHasCards) {
          nextLeaderId = winnerId;
        } else {
          final orderAfterWinner = [
            ...state.playerOrder
                .skipWhile((id) => id != (winnerId ?? state.playerOrder.first))
                .skip(1),
            ...state.playerOrder
                .takeWhile((id) => id != (winnerId ?? state.playerOrder.first)),
          ];
          nextLeaderId = orderAfterWinner.firstWhere(
            (id) => freshPlayerMap[id]?.hand.isNotEmpty ?? false,
            orElse: () => playersWithCards.first.id,
          );
        }
      }

      if (result.winnerId != null) {
        GameLogger.instance.trickWon(
          roomId: state.roomId,
          winnerId: result.winnerId!,
          winnerName: state.players[result.winnerId!]?.name ?? result.winnerId!,
          trickNumber: state.trickNumber,
        );
      }

      await _roomRef(state.roomId).update({
        'phase': GamePhase.trickEnd.index,
        'trickWinnerId': result.winnerId,
        'currentLeader': nextLeaderId,
        'currentTurn': nextLeaderId,
        'playedCards': playedCards.map((k, v) => MapEntry(k, v.toMap())),
        'trickNumber': state.trickNumber + 1,
        'finishOrder': finishOrder,
        'currentSuit': leadSuit,
        ...playerFieldUpdates,
      });
    }
  }

  /// Host starts the next trick after trickEnd pause.
  Future<void> startNextTrick(GameState state) async {
    final leader = state.currentLeader ?? state.playerOrder.first;
    await _roomRef(state.roomId).update({
      'phase': GamePhase.playing.index,
      'playedCards': {},
      'trickWinnerId': null,
      'currentSuit': null, // explicitly clear so leader sets it fresh
      'currentTurn': leader,
    });
  }

  // ── Matchmaking ──────────────────────────────────────────────

  Future<void> joinQueue({required String uid, required String name}) async {
    await _db.ref('matchmaking/queue/$uid').set({
      'uid': uid,
      'name': name,
      'joinedAt': ServerValue.timestamp,
      'roomId': null,
    });
  }

  Future<void> leaveQueue(String uid) async {
    await _db.ref('matchmaking/queue/$uid').remove();
  }

  Future<void> setQueueRoomId(String uid, String roomId) async {
    await _db.ref('matchmaking/queue/$uid/roomId').set(roomId);
  }

  /// Returns true if this client successfully claimed the matchmaking lead.
  Future<bool> claimMatchmakingLead(String uid) async {
    final ref = _db.ref('matchmaking/creating');
    final result = await ref.runTransaction((Object? current) {
      if (current != null) return Transaction.abort();
      return Transaction.success(uid);
    });
    return result.committed;
  }

  Future<void> releaseMatchmakingLead() async {
    await _db.ref('matchmaking/creating').remove();
  }

  Stream<List<Map<String, dynamic>>> queueStream() {
    return _db.ref('matchmaking/queue').onValue.map((event) {
      if (!event.snapshot.exists) return [];
      final raw = event.snapshot.value as Map<dynamic, dynamic>;
      return raw.entries.map((e) {
        final v = Map<String, dynamic>.from(e.value as Map);
        v['uid'] = e.key.toString();
        return v;
      }).toList();
    });
  }

  Stream<String?> myQueueEntryStream(String uid) {
    return _db.ref('matchmaking/queue/$uid/roomId').onValue.map((event) {
      if (!event.snapshot.exists) return null;
      final val = event.snapshot.value;
      if (val == null) return null;
      return val.toString();
    });
  }

  Future<List<Map<String, dynamic>>> getQueueSnapshot() async {
    final snap = await _db.ref('matchmaking/queue').get();
    if (!snap.exists) return [];
    final raw = snap.value as Map<dynamic, dynamic>;
    return raw.entries.map((e) {
      final v = Map<String, dynamic>.from(e.value as Map);
      v['uid'] = e.key.toString();
      return v;
    }).toList();
  }

  Future<GameState?> getFreshState(String roomId) async {
    final snap = await _roomRef(roomId).get();
    if (!snap.exists) return null;
    return GameState.fromMap(snap.value as Map<dynamic, dynamic>);
  }

  Future<GameState> createMatchmadeRoom({
    required List<({String uid, String name})> players,
  }) async {
    final code = GameLogic.generateRoomCode();
    final roomId = _db.ref('rooms').push().key!;

    final playerMap = <String, Player>{};
    final orderList = <String>[];

    for (int i = 0; i < players.length; i++) {
      final p = players[i];
      playerMap[p.uid] = Player(id: p.uid, name: p.name, isHost: i == 0);
      orderList.add(p.uid);
    }

    final state = GameState(
      roomId: roomId,
      roomCode: code,
      players: playerMap,
      phase: GamePhase.waiting,
      hostId: players[0].uid,
      playerOrder: orderList,
    );

    await _roomRef(roomId).set(state.toMap());
    await _db.ref('roomCodes/$code').set(roomId);
    return state;
  }

  // ── Streams ──────────────────────────────────────────────────

  Stream<GameState?> roomStream(String roomId) {
    return _roomRef(roomId).onValue.map((event) {
      if (!event.snapshot.exists) return null;
      return GameState.fromMap(
          event.snapshot.value as Map<dynamic, dynamic>);
    });
  }

  // ── Chat ─────────────────────────────────────────────────────
  // Pre-populated quick-chat messages stored under rooms/{roomId}/chat.
  // Each entry: { senderId, senderName, message, timestamp }

  Future<void> sendChatMessage({
    required String roomId,
    required String senderId,
    required String senderName,
    required String message,
  }) async {
    await _roomRef(roomId).child('chat').push().set({
      'senderId': senderId,
      'senderName': senderName,
      'message': message,
      'timestamp': ServerValue.timestamp,
    });
  }

  Stream<List<ChatMessage>> chatStream(String roomId) {
    return _roomRef(roomId).child('chat').orderByChild('timestamp').onValue.map((event) {
      if (!event.snapshot.exists) return [];
      final map = event.snapshot.value as Map<dynamic, dynamic>;
      final messages = map.entries.map((e) {
        final data = e.value as Map<dynamic, dynamic>;
        return ChatMessage(
          id: e.key as String,
          senderId: data['senderId'] as String? ?? '',
          senderName: data['senderName'] as String? ?? '',
          message: data['message'] as String? ?? '',
          timestamp: data['timestamp'] as int? ?? 0,
        );
      }).toList();
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      // Keep only the last 50 messages in memory
      if (messages.length > 50) return messages.sublist(messages.length - 50);
      return messages;
    });
  }
}
