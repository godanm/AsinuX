import 'card_model.dart';

class Player {
  final String id;
  final String name;
  final List<PlayingCard> hand;
  final bool isHost;
  final bool isBot;
  final bool isEliminated;
  final int finishPosition;
  final int score; // rounds survived safely (escaped first)

  const Player({
    required this.id,
    required this.name,
    this.hand = const [],
    this.isHost = false,
    this.isBot = false,
    this.isEliminated = false,
    this.finishPosition = 0,
    this.score = 0,
  });

  Player copyWith({
    String? name,
    List<PlayingCard>? hand,
    bool? isHost,
    bool? isBot,
    bool? isEliminated,
    int? finishPosition,
    int? score,
  }) {
    return Player(
      id: id,
      name: name ?? this.name,
      hand: hand ?? this.hand,
      isHost: isHost ?? this.isHost,
      isBot: isBot ?? this.isBot,
      isEliminated: isEliminated ?? this.isEliminated,
      finishPosition: finishPosition ?? this.finishPosition,
      score: score ?? this.score,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'hand': hand.map((c) => c.toMap()).toList(),
        'isHost': isHost,
        'isBot': isBot,
        'isEliminated': isEliminated,
        'finishPosition': finishPosition,
        'score': score,
      };

  factory Player.fromMap(String id, Map<dynamic, dynamic> map) => Player(
        id: id,
        name: map['name'] as String? ?? 'Player',
        hand: (map['hand'] as List<dynamic>? ?? [])
            .map((c) => PlayingCard.fromMap(c as Map<dynamic, dynamic>))
            .toList(),
        isHost: map['isHost'] as bool? ?? false,
        isBot: map['isBot'] as bool? ?? false,
        isEliminated: map['isEliminated'] as bool? ?? false,
        finishPosition: map['finishPosition'] as int? ?? 0,
        score: map['score'] as int? ?? 0,
      );
}
