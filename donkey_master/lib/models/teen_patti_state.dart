import '../models/card_model.dart';

enum TeenPattiPhase {
  waiting,         // room open, waiting for players to start
  betting,         // main game loop
  sideshowPending, // waiting for sideshow accept/reject
  showdown,        // force-show or called-show, cards being compared
  payout,          // winner determined, result visible
}

enum PlayerStatus { blind, seen, folded }

// ── Hand evaluation ──────────────────────────────────────────────────────────

enum HandRank {
  highCard,      // 0 — lowest
  pair,          // 1
  color,         // 2
  sequence,      // 3
  pureSequence,  // 4
  trail,         // 5 — highest
}

// Spades > Hearts > Diamonds > Clubs (absolute Color tie-breaker)
const Map<Suit, int> _suitStrength = {
  Suit.clubs:    0,
  Suit.diamonds: 1,
  Suit.hearts:   2,
  Suit.spades:   3,
};

class HandResult {
  final HandRank rank;
  final List<int> tiebreakers;

  const HandResult(this.rank, this.tiebreakers);

  /// Positive = this hand is stronger, 0 = equal, negative = other is stronger.
  int compareTo(HandResult other) {
    final rc = rank.index.compareTo(other.rank.index);
    if (rc != 0) return rc;
    for (int i = 0; i < tiebreakers.length && i < other.tiebreakers.length; i++) {
      final c = tiebreakers[i].compareTo(other.tiebreakers[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  String get label => const {
    HandRank.highCard:     'High Card',
    HandRank.pair:         'Pair',
    HandRank.color:        'Color',
    HandRank.sequence:     'Sequence',
    HandRank.pureSequence: 'Pure Sequence',
    HandRank.trail:        'Trail',
  }[rank]!;
}

/// Evaluate a 3-card Teen Patti hand and return a comparable [HandResult].
HandResult evaluateHand(List<PlayingCard> cards) {
  assert(cards.length == 3);
  // Sort highest rank first
  final s = List<PlayingCard>.from(cards)
    ..sort((a, b) => b.rank.index.compareTo(a.rank.index));

  final isFlush = s[0].suit == s[1].suit && s[1].suit == s[2].suit;
  final seqVal  = _sequenceValue(s);
  final isSeq   = seqVal >= 0;

  // Trail — three of a kind
  if (s[0].rank == s[1].rank && s[1].rank == s[2].rank) {
    return HandResult(HandRank.trail, [s[0].rank.index]);
  }
  // Pure Sequence — straight flush
  if (isSeq && isFlush) return HandResult(HandRank.pureSequence, [seqVal]);
  // Sequence — straight
  if (isSeq) return HandResult(HandRank.sequence, [seqVal]);
  // Color — flush; tie-break by each card rank desc, then suit of highest card
  if (isFlush) {
    return HandResult(HandRank.color, [
      s[0].rank.index, s[1].rank.index, s[2].rank.index,
      _suitStrength[s[0].suit]!,
    ]);
  }
  // Pair — tie-break: pair rank, then kicker
  if (s[0].rank == s[1].rank) {
    return HandResult(HandRank.pair, [s[0].rank.index, s[2].rank.index]);
  }
  if (s[1].rank == s[2].rank) {
    return HandResult(HandRank.pair, [s[1].rank.index, s[0].rank.index]);
  }
  // High Card
  return HandResult(HandRank.highCard,
      [s[0].rank.index, s[1].rank.index, s[2].rank.index]);
}

/// Returns the sequence strength, or -1 if not a valid sequence.
/// A-K-Q → 14 (highest), A-2-3 → 13, K-Q-J → 11, …, 4-3-2 → 2.
int _sequenceValue(List<PlayingCard> s) {
  final r = [s[0].rank.index, s[1].rank.index, s[2].rank.index];
  if (r[0] == 12 && r[1] == 11 && r[2] == 10) return 14; // A-K-Q
  if (r[0] == 12 && r[1] == 1  && r[2] == 0)  return 13; // A-2-3
  if (r[0] - r[1] == 1 && r[1] - r[2] == 1)   return r[0]; // normal run
  return -1;
}

// ── Player ───────────────────────────────────────────────────────────────────

class TeenPattiPlayer {
  final String id;
  final String name;
  final bool isBot;
  final bool isHost;
  final int seatIndex;
  final PlayerStatus status;
  final int roundBet; // total chips committed by this player this round

  bool get isFolded => status == PlayerStatus.folded;
  bool get isSeen   => status == PlayerStatus.seen;
  bool get isBlind  => status == PlayerStatus.blind;

  const TeenPattiPlayer({
    required this.id,
    required this.name,
    this.isBot = false,
    this.isHost = false,
    required this.seatIndex,
    this.status = PlayerStatus.blind,
    this.roundBet = 0,
  });

  TeenPattiPlayer copyWith({
    PlayerStatus? status,
    int? roundBet,
    bool? isHost,
  }) => TeenPattiPlayer(
    id: id,
    name: name,
    isBot: isBot,
    isHost: isHost ?? this.isHost,
    seatIndex: seatIndex,
    status: status ?? this.status,
    roundBet: roundBet ?? this.roundBet,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'isBot': isBot,
    'isHost': isHost,
    'seatIndex': seatIndex,
    'status': status.index,
    'roundBet': roundBet,
  };

  factory TeenPattiPlayer.fromMap(String id, Map<dynamic, dynamic> m) =>
      TeenPattiPlayer(
        id: id,
        name: m['name'] as String? ?? 'Player',
        isBot: m['isBot'] as bool? ?? false,
        isHost: m['isHost'] as bool? ?? false,
        seatIndex: (m['seatIndex'] as num?)?.toInt() ?? 0,
        status: PlayerStatus.values[(m['status'] as num?)?.toInt() ?? 0],
        roundBet: (m['roundBet'] as num?)?.toInt() ?? 0,
      );
}

// ── State ────────────────────────────────────────────────────────────────────

class TeenPattiState {
  final String roomId;
  final String roomCode;
  final TeenPattiPhase phase;
  final String? hostId;
  final Map<String, TeenPattiPlayer> players;
  final List<String> playerOrder;

  // Economy
  final int pot;
  final int currentStake;
  final int bootAmount;
  final int potLimit;

  // Turn tracking
  final String? currentTurn;
  final String? lastActorId; // previous non-folded player — sideshow target
  final int dealerIndex;     // rotates each round
  final int roundNumber;
  final int turnStartedAt;   // epoch ms, for 20-second timeout

  // Sideshow
  final String? sideshowRequesterId;
  final String? sideshowTargetId;

  // Payout
  final List<String> winners; // player IDs who share the pot

  const TeenPattiState({
    required this.roomId,
    required this.roomCode,
    this.phase = TeenPattiPhase.waiting,
    this.hostId,
    this.players = const {},
    this.playerOrder = const [],
    this.pot = 0,
    this.currentStake = 10,
    this.bootAmount = 10,
    this.potLimit = 1000,
    this.currentTurn,
    this.lastActorId,
    this.dealerIndex = 0,
    this.roundNumber = 0,
    this.turnStartedAt = 0,
    this.sideshowRequesterId,
    this.sideshowTargetId,
    this.winners = const [],
  });

  List<TeenPattiPlayer> get orderedPlayers => playerOrder
      .where((id) => players.containsKey(id))
      .map((id) => players[id]!)
      .toList();

  /// IDs of players who have not folded.
  List<String> get activePlayers => playerOrder
      .where((id) => players[id] != null && !players[id]!.isFolded)
      .toList();

  bool get canStart => players.length >= 3;

  TeenPattiState copyWith({
    TeenPattiPhase? phase,
    String? hostId,
    Map<String, TeenPattiPlayer>? players,
    List<String>? playerOrder,
    int? pot,
    int? currentStake,
    int? bootAmount,
    int? potLimit,
    String? currentTurn,
    bool clearCurrentTurn = false,
    String? lastActorId,
    bool clearLastActor = false,
    int? dealerIndex,
    int? roundNumber,
    int? turnStartedAt,
    String? sideshowRequesterId,
    String? sideshowTargetId,
    bool clearSideshow = false,
    List<String>? winners,
  }) => TeenPattiState(
    roomId: roomId,
    roomCode: roomCode,
    phase: phase ?? this.phase,
    hostId: hostId ?? this.hostId,
    players: players ?? this.players,
    playerOrder: playerOrder ?? this.playerOrder,
    pot: pot ?? this.pot,
    currentStake: currentStake ?? this.currentStake,
    bootAmount: bootAmount ?? this.bootAmount,
    potLimit: potLimit ?? this.potLimit,
    currentTurn: clearCurrentTurn ? null : (currentTurn ?? this.currentTurn),
    lastActorId: clearLastActor ? null : (lastActorId ?? this.lastActorId),
    dealerIndex: dealerIndex ?? this.dealerIndex,
    roundNumber: roundNumber ?? this.roundNumber,
    turnStartedAt: turnStartedAt ?? this.turnStartedAt,
    sideshowRequesterId: clearSideshow ? null : (sideshowRequesterId ?? this.sideshowRequesterId),
    sideshowTargetId: clearSideshow ? null : (sideshowTargetId ?? this.sideshowTargetId),
    winners: winners ?? this.winners,
  );

  Map<String, dynamic> toMap() => {
    'roomId': roomId,
    'roomCode': roomCode,
    'phase': phase.index,
    'hostId': hostId,
    'players': players.map((k, v) => MapEntry(k, v.toMap())),
    'playerOrder': playerOrder,
    'pot': pot,
    'currentStake': currentStake,
    'bootAmount': bootAmount,
    'potLimit': potLimit,
    'currentTurn': currentTurn,
    'lastActorId': lastActorId,
    'dealerIndex': dealerIndex,
    'roundNumber': roundNumber,
    'turnStartedAt': turnStartedAt,
    'sideshowRequesterId': sideshowRequesterId,
    'sideshowTargetId': sideshowTargetId,
    'winners': winners,
  };

  factory TeenPattiState.fromMap(Map<dynamic, dynamic> m) => TeenPattiState(
    roomId: m['roomId'] as String? ?? '',
    roomCode: m['roomCode'] as String? ?? '',
    phase: TeenPattiPhase.values[(m['phase'] as num?)?.toInt() ?? 0],
    hostId: m['hostId'] as String?,
    players: ((m['players'] as Map<dynamic, dynamic>?) ?? {}).map(
      (k, v) => MapEntry(
        k.toString(),
        TeenPattiPlayer.fromMap(k.toString(), v as Map<dynamic, dynamic>),
      ),
    ),
    playerOrder: (m['playerOrder'] as List<dynamic>? ?? [])
        .map((e) => e.toString()).toList(),
    pot: (m['pot'] as num?)?.toInt() ?? 0,
    currentStake: (m['currentStake'] as num?)?.toInt() ?? 10,
    bootAmount: (m['bootAmount'] as num?)?.toInt() ?? 10,
    potLimit: (m['potLimit'] as num?)?.toInt() ?? 1000,
    currentTurn: m['currentTurn'] as String?,
    lastActorId: m['lastActorId'] as String?,
    dealerIndex: (m['dealerIndex'] as num?)?.toInt() ?? 0,
    roundNumber: (m['roundNumber'] as num?)?.toInt() ?? 0,
    turnStartedAt: (m['turnStartedAt'] as num?)?.toInt() ?? 0,
    sideshowRequesterId: m['sideshowRequesterId'] as String?,
    sideshowTargetId: m['sideshowTargetId'] as String?,
    winners: (m['winners'] as List<dynamic>? ?? [])
        .map((e) => e.toString()).toList(),
  );
}
