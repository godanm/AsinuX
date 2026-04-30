import '../models/card_model.dart' show Suit;

// ── Card ──────────────────────────────────────────────────────────────────────

class RummyCard {
  /// 1=A  2-10  11=J  12=Q  13=K  0=printed joker
  final int rank;
  /// 0=♠  1=♥  2=♦  3=♣  -1=printed joker
  final int suit;
  final bool isPrintedJoker;

  const RummyCard({
    required this.rank,
    required this.suit,
    this.isPrintedJoker = false,
  });

  // ── Display ────────────────────────────────────────────────────

  String get rankLabel => switch (rank) {
        0 => 'JKR',
        1 => 'A',
        11 => 'J',
        12 => 'Q',
        13 => 'K',
        _ => '$rank',
      };

  String get suitSymbol => switch (suit) {
        0 => '♠',
        1 => '♥',
        2 => '♦',
        3 => '♣',
        _ => '★',
      };

  bool get isRed => suit == 1 || suit == 2;

  // ── Points ─────────────────────────────────────────────────────

  int get points {
    if (isPrintedJoker || rank == 0) return 0;
    if (rank == 1 || rank >= 11) return 10; // A, J, Q, K
    return rank; // 2–10
  }

  // ── Serialisation ──────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'rank': rank,
        'suit': suit,
        'isPrintedJoker': isPrintedJoker,
      };

  factory RummyCard.fromMap(Map<dynamic, dynamic> map) => RummyCard(
        rank: (map['rank'] as num).toInt(),
        suit: (map['suit'] as num).toInt(),
        isPrintedJoker: (map['isPrintedJoker'] as bool?) ?? false,
      );

  @override
  String toString() => isPrintedJoker ? 'JKR' : '$rankLabel$suitSymbol';

  @override
  bool operator ==(Object other) =>
      other is RummyCard &&
      other.rank == rank &&
      other.suit == suit &&
      other.isPrintedJoker == isPrintedJoker;

  @override
  int get hashCode => Object.hash(rank, suit, isPrintedJoker);
}

// ── Deck factory ──────────────────────────────────────────────────────────────

List<RummyCard> buildRummyDeck() {
  final cards = <RummyCard>[];
  for (int d = 0; d < 2; d++) {
    for (int s = 0; s < 4; s++) {
      for (int r = 1; r <= 13; r++) {
        cards.add(RummyCard(rank: r, suit: s));
      }
    }
  }
  // Two printed jokers
  cards.add(const RummyCard(rank: 0, suit: -1, isPrintedJoker: true));
  cards.add(const RummyCard(rank: 0, suit: -1, isPrintedJoker: true));
  return cards;
}

// ── Phase ─────────────────────────────────────────────────────────────────────

enum RummyPhase { draw, discard, gameOver }

RummyPhase rummyPhaseFromString(String s) => switch (s) {
      'discard' => RummyPhase.discard,
      'gameOver' => RummyPhase.gameOver,
      _ => RummyPhase.draw,
    };

// ── Meld validation ───────────────────────────────────────────────────────────

bool isRummyJoker(RummyCard c, int wildRank) =>
    c.isPrintedJoker || c.rank == wildRank;

/// True if [cards] form a valid sequence (run of 3+ consecutive same-suit cards,
/// jokers may substitute for any card).
bool isValidSequence(List<RummyCard> cards, int wildRank) {
  if (cards.length < 3) return false;
  final jokers = cards.where((c) => isRummyJoker(c, wildRank)).toList();
  final regs = cards.where((c) => !isRummyJoker(c, wildRank)).toList();
  if (regs.isEmpty) return false;

  final suit = regs.first.suit;
  if (regs.any((c) => c.suit != suit)) return false;

  bool checkRanks(List<int> ranks) {
    final sorted = List<int>.from(ranks)..sort();
    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i] == sorted[i - 1]) return false;
    }
    final jokerCount = jokers.length;
    final minR = sorted.first;
    // Clamp upper bound at 14 to support Ace-as-high (rank 14) for Q-K-A
    final startFrom = (minR - jokerCount).clamp(1, 14);
    for (int start = startFrom; start <= minR; start++) {
      final end = start + cards.length - 1;
      if (end > 14) continue;
      if (sorted.any((r) => r < start || r > end)) continue;
      return true;
    }
    return false;
  }

  final baseRanks = regs.map((c) => c.rank).toList();
  if (checkRanks(baseRanks)) return true;

  // Try Ace as high (14) to validate Q-K-A sequences
  if (baseRanks.contains(1)) {
    final highAceRanks = baseRanks.map((r) => r == 1 ? 14 : r).toList();
    if (checkRanks(highAceRanks)) return true;
  }

  return false;
}

/// True if [cards] form a valid set (3-4 same-rank different-suit cards,
/// jokers may substitute).
bool isValidSet(List<RummyCard> cards, int wildRank) {
  if (cards.length < 3 || cards.length > 4) return false;
  final regs = cards.where((c) => !isRummyJoker(c, wildRank)).toList();
  if (regs.isEmpty) return false;

  final rank = regs.first.rank;
  if (regs.any((c) => c.rank != rank)) return false;

  final suits = regs.map((c) => c.suit).toSet();
  if (suits.length != regs.length) return false; // duplicate suits

  return true;
}

bool isValidMeld(List<RummyCard> cards, int wildRank) =>
    isValidSequence(cards, wildRank) || isValidSet(cards, wildRank);

bool isPureSequence(List<RummyCard> cards, int wildRank) =>
    isValidSequence(cards, wildRank) &&
    cards.every((c) => !isRummyJoker(c, wildRank));

/// Validates a full declaration. Returns null if valid, error message if invalid.
String? validateDeclaration(List<List<RummyCard>> melds, int wildRank) {
  final total = melds.fold(0, (s, m) => s + m.length);
  if (total != 13) return 'Need exactly 13 cards in melds (got $total)';

  for (final meld in melds) {
    if (meld.isEmpty) continue;
    if (!isValidMeld(meld, wildRank)) {
      return 'Invalid meld: ${meld.map((c) => c.toString()).join(' ')}';
    }
  }

  final nonEmpty = melds.where((m) => m.isNotEmpty).toList();
  final pureSeqs = nonEmpty.where((m) => isPureSequence(m, wildRank)).length;
  if (pureSeqs < 1) return 'Need at least 1 pure sequence (no jokers)';

  final seqs = nonEmpty.where((m) => isValidSequence(m, wildRank)).length;
  if (seqs < 2) return 'Need at least 2 sequences';

  return null; // valid!
}

// ── Player ────────────────────────────────────────────────────────────────────

class RummyPlayer {
  final String id;
  final String name;
  final List<RummyCard> hand;
  final bool hasDropped;

  const RummyPlayer({
    required this.id,
    required this.name,
    required this.hand,
    this.hasDropped = false,
  });

  int get handSize => hand.length;
  int get deadwood => hand.fold(0, (sum, c) => sum + c.points);

  // Helper: is this card a wild joker given the current wild rank?
  bool isWildJoker(RummyCard card, int wildRank) =>
      !card.isPrintedJoker && card.rank == wildRank;

  factory RummyPlayer.fromMap(String id, Map<dynamic, dynamic> map,
      List<RummyCard> hand) =>
      RummyPlayer(
        id: id,
        name: map['name'] as String,
        hand: hand,
        hasDropped: (map['hasDropped'] as bool?) ?? false,
      );

  Map<String, dynamic> toPlayerMap() => {
        'id': id,
        'name': name,
        'handSize': hand.length,
        'hasDropped': hasDropped,
      };
}

// ── Game State ────────────────────────────────────────────────────────────────

class RummyGameState {
  final String roomId;
  final RummyPhase phase;
  final String currentTurn;
  final List<String> turnOrder;
  final RummyCard wildJoker;
  final List<RummyCard> openDeck;   // last element = top (visible)
  final int closedDeckCount;
  final Map<String, RummyPlayer> players;
  final String? winnerId;
  final Map<String, int> scores;        // current-round penalty points
  final Map<String, int> sessionScores; // cumulative across rounds
  final int targetScore;  // 0 = single round; 101 / 201 = Pool Rummy
  final int round;        // 1-based round number
  final bool sessionOver;
  final String? sessionWinnerId;

  const RummyGameState({
    required this.roomId,
    required this.phase,
    required this.currentTurn,
    required this.turnOrder,
    required this.wildJoker,
    required this.openDeck,
    required this.closedDeckCount,
    required this.players,
    this.winnerId,
    this.scores = const {},
    this.sessionScores = const {},
    this.targetScore = 0,
    this.round = 1,
    this.sessionOver = false,
    this.sessionWinnerId,
  });

  RummyCard? get topOfOpen => openDeck.isNotEmpty ? openDeck.last : null;

  List<RummyPlayer> get activePlayers =>
      turnOrder.map((id) => players[id]).whereType<RummyPlayer>().toList();

  factory RummyGameState.fromMap(
    String roomId,
    Map<dynamic, dynamic> map,
    Map<String, List<RummyCard>> hands,
  ) {
    final playersRaw = Map<String, dynamic>.from(map['players'] as Map);
    final players = <String, RummyPlayer>{};
    for (final entry in playersRaw.entries) {
      final hand = hands[entry.key] ?? [];
      players[entry.key] = RummyPlayer.fromMap(
        entry.key,
        Map<dynamic, dynamic>.from(entry.value as Map),
        hand,
      );
    }

    final openRaw = (map['openDeck'] as List?)?.cast<dynamic>() ?? [];
    final openDeck =
        openRaw.map((c) => RummyCard.fromMap(c as Map)).toList();

    final turnOrder = (map['turnOrder'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final scoresRaw = map['scores'] != null
        ? Map<String, dynamic>.from(map['scores'] as Map)
        : <String, dynamic>{};
    final scores = scoresRaw.map((k, v) => MapEntry(k, (v as num).toInt()));

    final sessionRaw = map['sessionScores'] != null
        ? Map<String, dynamic>.from(map['sessionScores'] as Map)
        : <String, dynamic>{};
    final sessionScores = sessionRaw.map((k, v) => MapEntry(k, (v as num).toInt()));

    return RummyGameState(
      roomId: roomId,
      phase: rummyPhaseFromString(map['phase'] as String? ?? 'draw'),
      currentTurn: map['currentTurn'] as String? ?? '',
      turnOrder: turnOrder,
      wildJoker: RummyCard.fromMap(map['wildJoker'] as Map),
      openDeck: openDeck,
      closedDeckCount: (map['closedDeckCount'] as num?)?.toInt() ?? 0,
      players: players,
      winnerId: map['winnerId'] as String?,
      scores: scores,
      sessionScores: sessionScores,
      targetScore: (map['targetScore'] as num?)?.toInt() ?? 0,
      round: (map['round'] as num?)?.toInt() ?? 1,
      sessionOver: (map['sessionOver'] as bool?) ?? false,
      sessionWinnerId: map['sessionWinnerId'] as String?,
    );
  }
}

// ── Suit helpers (for hand grouping) ─────────────────────────────────────────

extension RummyCardSuit on RummyCard {
  /// Map to existing Suit enum for colour/grouping reuse
  Suit? get asSuit => isPrintedJoker
      ? null
      : switch (suit) {
          0 => Suit.spades,
          1 => Suit.hearts,
          2 => Suit.diamonds,
          3 => Suit.clubs,
          _ => null,
        };
}
