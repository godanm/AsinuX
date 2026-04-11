import 'dart:math';
import '../models/card_model.dart';
import '../models/player_model.dart';

class GameLogic {
  static List<PlayingCard> buildFullDeck() {
    final cards = <PlayingCard>[];
    for (final suit in Suit.values) {
      for (final rank in Rank.values) {
        cards.add(PlayingCard(rank: rank, suit: suit));
      }
    }
    return cards..shuffle(Random());
  }

  /// Deal all 52 cards evenly (13 each) to 4 players.
  /// Returns dealt players and who holds the Ace of Spades.
  static ({Map<String, Player> players, String aceOfSpadesHolder})
      dealCards(List<String> playerIds) {
    final deck = buildFullDeck();
    final cardsPerPlayer = deck.length ~/ playerIds.length;
    final updatedPlayers = <String, Player>{};
    String? aceHolder;

    for (int i = 0; i < playerIds.length; i++) {
      final hand = deck.sublist(
        i * cardsPerPlayer,
        (i + 1) * cardsPerPlayer,
      );
      updatedPlayers[playerIds[i]] = Player(
        id: playerIds[i],
        name: '',
        hand: hand,
      );
      if (hand.any((c) => c.suit == Suit.spades && c.rank == Rank.ace)) {
        aceHolder = playerIds[i];
      }
    }

    return (players: updatedPlayers, aceOfSpadesHolder: aceHolder!);
  }

  /// Resolve a completed trick.
  ///
  /// If all players followed the lead suit → highest card wins (normal).
  /// If any player cut (different suit) → highest lead-suit card player
  /// picks up ALL cards on the table.
  static ({String? winnerId, bool hasCut, String? pickupId}) resolveTrick(
    Map<String, PlayingCard> playedCards,
    int leadSuit,
    List<String> playerOrder,
  ) {
    final hasCut = playedCards.values.any((c) => c.suit.index != leadSuit);

    String? highestId;
    int? highestRank;
    for (final id in playerOrder) {
      final card = playedCards[id];
      if (card == null) continue;
      if (card.suit.index != leadSuit) continue;
      if (highestRank == null || card.rank.index > highestRank) {
        highestRank = card.rank.index;
        highestId = id;
      }
    }

    if (hasCut) {
      return (winnerId: null, hasCut: true, pickupId: highestId);
    } else {
      return (winnerId: highestId, hasCut: false, pickupId: null);
    }
  }

  /// Check if player has any card of [suit] in hand.
  static bool hasMatchingSuit(List<PlayingCard> hand, int suit) {
    return hand.any((c) => c.suit.index == suit);
  }

  /// Apply round result: the donkey is immediately eliminated.
  /// Last non-eliminated player standing wins the tournament.
  static ({Map<String, Player> players, String? tournamentWinnerId})
      applyRoundResult({
    required Map<String, Player> players,
    required String donkeyId,
    required List<String> finishOrder,
  }) {
    final updated = Map<String, Player>.from(players);

    // Donkey is eliminated immediately — no letter accumulation
    updated[donkeyId] = updated[donkeyId]!.copyWith(isEliminated: true);

    // First to escape this round gets a score point
    if (finishOrder.isNotEmpty) {
      final first = updated[finishOrder.first]!;
      updated[finishOrder.first] = first.copyWith(score: first.score + 1);
    }

    final remaining = updated.values.where((p) => !p.isEliminated).toList();
    final tournamentWinnerId =
        remaining.length == 1 ? remaining.first.id : null;

    return (players: updated, tournamentWinnerId: tournamentWinnerId);
  }

  static String generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return String.fromCharCodes(
      List.generate(6, (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
    );
  }
}
