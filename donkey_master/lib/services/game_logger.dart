import 'package:firebase_database/firebase_database.dart';
import '../models/card_model.dart';

/// Lightweight game event logger — writes to `gamelogs/{roomId}/events`.
/// Every entry carries: event, gameType, ts (epoch ms), datetime (ISO-8601 UTC).
class GameLogger {
  static final GameLogger _instance = GameLogger._();
  static GameLogger get instance => _instance;
  GameLogger._();

  static const enabled = true;

  final _db = FirebaseDatabase.instance;

  // Keyed by roomId → session node name for current game session
  final Map<String, String> _sessionKeys = {};

  // Session node: "{roomId}-started-{datetime}-game-{gameType}"
  // Firebase keys can't contain '.' so milliseconds are stripped from the timestamp.
  DatabaseReference _ref(String roomId) {
    final key = _sessionKeys[roomId];
    return _db.ref('gamelogs/${key ?? roomId}/events');
  }

  Future<void> _initRoom(String roomId, String gameType) async {
    if (!enabled) return;
    if (_sessionKeys.containsKey(roomId)) return; // already initialised — don't split the log
    final ts = '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
    final sessionKey = '$roomId-started-$ts-game-$gameType';
    _sessionKeys[roomId] = sessionKey;
    // Node is created implicitly when first event is pushed; no extra write needed.
  }

  String _cardStr(PlayingCard c) => '${c.rank.name}_of_${c.suit.name}';
  String _handStr(List<PlayingCard> hand) => hand.map(_cardStr).join(', ');

  static String cardLabel(PlayingCard c) => '${c.rank.name}_of_${c.suit.name}';
  static String handLabel(List<PlayingCard> hand) => hand.map(cardLabel).join(', ');

  Future<void> _log(
    String roomId,
    String event,
    String gameType,
    Map<String, dynamic> data,
  ) async {
    if (!enabled) return;
    // Lazily initialize session key if missing (e.g. after app reload mid-game)
    if (!_sessionKeys.containsKey(roomId)) {
      await _initRoom(roomId, gameType);
    }
    await _ref(roomId).push().set({
      'event': event,
      'gameType': gameType,
      'ts': ServerValue.timestamp,
      'datetime': DateTime.now().toUtc().toIso8601String(),
      ...data,
    });
  }

  // ── Kazhutha ──────────────────────────────────────────────────────────────

  Future<void> cardPlayed({
    required String roomId,
    required String playerId,
    required String playerName,
    required PlayingCard card,
    required List<PlayingCard> handBefore,
    required List<PlayingCard> handAfter,
    required bool isLeader,
    required bool isCut,
    required int? leadSuit,
    required int trickNumber,
  }) =>
      _log(roomId, 'CARD_PLAYED', 'kazhutha', {
        'trick': trickNumber,
        'player': '$playerName ($playerId)',
        'card': _cardStr(card),
        'isLeader': isLeader,
        'isCut': isCut,
        'leadSuit': leadSuit != null ? Suit.values[leadSuit].name : null,
        'handBefore': _handStr(handBefore),
        'handAfter': _handStr(handAfter),
        'handSizeBefore': handBefore.length,
        'handSizeAfter': handAfter.length,
      });

  Future<void> cutDetected({
    required String roomId,
    required String cutterId,
    required String cutterName,
    required String pickupId,
    required String pickupName,
    required List<PlayingCard> tableCards,
    required List<PlayingCard> pickupHandBefore,
    required List<PlayingCard> pickupHandAfter,
    required int trickNumber,
  }) =>
      _log(roomId, 'CUT_DETECTED', 'kazhutha', {
        'trick': trickNumber,
        'cutter': '$cutterName ($cutterId)',
        'pickup': '$pickupName ($pickupId)',
        'tableCards': tableCards.map(_cardStr).join(', '),
        'tableCardCount': tableCards.length,
        'pickupHandBefore': _handStr(pickupHandBefore),
        'pickupHandAfter': _handStr(pickupHandAfter),
        'pickupHandSizeBefore': pickupHandBefore.length,
        'pickupHandSizeAfter': pickupHandAfter.length,
      });

  Future<void> trickWon({
    required String roomId,
    required String winnerId,
    required String winnerName,
    required int trickNumber,
  }) =>
      _log(roomId, 'TRICK_WON', 'kazhutha', {
        'trick': trickNumber,
        'winner': '$winnerName ($winnerId)',
      });

  Future<void> trickStart({
    required String roomId,
    required String leaderId,
    required String leaderName,
    required List<PlayingCard> leaderHand,
    required Map<String, int> allHandSizes,
    required int trickNumber,
  }) async {
    if (trickNumber == 1) await _initRoom(roomId, 'kazhutha');
    return _log(roomId, 'TRICK_START', 'kazhutha', {
      'trick': trickNumber,
      'leader': '$leaderName ($leaderId)',
      'leaderHand': _handStr(leaderHand),
      'leaderHandSize': leaderHand.length,
      'allHandSizes': allHandSizes,
    });
  }

  Future<void> roundEnd({
    required String roomId,
    required String donkeyId,
    required String donkeyName,
    required List<String> finishOrder,
    required int trickNumber,
  }) =>
      _log(roomId, 'ROUND_END', 'kazhutha', {
        'trick': trickNumber,
        'donkey': '$donkeyName ($donkeyId)',
        'finishOrder': finishOrder,
      });

  // ── Rummy ─────────────────────────────────────────────────────────────────

  Future<void> rummyGameStart({
    required String roomId,
    required Map<String, String> playerNames,
    required String wildJokerRank,
  }) async {
    await _initRoom(roomId, 'rummy');
    return _log(roomId, 'GAME_START', 'rummy', {
      'players': playerNames,
      'wildJoker': wildJokerRank,
    });
  }

  Future<void> rummyDraw({
    required String roomId,
    required String playerId,
    required String playerName,
    required bool fromOpen,
    String? cardDrawn,
    required int handSizeAfter,
  }) =>
      _log(roomId, 'DRAW', 'rummy', {
        'player': '$playerName ($playerId)',
        'source': fromOpen ? 'open' : 'closed',
        if (cardDrawn case final v?) 'card': v,
        'handSizeAfter': handSizeAfter,
      });

  Future<void> rummyDiscard({
    required String roomId,
    required String playerId,
    required String playerName,
    required String cardLabel,
    required int handSizeAfter,
  }) =>
      _log(roomId, 'DISCARD', 'rummy', {
        'player': '$playerName ($playerId)',
        'card': cardLabel,
        'handSizeAfter': handSizeAfter,
      });

  Future<void> rummyGameEnd({
    required String roomId,
    required String winnerId,
    required String winnerName,
    required Map<String, int> scores,
  }) =>
      _log(roomId, 'GAME_END', 'rummy', {
        'winner': '$winnerName ($winnerId)',
        'scores': scores,
      });

  // ── Teen Patti ────────────────────────────────────────────────────────────

  Future<void> tpGameStart({
    required String roomId,
    required int roundNumber,
    required Map<String, String> playerNames, // id → name
    required int bootAmount,
    required String firstTurn,
  }) async {
    await _initRoom(roomId, 'teen_patti');
    return _log(roomId, 'GAME_START', 'teen_patti', {
      'round': roundNumber,
      'players': playerNames,
      'bootAmount': bootAmount,
      'firstTurn': firstTurn,
    });
  }

  Future<void> tpSeeCards({
    required String roomId,
    required String playerId,
    required String playerName,
    required String handLabel,
  }) =>
      _log(roomId, 'SEE_CARDS', 'teen_patti', {
        'player': '$playerName ($playerId)',
        'hand': handLabel,
      });

  Future<void> tpFold({
    required String roomId,
    required String playerId,
    required String playerName,
    required int pot,
    required bool timeout,
  }) =>
      _log(roomId, 'FOLD', 'teen_patti', {
        'player': '$playerName ($playerId)',
        'pot': pot,
        'timeout': timeout,
      });

  Future<void> tpBet({
    required String roomId,
    required String playerId,
    required String playerName,
    required String action, // 'CHAAL' | 'RAISE'
    required int bet,
    required int newStake,
    required int potBefore,
    required int potAfter,
    required bool wasBlind,
  }) =>
      _log(roomId, action, 'teen_patti', {
        'player': '$playerName ($playerId)',
        'bet': bet,
        'newStake': newStake,
        'potBefore': potBefore,
        'potAfter': potAfter,
        'wasBlind': wasBlind,
      });

  Future<void> tpSideshowRequest({
    required String roomId,
    required String requesterId,
    required String requesterName,
    required String targetId,
    required String targetName,
  }) =>
      _log(roomId, 'SIDESHOW_REQUEST', 'teen_patti', {
        'requester': '$requesterName ($requesterId)',
        'target': '$targetName ($targetId)',
      });

  Future<void> tpSideshowResult({
    required String roomId,
    required String requesterId,
    required String requesterName,
    required String responderId,
    required String responderName,
    required bool accepted,
    String? loserName, // null if rejected
    String? requesterHand,
    String? responderHand,
  }) =>
      _log(roomId, 'SIDESHOW_RESULT', 'teen_patti', {
        'requester': '$requesterName ($requesterId)',
        'responder': '$responderName ($responderId)',
        'accepted': accepted,
        if (loserName != null) 'loser': loserName,
        if (requesterHand != null) 'requesterHand': requesterHand,
        if (responderHand != null) 'responderHand': responderHand,
      });

  Future<void> tpShow({
    required String roomId,
    required String callerId,
    required String callerName,
    required String otherId,
    required String otherName,
    required String? callerHand,
    required String? otherHand,
    required List<String> winners,
    required int pot,
    required int showCost,
  }) =>
      _log(roomId, 'SHOW', 'teen_patti', {
        'caller': '$callerName ($callerId)',
        'other': '$otherName ($otherId)',
        if (callerHand != null) 'callerHand': callerHand,
        if (otherHand != null) 'otherHand': otherHand,
        'winners': winners,
        'pot': pot,
        'showCost': showCost,
      });

  Future<void> tpForceShow({
    required String roomId,
    required Map<String, String> hands, // id → hand label
    required List<String> winners,
    required int pot,
  }) =>
      _log(roomId, 'FORCE_SHOW', 'teen_patti', {
        'hands': hands,
        'winners': winners,
        'pot': pot,
      });

  Future<void> tpPayout({
    required String roomId,
    required List<String> winnerNames,
    required int pot,
    required int share,
  }) =>
      _log(roomId, 'PAYOUT', 'teen_patti', {
        'winners': winnerNames,
        'pot': pot,
        'share': share,
      });

  Future<void> tpAutoFold({
    required String roomId,
    required String playerId,
    required String playerName,
  }) =>
      _log(roomId, 'AUTO_FOLD_TIMEOUT', 'teen_patti', {
        'player': '$playerName ($playerId)',
      });

  // ── 28 ────────────────────────────────────────────────────────────────────

  Future<void> game28RoundStart({
    required String roomId,
    required int roundNumber,
    required String firstBidder,
    required Map<String, List<PlayingCard>> hands,
  }) async {
    await _initRoom(roomId, '28');
    return _log(roomId, 'ROUND_START', '28', {
      'round': roundNumber,
      'firstBidder': firstBidder,
      'hands': hands.map((k, v) => MapEntry(k, _handStr(v))),
    });
  }

  Future<void> game28BidPlaced({
    required String roomId,
    required String playerId,
    required String playerName,
    required int? bidValue, // null = pass
    required int currentBid,
  }) =>
      _log(roomId, 'BID', '28', {
        'player': '$playerName ($playerId)',
        'bid': bidValue ?? 'PASS',
        'prevBid': currentBid,
      });

  Future<void> game28TrumpSelected({
    required String roomId,
    required String bidderId,
    required String bidderName,
    required int suitIndex,
    required int bidAmount,
  }) =>
      _log(roomId, 'TRUMP_SELECTED', '28', {
        'bidder': '$bidderName ($bidderId)',
        'trump': Suit.values[suitIndex].name,
        'bid': bidAmount,
      });

  Future<void> game28TrumpRevealed({
    required String roomId,
    required String revealerId,
    required String revealer,
    required String trump,
    required bool isBidWinner,
  }) =>
      _log(roomId, 'TRUMP_REVEALED', '28', {
        'revealer': '$revealer ($revealerId)',
        'trump': trump,
        'isBidWinner': isBidWinner,
      });

  Future<void> game28CardPlayed({
    required String roomId,
    required String playerId,
    required String playerName,
    required PlayingCard card,
    required int trickNumber,
    required bool isLeader,
    required bool trumpRevealed,
  }) =>
      _log(roomId, 'CARD_PLAYED', '28', {
        'trick': trickNumber,
        'player': '$playerName ($playerId)',
        'card': _cardStr(card),
        'isLeader': isLeader,
        'trumpRevealed': trumpRevealed,
      });

  Future<void> game28TrickWon({
    required String roomId,
    required String winnerId,
    required String winnerName,
    required int trickNumber,
    required int trickPoints,
    required Map<String, int> teamTrickPoints,
  }) =>
      _log(roomId, 'TRICK_WON', '28', {
        'trick': trickNumber,
        'winner': '$winnerName ($winnerId)',
        'trickPoints': trickPoints,
        'teamTrickPoints': teamTrickPoints,
      });

  Future<void> game28RoundEnd({
    required String roomId,
    required int roundNumber,
    required int bid,
    required bool bidMet,
    required bool isThani,
    required int gamePointsAwarded,
    required Map<String, int> teamGamePoints,
  }) =>
      _log(roomId, 'ROUND_END', '28', {
        'round': roundNumber,
        'bid': bid,
        'bidMet': bidMet,
        'isThani': isThani,
        'gamePointsAwarded': gamePointsAwarded,
        'teamGamePoints': teamGamePoints,
      });

  // ── Blackjack ─────────────────────────────────────────────────────────────

  Future<void> bjGameStart({
    required String sessionKey,
    required String playerName,
    required int chips,
  }) async {
    await _initRoom(sessionKey, 'blackjack');
    return _log(sessionKey, 'GAME_START', 'blackjack', {
      'player': playerName,
      'chips': chips,
    });
  }

  Future<void> bjRoundStart({
    required String sessionKey,
    required int bet,
    required int chips,
    required String playerHand,
    required int playerValue,
    required String dealerVisible,
  }) =>
      _log(sessionKey, 'ROUND_START', 'blackjack', {
        'bet': bet,
        'chips': chips,
        'playerHand': playerHand,
        'playerValue': playerValue,
        'dealerVisible': dealerVisible,
      });

  Future<void> bjAction({
    required String sessionKey,
    required String action, // 'HIT' | 'STAND' | 'DOUBLE_DOWN'
    required String hand,
    required int value,
  }) =>
      _log(sessionKey, action, 'blackjack', {
        'hand': hand,
        'value': value,
      });

  Future<void> bjRoundEnd({
    required String sessionKey,
    required String result,
    required int delta,
    required String playerHand,
    required int playerValue,
    required String dealerHand,
    required int dealerValue,
    required int chipsAfter,
  }) =>
      _log(sessionKey, 'ROUND_END', 'blackjack', {
        'result': result,
        'delta': delta,
        'playerHand': playerHand,
        'playerValue': playerValue,
        'dealerHand': dealerHand,
        'dealerValue': dealerValue,
        'chipsAfter': chipsAfter,
      });

  // ── Bluff ─────────────────────────────────────────────────────────────────

  Future<void> bluffGameStart({
    required String sessionKey,
    required String playerName,
    required List<String> botNames,
  }) async {
    await _initRoom(sessionKey, 'bluff');
    return _log(sessionKey, 'GAME_START', 'bluff', {
      'player': playerName,
      'bots': botNames,
    });
  }

  Future<void> bluffPlay({
    required String sessionKey,
    required String playerName,
    required int cardCount,
    required String claimedRank,
    required bool isBluff,
    required int pileAfter,
    required int handAfter,
  }) =>
      _log(sessionKey, 'PLAY', 'bluff', {
        'player': playerName,
        'cardCount': cardCount,
        'claimedRank': claimedRank,
        'isBluff': isBluff,
        'pileAfter': pileAfter,
        'handAfter': handAfter,
      });

  Future<void> bluffCall({
    required String sessionKey,
    required String callerName,
    required bool wasHonest,
    required String loserName,
    required int pileSize,
  }) =>
      _log(sessionKey, 'CALL_BLUFF', 'bluff', {
        'caller': callerName,
        'wasHonest': wasHonest,
        'loser': loserName,
        'pileSize': pileSize,
      });

  Future<void> bluffGameEnd({
    required String sessionKey,
    required String winnerName,
    required bool humanWon,
    required int bluffsAttempted,
    required int bluffsCaught,
    required int bluffsSucceeded,
  }) =>
      _log(sessionKey, 'GAME_END', 'bluff', {
        'winner': winnerName,
        'humanWon': humanWon,
        'bluffsAttempted': bluffsAttempted,
        'bluffsCaught': bluffsCaught,
        'bluffsSucceeded': bluffsSucceeded,
      });
}
