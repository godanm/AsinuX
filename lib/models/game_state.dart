import 'player_model.dart';
import 'card_model.dart';

enum GamePhase { waiting, playing, trickEnd, gameOver }

class GameState {
  final String roomId;
  final String roomCode;
  final Map<String, Player> players;
  final GamePhase phase;
  final String? hostId;
  final List<String> playerOrder;

  // Draw pile (cards not yet dealt)
  final List<PlayingCard> drawPile;

  // Current trick
  final Map<String, PlayingCard> playedCards; // playerId → card played this trick
  final int? currentSuit; // Suit index, set by leader's card
  final String? currentLeader; // who leads this trick
  final String? currentTurn; // whose turn it is right now
  final String? trickWinnerId; // set when trick is complete

  // Round / tournament
  final String? donkeyId; // who lost this round
  final String? tournamentWinnerId;
  final List<String> finishOrder; // order players emptied their hand this round
  final int roundNumber;
  final int trickNumber;

  const GameState({
    required this.roomId,
    required this.roomCode,
    this.players = const {},
    this.phase = GamePhase.waiting,
    this.hostId,
    this.playerOrder = const [],
    this.drawPile = const [],
    this.playedCards = const {},
    this.currentSuit,
    this.currentLeader,
    this.currentTurn,
    this.trickWinnerId,
    this.donkeyId,
    this.tournamentWinnerId,
    this.finishOrder = const [],
    this.roundNumber = 0,
    this.trickNumber = 0,
  });

  List<Player> get activePlayers => playerOrder
      .where((id) => players.containsKey(id))
      .map((id) => players[id]!)
      .where((p) => !p.isEliminated)
      .toList();

  List<Player> get playersStillInRound => activePlayers
      .where((p) => p.hand.isNotEmpty)
      .toList();

  List<Player> get allPlayers => playerOrder
      .where((id) => players.containsKey(id))
      .map((id) => players[id]!)
      .toList();

  bool get canStart => activePlayers.length >= 2;

  GameState copyWith({
    Map<String, Player>? players,
    GamePhase? phase,
    String? hostId,
    List<String>? playerOrder,
    List<PlayingCard>? drawPile,
    Map<String, PlayingCard>? playedCards,
    int? currentSuit,
    bool clearCurrentSuit = false,
    String? currentLeader,
    String? currentTurn,
    String? trickWinnerId,
    bool clearTrickWinner = false,
    String? donkeyId,
    bool clearDonkey = false,
    String? tournamentWinnerId,
    List<String>? finishOrder,
    int? roundNumber,
    int? trickNumber,
  }) {
    return GameState(
      roomId: roomId,
      roomCode: roomCode,
      players: players ?? this.players,
      phase: phase ?? this.phase,
      hostId: hostId ?? this.hostId,
      playerOrder: playerOrder ?? this.playerOrder,
      drawPile: drawPile ?? this.drawPile,
      playedCards: playedCards ?? this.playedCards,
      currentSuit:
          clearCurrentSuit ? null : (currentSuit ?? this.currentSuit),
      currentLeader: currentLeader ?? this.currentLeader,
      currentTurn: currentTurn ?? this.currentTurn,
      trickWinnerId: clearTrickWinner
          ? null
          : (trickWinnerId ?? this.trickWinnerId),
      donkeyId: clearDonkey ? null : (donkeyId ?? this.donkeyId),
      tournamentWinnerId: tournamentWinnerId ?? this.tournamentWinnerId,
      finishOrder: finishOrder ?? this.finishOrder,
      roundNumber: roundNumber ?? this.roundNumber,
      trickNumber: trickNumber ?? this.trickNumber,
    );
  }

  Map<String, dynamic> toMap() => {
        'roomId': roomId,
        'roomCode': roomCode,
        'players': players.map((k, v) => MapEntry(k, v.toMap())),
        'phase': phase.index,
        'hostId': hostId,
        'playerOrder': playerOrder,
        'drawPile': drawPile.map((c) => c.toMap()).toList(),
        'playedCards':
            playedCards.map((k, v) => MapEntry(k, v.toMap())),
        'currentSuit': currentSuit,
        'currentLeader': currentLeader,
        'currentTurn': currentTurn,
        'trickWinnerId': trickWinnerId,
        'donkeyId': donkeyId,
        'tournamentWinnerId': tournamentWinnerId,
        'finishOrder': finishOrder,
        'roundNumber': roundNumber,
        'trickNumber': trickNumber,
      };

  factory GameState.fromMap(Map<dynamic, dynamic> map) {
    final playersRaw = map['players'] as Map<dynamic, dynamic>? ?? {};
    final players = playersRaw.map(
      (k, v) => MapEntry(
        k.toString(),
        Player.fromMap(k.toString(), v as Map<dynamic, dynamic>),
      ),
    );

    final drawPileRaw = map['drawPile'] as List<dynamic>? ?? [];
    final drawPile = drawPileRaw
        .map((c) => PlayingCard.fromMap(c as Map<dynamic, dynamic>))
        .toList();

    final playedRaw = map['playedCards'] as Map<dynamic, dynamic>? ?? {};
    final playedCards = playedRaw.map(
      (k, v) => MapEntry(
        k.toString(),
        PlayingCard.fromMap(v as Map<dynamic, dynamic>),
      ),
    );

    return GameState(
      roomId: map['roomId'] as String? ?? '',
      roomCode: map['roomCode'] as String? ?? '',
      players: players,
      phase: GamePhase.values[map['phase'] as int? ?? 0],
      hostId: map['hostId'] as String?,
      playerOrder: (map['playerOrder'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      drawPile: drawPile,
      playedCards: playedCards,
      currentSuit: map['currentSuit'] as int?,
      currentLeader: map['currentLeader'] as String?,
      currentTurn: map['currentTurn'] as String?,
      trickWinnerId: map['trickWinnerId'] as String?,
      donkeyId: map['donkeyId'] as String?,
      tournamentWinnerId: map['tournamentWinnerId'] as String?,
      finishOrder: (map['finishOrder'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      roundNumber: map['roundNumber'] as int? ?? 0,
      trickNumber: map['trickNumber'] as int? ?? 0,
    );
  }
}
