import '../models/card_model.dart';

enum Game28Phase {
  waiting,
  cardReview,     // players see their first 4 cards before bidding
  bidding,
  trumpSelection,
  playing,
  trickEnd,
  roundEnd,
  gameOver,
}

// ── Card utilities ────────────────────────────────────────────────────────────

bool isGame28Card(PlayingCard card) => card.rank.index >= 5; // seven..ace

int cardPoints28(Rank rank) {
  switch (rank) {
    case Rank.jack:
      return 3;
    case Rank.nine:
      return 2;
    case Rank.ace:
      return 1;
    case Rank.ten:
      return 1;
    default:
      return 0;
  }
}

/// Authentic 28 rank: J(7) > 9(6) > A(5) > 10(4) > K(3) > Q(2) > 8(1) > 7(0)
const Map<Rank, int> _rank28StrengthMap = {
  Rank.jack:  7,
  Rank.nine:  6,
  Rank.ace:   5,
  Rank.ten:   4,
  Rank.king:  3,
  Rank.queen: 2,
  Rank.eight: 1,
  Rank.seven: 0,
};

int rankStrength28(Rank rank) => _rank28StrengthMap[rank] ?? -1;

List<PlayingCard> buildDeck28() => [
      for (final suit in Suit.values)
        for (final rank in Rank.values)
          if (rank.index >= 5) PlayingCard(suit: suit, rank: rank),
    ]; // 32 cards

// ── Player ────────────────────────────────────────────────────────────────────

class Game28Player {
  final String id;
  final String name;
  final bool isBot;
  final bool isHost;
  final int seatIndex; // 0–3
  final List<PlayingCard> hand;

  int get teamIndex => seatIndex % 2; // seats 0&2 = team 0; seats 1&3 = team 1

  const Game28Player({
    required this.id,
    required this.name,
    this.isBot = false,
    this.isHost = false,
    required this.seatIndex,
    this.hand = const [],
  });

  Game28Player copyWith({List<PlayingCard>? hand, bool? isHost}) => Game28Player(
        id: id,
        name: name,
        isBot: isBot,
        isHost: isHost ?? this.isHost,
        seatIndex: seatIndex,
        hand: hand ?? this.hand,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'isBot': isBot,
        'isHost': isHost,
        'seatIndex': seatIndex,
        'hand': hand.map((c) => c.toMap()).toList(),
      };

  factory Game28Player.fromMap(String id, Map<dynamic, dynamic> map) =>
      Game28Player(
        id: id,
        name: map['name'] as String? ?? 'Player',
        isBot: map['isBot'] as bool? ?? false,
        isHost: map['isHost'] as bool? ?? false,
        seatIndex: (map['seatIndex'] as num?)?.toInt() ?? 0,
        hand: (map['hand'] as List<dynamic>? ?? [])
            .map((c) => PlayingCard.fromMap(c as Map<dynamic, dynamic>))
            .toList(),
      );
}

// ── State ─────────────────────────────────────────────────────────────────────

class Game28State {
  final String roomId;
  final String roomCode;
  final Game28Phase phase;
  final String? hostId;
  final Map<String, Game28Player> players;
  final List<String> playerOrder;

  // Bidding
  final int currentBid;         // 13 = no bid placed yet
  final String? currentBidder;
  final String? biddingTurn;
  final List<String> passedPlayers;

  // Trump
  final int? trumpSuit;         // Suit.index; null until bidder locks in
  final bool trumpRevealed;     // false until first trump card is played
  final String? bidWinnerId;
  final int? bidWinnerTeam;

  // Trick
  final Map<String, PlayingCard> currentTrick;
  final int? leadSuit;
  final String? leadPlayer;
  final String? currentTurn;
  final int trickNumber;        // 1–8

  // Two-phase deal: second 4 cards per player stored here until trump is chosen
  final List<PlayingCard> pendingDeck;

  // Set to true when the current player calls askForTrump; forces them to
  // play a trump card, then clears automatically after the card is played.
  final bool trumpRevealRequired;

  // Scores
  final Map<String, int> teamTrickPoints; // "0"/"1" → pts won this round
  final Map<String, int> teamGamePoints;  // "0"/"1" → cumulative game pts
  final int roundNumber;
  final int targetScore; // first team to this wins the game

  const Game28State({
    required this.roomId,
    required this.roomCode,
    this.phase = Game28Phase.waiting,
    this.hostId,
    this.players = const {},
    this.playerOrder = const [],
    this.currentBid = 13,
    this.currentBidder,
    this.biddingTurn,
    this.passedPlayers = const [],
    this.trumpSuit,
    this.trumpRevealed = false,
    this.bidWinnerId,
    this.bidWinnerTeam,
    this.currentTrick = const {},
    this.leadSuit,
    this.leadPlayer,
    this.currentTurn,
    this.trickNumber = 1,
    this.pendingDeck = const [],
    this.trumpRevealRequired = false,
    this.teamTrickPoints = const {'t0': 0, 't1': 0},
    this.teamGamePoints = const {'t0': 0, 't1': 0},
    this.roundNumber = 0,
    this.targetScore = 6,
  });

  List<Game28Player> get orderedPlayers => playerOrder
      .where((id) => players.containsKey(id))
      .map((id) => players[id]!)
      .toList();

  bool get canStart => players.length == 4;

  Game28State copyWith({
    Game28Phase? phase,
    String? hostId,
    Map<String, Game28Player>? players,
    List<String>? playerOrder,
    int? currentBid,
    String? currentBidder,
    bool clearBidder = false,
    String? biddingTurn,
    List<String>? passedPlayers,
    int? trumpSuit,
    bool? trumpRevealed,
    String? bidWinnerId,
    int? bidWinnerTeam,
    Map<String, PlayingCard>? currentTrick,
    int? leadSuit,
    bool clearLeadSuit = false,
    String? leadPlayer,
    String? currentTurn,
    int? trickNumber,
    List<PlayingCard>? pendingDeck,
    bool? trumpRevealRequired,
    Map<String, int>? teamTrickPoints,
    Map<String, int>? teamGamePoints,
    int? roundNumber,
    int? targetScore,
  }) =>
      Game28State(
        roomId: roomId,
        roomCode: roomCode,
        phase: phase ?? this.phase,
        hostId: hostId ?? this.hostId,
        players: players ?? this.players,
        playerOrder: playerOrder ?? this.playerOrder,
        currentBid: currentBid ?? this.currentBid,
        currentBidder:
            clearBidder ? null : (currentBidder ?? this.currentBidder),
        biddingTurn: biddingTurn ?? this.biddingTurn,
        passedPlayers: passedPlayers ?? this.passedPlayers,
        trumpSuit: trumpSuit ?? this.trumpSuit,
        trumpRevealed: trumpRevealed ?? this.trumpRevealed,
        bidWinnerId: bidWinnerId ?? this.bidWinnerId,
        bidWinnerTeam: bidWinnerTeam ?? this.bidWinnerTeam,
        currentTrick: currentTrick ?? this.currentTrick,
        leadSuit: clearLeadSuit ? null : (leadSuit ?? this.leadSuit),
        leadPlayer: leadPlayer ?? this.leadPlayer,
        currentTurn: currentTurn ?? this.currentTurn,
        trickNumber: trickNumber ?? this.trickNumber,
        pendingDeck: pendingDeck ?? this.pendingDeck,
        trumpRevealRequired: trumpRevealRequired ?? this.trumpRevealRequired,
        teamTrickPoints: teamTrickPoints ?? this.teamTrickPoints,
        teamGamePoints: teamGamePoints ?? this.teamGamePoints,
        roundNumber: roundNumber ?? this.roundNumber,
        targetScore: targetScore ?? this.targetScore,
      );

  Map<String, dynamic> toMap() => {
        'roomId': roomId,
        'roomCode': roomCode,
        'phase': phase.index,
        'hostId': hostId,
        'players': players.map((k, v) => MapEntry(k, v.toMap())),
        'playerOrder': playerOrder,
        'currentBid': currentBid,
        'currentBidder': currentBidder,
        'biddingTurn': biddingTurn,
        'passedPlayers': passedPlayers,
        'trumpSuit': trumpSuit,
        'trumpRevealed': trumpRevealed,
        'bidWinnerId': bidWinnerId,
        'bidWinnerTeam': bidWinnerTeam,
        'currentTrick': currentTrick.map((k, v) => MapEntry(k, v.toMap())),
        'leadSuit': leadSuit,
        'leadPlayer': leadPlayer,
        'currentTurn': currentTurn,
        'trickNumber': trickNumber,
        'pendingDeck': pendingDeck.map((c) => c.toMap()).toList(),
        'trumpRevealRequired': trumpRevealRequired,
        'teamTrickPoints': teamTrickPoints,
        'teamGamePoints': teamGamePoints,
        'roundNumber': roundNumber,
        'targetScore': targetScore,
      };

  factory Game28State.fromMap(Map<dynamic, dynamic> map) {
    final trickPts =
        (map['teamTrickPoints'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{};
    final gamePts =
        (map['teamGamePoints'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{};
    return Game28State(
      roomId: map['roomId'] as String? ?? '',
      roomCode: map['roomCode'] as String? ?? '',
      phase: Game28Phase.values[(map['phase'] as num?)?.toInt() ?? 0],
      hostId: map['hostId'] as String?,
      players: ((map['players'] as Map<dynamic, dynamic>?) ?? {}).map(
        (k, v) => MapEntry(
          k.toString(),
          Game28Player.fromMap(k.toString(), v as Map<dynamic, dynamic>),
        ),
      ),
      playerOrder: (map['playerOrder'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      currentBid: (map['currentBid'] as num?)?.toInt() ?? 13,
      currentBidder: map['currentBidder'] as String?,
      biddingTurn: map['biddingTurn'] as String?,
      passedPlayers: (map['passedPlayers'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      trumpSuit: (map['trumpSuit'] as num?)?.toInt(),
      trumpRevealed: map['trumpRevealed'] as bool? ?? false,
      bidWinnerId: map['bidWinnerId'] as String?,
      bidWinnerTeam: (map['bidWinnerTeam'] as num?)?.toInt(),
      currentTrick: ((map['currentTrick'] as Map<dynamic, dynamic>?) ?? {}).map(
        (k, v) => MapEntry(
          k.toString(),
          PlayingCard.fromMap(v as Map<dynamic, dynamic>),
        ),
      ),
      leadSuit: (map['leadSuit'] as num?)?.toInt(),
      leadPlayer: map['leadPlayer'] as String?,
      currentTurn: map['currentTurn'] as String?,
      trickNumber: (map['trickNumber'] as num?)?.toInt() ?? 1,
      pendingDeck: (map['pendingDeck'] as List<dynamic>? ?? [])
          .map((c) => PlayingCard.fromMap(c as Map<dynamic, dynamic>))
          .toList(),
      trumpRevealRequired: map['trumpRevealRequired'] as bool? ?? false,
      teamTrickPoints: {
        't0': (trickPts['t0'] as num?)?.toInt() ?? 0,
        't1': (trickPts['t1'] as num?)?.toInt() ?? 0,
      },
      teamGamePoints: {
        't0': (gamePts['t0'] as num?)?.toInt() ?? 0,
        't1': (gamePts['t1'] as num?)?.toInt() ?? 0,
      },
      roundNumber: (map['roundNumber'] as num?)?.toInt() ?? 0,
      targetScore: (map['targetScore'] as num?)?.toInt() ?? 6,
    );
  }
}
