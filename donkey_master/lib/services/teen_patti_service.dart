import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/card_model.dart';
import '../models/teen_patti_state.dart';
import 'game_logger.dart';

class TeenPattiService {
  static final TeenPattiService _i = TeenPattiService._();
  static TeenPattiService get instance => _i;
  TeenPattiService._();

  final _db = FirebaseDatabase.instance;

  DatabaseReference _ref(String roomId) =>
      _db.ref('teen_patti_rooms/$roomId');
  DatabaseReference _secretsRef(String roomId) =>
      _db.ref('teen_patti_secrets/$roomId');
  DatabaseReference _balanceRef(String uid) =>
      _db.ref('stats/$uid/totalPoints');

  // ── Streams ──────────────────────────────────────────────────────────────────

  Stream<TeenPattiState?> roomStream(String roomId) =>
      _ref(roomId).onValue.map((e) {
        if (!e.snapshot.exists) return null;
        return TeenPattiState.fromMap(
            e.snapshot.value as Map<dynamic, dynamic>);
      });

  /// Streams the local player's own cards from the secrets path.
  Stream<List<PlayingCard>> cardsStream(String roomId, String playerId) =>
      _secretsRef(roomId).child(playerId).onValue.map((e) {
        if (!e.snapshot.exists) return <PlayingCard>[];
        return _parseCards(e.snapshot.value as Map<dynamic, dynamic>);
      });

  Future<List<PlayingCard>> getCards(String roomId, String playerId) async {
    final snap = await _secretsRef(roomId).child(playerId).get();
    if (!snap.exists) return [];
    return _parseCards(snap.value as Map<dynamic, dynamic>);
  }

  Future<TeenPattiState?> getFreshState(String roomId) async {
    final snap = await _ref(roomId).get();
    if (!snap.exists) return null;
    return TeenPattiState.fromMap(snap.value as Map<dynamic, dynamic>);
  }

  // ── Room lifecycle ────────────────────────────────────────────────────────────

  Future<TeenPattiState> createRoom({
    required String playerId,
    required String playerName,
    int bootAmount = 10,
    int potLimit = 1000,
  }) async {
    final code = _generateCode();
    final roomId = _db.ref('teen_patti_rooms').push().key!;
    final host = TeenPattiPlayer(
      id: playerId,
      name: playerName,
      isHost: true,
      seatIndex: 0,
    );
    final state = TeenPattiState(
      roomId: roomId,
      roomCode: code,
      hostId: playerId,
      players: {playerId: host},
      playerOrder: [playerId],
      bootAmount: bootAmount,
      currentStake: bootAmount,
      potLimit: potLimit,
    );
    await _ref(roomId).set(state.toMap());
    await _db.ref('teen_patti_codes/$code').set(roomId);
    return state;
  }

  Future<TeenPattiState?> joinRoom({
    required String code,
    required String playerId,
    required String playerName,
  }) async {
    final codeSnap =
        await _db.ref('teen_patti_codes/${code.toUpperCase()}').get();
    if (!codeSnap.exists) return null;
    final roomId = codeSnap.value as String;
    final snap = await _ref(roomId).get();
    if (!snap.exists) return null;
    final state =
        TeenPattiState.fromMap(snap.value as Map<dynamic, dynamic>);
    if (state.players.length >= 6) return null;
    if (state.phase != TeenPattiPhase.waiting) return null;

    final player = TeenPattiPlayer(
      id: playerId,
      name: playerName,
      seatIndex: state.players.length,
    );
    await _ref(roomId).update({
      'players/$playerId': player.toMap(),
      'playerOrder': [...state.playerOrder, playerId],
    });
    return state;
  }

  Future<void> addBots(TeenPattiState state, int count) async {
    final rng = Random();
    final existing = state.players.length;
    final updates = <String, dynamic>{};
    final newOrder = List<String>.from(state.playerOrder);
    for (int i = 0; i < count; i++) {
      final seatIdx = existing + i;
      final botId = 'bot_${state.roomId}_$seatIdx';
      final bot = TeenPattiPlayer(
        id: botId,
        name: _botNames[rng.nextInt(_botNames.length)],
        isBot: true,
        seatIndex: seatIdx,
      );
      updates['players/$botId'] = bot.toMap();
      newOrder.add(botId);
    }
    updates['playerOrder'] = newOrder;
    await _ref(state.roomId).update(updates);
  }

  Future<void> leaveRoom(String roomId, String playerId) async {
    final snap = await _ref(roomId).get();
    if (!snap.exists) return;
    final state =
        TeenPattiState.fromMap(snap.value as Map<dynamic, dynamic>);
    final humans = state.playerOrder
        .where((id) => id != playerId && !id.startsWith('bot_'))
        .toList();
    if (humans.isEmpty) {
      await _ref(roomId).remove();
      if (state.roomCode.isNotEmpty) {
        await _db.ref('teen_patti_codes/${state.roomCode}').remove();
      }
    } else {
      await _ref(roomId).child('players/$playerId').remove();
      final newOrder =
          state.playerOrder.where((id) => id != playerId).toList();
      await _ref(roomId).child('playerOrder').set(newOrder);
    }
  }

  // ── Game start ────────────────────────────────────────────────────────────────

  Future<void> startGame(TeenPattiState state) async {
    debugPrint('[TeenPattiService] startGame — roomId=${state.roomId} round=${state.roundNumber + 1} players=${state.playerOrder}');
    final deck = _buildFullDeck()..shuffle(Random());
    final order = List<String>.from(state.playerOrder);

    // Clear old secrets and deal 3 cards each
    debugPrint('[TeenPattiService] removing old secrets');
    await _secretsRef(state.roomId).remove();
    for (int i = 0; i < order.length; i++) {
      debugPrint('[TeenPattiService] dealing cards to ${order[i]}');
      await _secretsRef(state.roomId).child(order[i]).set({
        'cards': deck.sublist(i * 3, i * 3 + 3).map((c) => c.toMap()).toList(),
      });
    }

    // Reset all players to blind + collect boot
    final playerUpdates = <String, dynamic>{};
    for (final id in order) {
      playerUpdates['players/$id'] = state.players[id]!.copyWith(
        status: PlayerStatus.blind,
        roundBet: state.bootAmount,
      ).toMap();
      if (!id.startsWith('bot_')) {
        debugPrint('[TeenPattiService] deducting boot ${state.bootAmount} from $id');
        await _balanceRef(id).set(ServerValue.increment(-state.bootAmount));
      }
    }

    final firstTurn = order[(state.dealerIndex + 1) % order.length];
    debugPrint('[TeenPattiService] firstTurn=$firstTurn pot=${state.bootAmount * order.length}');

    await _ref(state.roomId).update({
      ...playerUpdates,
      'phase': TeenPattiPhase.betting.index,
      'pot': state.bootAmount * order.length,
      'currentStake': state.bootAmount,
      'currentTurn': firstTurn,
      'lastActorId': null,
      'roundNumber': state.roundNumber + 1,
      'winners': [],
      'sideshowRequesterId': null,
      'sideshowTargetId': null,
      'turnStartedAt': ServerValue.timestamp,
    });
    debugPrint('[TeenPattiService] startGame complete — phase=betting');

    await GameLogger.instance.tpGameStart(
      roomId: state.roomId,
      roundNumber: state.roundNumber + 1,
      playerNames: {for (final id in order) id: state.players[id]?.name ?? id},
      bootAmount: state.bootAmount,
      firstTurn: firstTurn,
    );
  }

  // ── Player actions ────────────────────────────────────────────────────────────

  /// Mark the player as Seen. Cards are already available client-side via [cardsStream].
  Future<void> seeCards(TeenPattiState state, String playerId) async {
    if (state.players[playerId]?.isSeen ?? false) return;
    debugPrint('[TeenPattiService] seeCards — playerId=$playerId');
    await _ref(state.roomId)
        .child('players/$playerId/status')
        .set(PlayerStatus.seen.index);
    final cards = await getCards(state.roomId, playerId);
    final label = cards.isNotEmpty ? evaluateHand(cards).label : 'unknown';
    debugPrint('[TeenPattiService] seeCards — hand=$label');
    await GameLogger.instance.tpSeeCards(
      roomId: state.roomId,
      playerId: playerId,
      playerName: state.players[playerId]?.name ?? playerId,
      handLabel: label,
    );
  }

  Future<void> fold(TeenPattiState state, String playerId, {bool timeout = false}) async {
    final player = state.players[playerId];
    debugPrint('[TeenPattiService] fold — player=${player?.name} ($playerId) timeout=$timeout pot=${state.pot}');
    await GameLogger.instance.tpFold(
      roomId: state.roomId,
      playerId: playerId,
      playerName: player?.name ?? playerId,
      pot: state.pot,
      timeout: timeout,
    );

    final remaining =
        state.activePlayers.where((id) => id != playerId).toList();
    final updates = <String, dynamic>{
      'players/$playerId/status': PlayerStatus.folded.index,
    };

    if (remaining.length == 1) {
      debugPrint('[TeenPattiService] fold — last player standing: ${remaining.first}');
      updates['phase'] = TeenPattiPhase.payout.index;
      updates['winners'] = [remaining.first];
      updates['currentTurn'] = null;
      await _ref(state.roomId).update(updates);
      await _settlePot(state.roomId, state.pot, remaining);
    } else {
      final next = _nextActive(state, playerId, skip: {playerId});
      debugPrint('[TeenPattiService] fold — next turn: $next');
      updates['currentTurn'] = next;
      updates['turnStartedAt'] = ServerValue.timestamp;
      await _ref(state.roomId).update(updates);
    }
  }

  /// Stay in at minimum cost: Blind pays 1× stake, Seen pays 2× stake.
  Future<void> chaal(TeenPattiState state, String playerId) async {
    final player = state.players[playerId]!;
    final bet = player.isBlind ? state.currentStake : state.currentStake * 2;
    debugPrint('[TeenPattiService] chaal — player=${player.name} bet=$bet pot=${state.pot} stake=${state.currentStake}');
    await GameLogger.instance.tpBet(
      roomId: state.roomId,
      playerId: playerId,
      playerName: player.name,
      action: 'CHAAL',
      bet: bet,
      newStake: state.currentStake,
      potBefore: state.pot,
      potAfter: state.pot + bet,
      wasBlind: player.isBlind,
    );
    await _placeBet(state, playerId, bet, newStake: null);
  }

  /// Raise: Blind bets 2× stake (new stake = bet), Seen bets 4× stake (new stake = bet ÷ 2).
  Future<void> raise(TeenPattiState state, String playerId) async {
    final player = state.players[playerId]!;
    final bet =
        player.isBlind ? state.currentStake * 2 : state.currentStake * 4;
    final newStake = player.isBlind ? bet : bet ~/ 2;
    debugPrint('[TeenPattiService] raise — player=${player.name} bet=$bet newStake=$newStake pot=${state.pot}');
    await GameLogger.instance.tpBet(
      roomId: state.roomId,
      playerId: playerId,
      playerName: player.name,
      action: 'RAISE',
      bet: bet,
      newStake: newStake,
      potBefore: state.pot,
      potAfter: state.pot + bet,
      wasBlind: player.isBlind,
    );
    await _placeBet(state, playerId, bet, newStake: newStake);
  }

  Future<void> _placeBet(
    TeenPattiState state,
    String playerId,
    int bet, {
    required int? newStake,
  }) async {
    final newPot = state.pot + bet;
    final updates = <String, dynamic>{
      'pot': newPot,
      'players/$playerId/roundBet':
          (state.players[playerId]?.roundBet ?? 0) + bet,
      'lastActorId': playerId,
    };
    if (newStake != null) updates['currentStake'] = newStake;

    if (!playerId.startsWith('bot_')) {
      await _balanceRef(playerId).set(ServerValue.increment(-bet));
    }

    // Pot limit hit → force show
    if (newPot >= state.potLimit) {
      updates['phase'] = TeenPattiPhase.showdown.index;
      updates['currentTurn'] = null;
      await _ref(state.roomId).update(updates);
      await _resolveForceShow(state, newPot);
      return;
    }

    final next = _nextActive(state, playerId);
    updates['currentTurn'] = next;
    updates['turnStartedAt'] = ServerValue.timestamp;
    await _ref(state.roomId).update(updates);
  }

  // ── Sideshow ──────────────────────────────────────────────────────────────────

  Future<void> requestSideshow(TeenPattiState state, String requesterId) async {
    final targetId = state.lastActorId;
    if (targetId == null) return;
    final requesterName = state.players[requesterId]?.name ?? requesterId;
    final targetName = state.players[targetId]?.name ?? targetId;
    debugPrint('[TeenPattiService] requestSideshow — requester=$requesterName → target=$targetName');
    await GameLogger.instance.tpSideshowRequest(
      roomId: state.roomId,
      requesterId: requesterId,
      requesterName: requesterName,
      targetId: targetId,
      targetName: targetName,
    );
    await _ref(state.roomId).update({
      'phase': TeenPattiPhase.sideshowPending.index,
      'sideshowRequesterId': requesterId,
      'sideshowTargetId': targetId,
    });
  }

  Future<void> respondSideshow(
    TeenPattiState state,
    String responderId,
    bool accepted,
  ) async {
    final requesterId = state.sideshowRequesterId!;
    final updates = <String, dynamic>{
      'sideshowRequesterId': null,
      'sideshowTargetId': null,
      'phase': TeenPattiPhase.betting.index,
    };

    if (!accepted) {
      debugPrint('[TeenPattiService] sideshow rejected — continuing, next after requester');
      await GameLogger.instance.tpSideshowResult(
        roomId: state.roomId,
        requesterId: requesterId,
        requesterName: state.players[requesterId]?.name ?? requesterId,
        responderId: responderId,
        responderName: state.players[responderId]?.name ?? responderId,
        accepted: false,
      );
      final next = _nextActive(state, requesterId);
      updates['currentTurn'] = next;
      updates['lastActorId'] = requesterId;
      updates['turnStartedAt'] = ServerValue.timestamp;
      await _ref(state.roomId).update(updates);
      return;
    }

    // Accepted — compare hands privately
    final rCards = await getCards(state.roomId, requesterId);
    final tCards = await getCards(state.roomId, responderId);

    String loser;
    String? rLabel, tLabel;
    if (rCards.isEmpty || tCards.isEmpty) {
      loser = requesterId; // safety fallback
    } else {
      rLabel = evaluateHand(rCards).label;
      tLabel = evaluateHand(tCards).label;
      final cmp = evaluateHand(rCards).compareTo(evaluateHand(tCards));
      loser = cmp > 0 ? responderId : requesterId;
    }
    final loserName = state.players[loser]?.name ?? loser;
    debugPrint('[TeenPattiService] sideshow accepted — requester=$rLabel responder=$tLabel loser=$loserName');
    await GameLogger.instance.tpSideshowResult(
      roomId: state.roomId,
      requesterId: requesterId,
      requesterName: state.players[requesterId]?.name ?? requesterId,
      responderId: responderId,
      responderName: state.players[responderId]?.name ?? responderId,
      accepted: true,
      loserName: loserName,
      requesterHand: rLabel,
      responderHand: tLabel,
    );

    updates['players/$loser/status'] = PlayerStatus.folded.index;

    final remaining =
        state.activePlayers.where((id) => id != loser).toList();

    if (remaining.length == 1) {
      updates['phase'] = TeenPattiPhase.payout.index;
      updates['winners'] = [remaining.first];
      updates['currentTurn'] = null;
      await _ref(state.roomId).update(updates);
      await _settlePot(state.roomId, state.pot, remaining);
    } else {
      final next = _nextActive(state, requesterId, skip: {loser});
      updates['currentTurn'] = next;
      updates['lastActorId'] = requesterId;
      updates['turnStartedAt'] = ServerValue.timestamp;
      await _ref(state.roomId).update(updates);
    }
  }

  // ── Show ──────────────────────────────────────────────────────────────────────

  /// One of the final 2 players calls for a Show.
  Future<void> callShow(TeenPattiState state, String callerId) async {
    final active = state.activePlayers;
    if (active.length != 2) return;

    final otherId = active.firstWhere((id) => id != callerId);
    final caller = state.players[callerId]!;
    final other = state.players[otherId]!;

    // Show cost: both seen = 2× stake (video rule); one or both blind = 1× stake
    final showCost = (caller.isSeen && other.isSeen)
        ? state.currentStake * 2
        : state.currentStake;

    if (!callerId.startsWith('bot_')) {
      await _balanceRef(callerId).set(ServerValue.increment(-showCost));
    }

    final newPot = state.pot + showCost;
    await _ref(state.roomId).update({
      'phase': TeenPattiPhase.showdown.index,
      'pot': newPot,
      'players/$callerId/roundBet': caller.roundBet + showCost,
    });

    // Resolve winner
    final cCards = await getCards(state.roomId, callerId);
    final oCards = await getCards(state.roomId, otherId);

    final cLabel = cCards.isNotEmpty ? evaluateHand(cCards).label : null;
    final oLabel = oCards.isNotEmpty ? evaluateHand(oCards).label : null;

    List<String> winners;
    if (cCards.isEmpty || oCards.isEmpty) {
      winners = [otherId];
    } else {
      final cmp = evaluateHand(cCards).compareTo(evaluateHand(oCards));
      if (cmp > 0) {
        winners = [callerId];
      } else if (cmp < 0) {
        winners = [otherId];
      } else {
        winners = [otherId];
      }
    }
    debugPrint('[TeenPattiService] show — caller=$cLabel other=$oLabel winners=$winners pot=$newPot');
    await GameLogger.instance.tpShow(
      roomId: state.roomId,
      callerId: callerId,
      callerName: caller.name,
      otherId: otherId,
      otherName: other.name,
      callerHand: cLabel,
      otherHand: oLabel,
      winners: winners,
      pot: newPot,
      showCost: showCost,
    );

    await _ref(state.roomId).update({
      'phase': TeenPattiPhase.payout.index,
      'winners': winners,
    });
    await _settlePot(state.roomId, newPot, winners);
  }

  // ── Auto-fold on timeout (called by bot service) ──────────────────────────────

  Future<void> timeoutFold(TeenPattiState state) async {
    final currentId = state.currentTurn;
    if (currentId == null) return;
    final name = state.players[currentId]?.name ?? currentId;
    debugPrint('[TeenPattiService] timeout fold for $name ($currentId)');
    await GameLogger.instance.tpAutoFold(
      roomId: state.roomId,
      playerId: currentId,
      playerName: name,
    );
    await fold(state, currentId, timeout: true);
  }

  // ── Next round ────────────────────────────────────────────────────────────────

  Future<void> startNextRound(TeenPattiState state) async {
    final newDealer =
        (state.dealerIndex + 1) % state.playerOrder.length;
    final playerUpdates = <String, dynamic>{};
    for (final id in state.playerOrder) {
      playerUpdates['players/$id'] = state.players[id]!
          .copyWith(status: PlayerStatus.blind, roundBet: 0)
          .toMap();
    }
    await _ref(state.roomId).update({
      ...playerUpdates,
      'phase': TeenPattiPhase.waiting.index,
      'pot': 0,
      'currentStake': state.bootAmount,
      'currentTurn': null,
      'lastActorId': null,
      'dealerIndex': newDealer,
      'sideshowRequesterId': null,
      'sideshowTargetId': null,
      'winners': [],
    });
    await _secretsRef(state.roomId).remove();
  }

  // ── Internal helpers ──────────────────────────────────────────────────────────

  Future<void> _resolveForceShow(TeenPattiState state, int pot) async {
    final active = state.activePlayers;
    if (active.isEmpty) return;
    debugPrint('[TeenPattiService] forceShow — active=${active.length} players pot=$pot');

    final results = <String, HandResult>{};
    for (final id in active) {
      final cards = await getCards(state.roomId, id);
      if (cards.isNotEmpty) results[id] = evaluateHand(cards);
    }

    HandResult? best;
    for (final res in results.values) {
      if (best == null || res.compareTo(best) > 0) best = res;
    }
    final bestResult = best;
    if (bestResult == null) return;

    final winners = results.entries
        .where((e) => e.value.compareTo(bestResult) == 0)
        .map((e) => e.key)
        .toList();

    final handLabels = {
      for (final e in results.entries)
        (state.players[e.key]?.name ?? e.key): e.value.label,
    };
    debugPrint('[TeenPattiService] forceShow — hands=$handLabels winners=$winners');
    await GameLogger.instance.tpForceShow(
      roomId: state.roomId,
      hands: handLabels,
      winners: winners,
      pot: pot,
    );

    await _ref(state.roomId).update({
      'phase': TeenPattiPhase.payout.index,
      'winners': winners,
    });
    await _settlePot(state.roomId, pot, winners);
  }

  Future<void> _settlePot(
    String roomId,
    int pot,
    List<String> winners,
  ) async {
    if (winners.isEmpty || pot <= 0) return;
    final share = pot ~/ winners.length;
    debugPrint('[TeenPattiService] _settlePot — pot=$pot winners=${winners.join(", ")} share=$share');
    for (final id in winners) {
      if (!id.startsWith('bot_')) {
        await _balanceRef(id).set(ServerValue.increment(share));
      }
    }
    final fresh = await _db.ref('teen_patti_rooms/$roomId/players').get();
    debugPrint('[TeenPattiService] _settlePot complete');
    final winnerNames = <String>[];
    if (fresh.exists) {
      final playersMap = fresh.value as Map<dynamic, dynamic>;
      for (final id in winners) {
        winnerNames.add(playersMap[id]?['name'] as String? ?? id);
      }
    }
    await GameLogger.instance.tpPayout(
      roomId: roomId,
      winnerNames: winnerNames.isEmpty ? winners : winnerNames,
      pot: pot,
      share: share,
    );
  }

  /// Returns the next non-folded player after [fromId], optionally skipping [skip].
  String _nextActive(
    TeenPattiState state,
    String fromId, {
    Set<String>? skip,
  }) {
    final order = state.playerOrder;
    final fromIdx = order.indexOf(fromId);
    for (int i = 1; i <= order.length; i++) {
      final id = order[(fromIdx + i) % order.length];
      final p = state.players[id];
      if (p == null || p.isFolded) continue;
      if (skip != null && skip.contains(id)) continue;
      return id;
    }
    return fromId;
  }

  List<PlayingCard> _parseCards(Map<dynamic, dynamic> data) =>
      (data['cards'] as List<dynamic>? ?? [])
          .map((c) => PlayingCard.fromMap(c as Map<dynamic, dynamic>))
          .toList();

  List<PlayingCard> _buildFullDeck() => [
        for (final suit in Suit.values)
          for (final rank in Rank.values)
            PlayingCard(suit: suit, rank: rank),
      ]; // 52 cards

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return List.generate(4, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  static const _botNames = [
    'Arjun', 'Priya', 'Ravi', 'Deepa', 'Suresh', 'Anita',
    'Vijay', 'Meena', 'Kumar', 'Latha', 'Ganesh', 'Kavitha',
  ];
}
