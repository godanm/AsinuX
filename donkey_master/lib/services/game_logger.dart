import 'package:firebase_database/firebase_database.dart';
import '../models/card_model.dart';

/// Lightweight game event logger — writes to `gamelogs/{roomId}/events`.
/// Enable/disable with [enabled]. Costs negligible reads; writes only on events.
class GameLogger {
  static final GameLogger _instance = GameLogger._();
  static GameLogger get instance => _instance;
  GameLogger._();

  static const enabled = true; // set false to disable all logging

  final _db = FirebaseDatabase.instance;
  DatabaseReference _ref(String roomId) => _db.ref('gamelogs/$roomId/events');

  String _cardStr(PlayingCard c) => '${c.rank.name}_of_${c.suit.name}';

  String _handStr(List<PlayingCard> hand) =>
      hand.map(_cardStr).join(', ');

  Future<void> _log(String roomId, String event, Map<String, dynamic> data) async {
    if (!enabled) return;
    await _ref(roomId).push().set({
      'event': event,
      'ts': ServerValue.timestamp,
      ...data,
    });
  }

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
  }) => _log(roomId, 'CARD_PLAYED', {
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
  }) => _log(roomId, 'CUT_DETECTED', {
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
  }) => _log(roomId, 'TRICK_WON', {
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
  }) => _log(roomId, 'TRICK_START', {
    'trick': trickNumber,
    'leader': '$leaderName ($leaderId)',
    'leaderHand': _handStr(leaderHand),
    'leaderHandSize': leaderHand.length,
    'allHandSizes': allHandSizes,
  });

  Future<void> roundEnd({
    required String roomId,
    required String donkeyId,
    required String donkeyName,
    required List<String> finishOrder,
    required int trickNumber,
  }) => _log(roomId, 'ROUND_END', {
    'trick': trickNumber,
    'donkey': '$donkeyName ($donkeyId)',
    'finishOrder': finishOrder,
  });
}
