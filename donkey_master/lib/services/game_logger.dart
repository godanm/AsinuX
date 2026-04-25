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
    final ts = '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
    final sessionKey = '$roomId-started-$ts-game-$gameType';
    _sessionKeys[roomId] = sessionKey;
    // Node is created implicitly when first event is pushed; no extra write needed.
  }

  String _cardStr(PlayingCard c) => '${c.rank.name}_of_${c.suit.name}';
  String _handStr(List<PlayingCard> hand) => hand.map(_cardStr).join(', ');

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
}
