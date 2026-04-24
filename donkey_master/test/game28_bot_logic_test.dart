import 'package:flutter_test/flutter_test.dart';
import 'package:asinux/models/card_model.dart';
import 'package:asinux/models/game28_state.dart';
import 'package:asinux/services/game28_bot_logic.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

PlayingCard c(Rank r, Suit s) => PlayingCard(rank: r, suit: s);

// Team layout: p1(seat0,team0), p2(seat1,team1), p3(seat2,team0), p4(seat3,team1)
// p1 & p3 are partners (team 0); p2 & p4 are partners (team 1)
const p1 = 'p1', p2 = 'p2', p3 = 'p3', p4 = 'p4';

Map<String, Game28Player> fourPlayers({
  List<PlayingCard> p1Hand = const [],
  List<PlayingCard> p2Hand = const [],
  List<PlayingCard> p3Hand = const [],
  List<PlayingCard> p4Hand = const [],
}) =>
    {
      p1: Game28Player(id: p1, name: 'P1', seatIndex: 0, hand: p1Hand),
      p2: Game28Player(id: p2, name: 'P2', seatIndex: 1, hand: p2Hand),
      p3: Game28Player(id: p3, name: 'P3', seatIndex: 2, hand: p3Hand),
      p4: Game28Player(id: p4, name: 'P4', seatIndex: 3, hand: p4Hand),
    };

Game28State playingState({
  required List<PlayingCard> myHand,
  required Map<String, PlayingCard> trick,
  int? leadSuit,
  int? trumpSuit,
  bool trumpRevealed = false,
  bool trumpRevealRequired = false,
  String currentTurn = p1,
}) =>
    Game28State(
      roomId: 'test',
      roomCode: 'T',
      phase: Game28Phase.playing,
      players: fourPlayers(p1Hand: myHand),
      playerOrder: [p1, p2, p3, p4],
      currentTrick: trick,
      leadSuit: leadSuit,
      trumpSuit: trumpSuit,
      trumpRevealed: trumpRevealed,
      trumpRevealRequired: trumpRevealRequired,
      currentTurn: currentTurn,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── botHandStrength ─────────────────────────────────────────────────────────
  group('botHandStrength', () {
    test('empty hand → 0', () {
      expect(botHandStrength([]), 0);
    });

    test('all zero-point cards → 0', () {
      expect(
        botHandStrength([
          c(Rank.seven, Suit.spades),
          c(Rank.eight, Suit.hearts),
          c(Rank.king, Suit.diamonds),
          c(Rank.queen, Suit.clubs),
        ]),
        0,
      );
    });

    test('single Jack → 3', () {
      expect(botHandStrength([c(Rank.jack, Suit.hearts)]), 3);
    });

    test('single Nine → 2', () {
      expect(botHandStrength([c(Rank.nine, Suit.clubs)]), 2);
    });

    test('Ace → 1, Ten → 1', () {
      expect(botHandStrength([c(Rank.ace, Suit.spades), c(Rank.ten, Suit.hearts)]), 2);
    });

    test('J+9 same suit → 5 + 2 bonus = 7', () {
      expect(
        botHandStrength([
          c(Rank.jack, Suit.hearts),
          c(Rank.nine, Suit.hearts),
          c(Rank.seven, Suit.spades),
          c(Rank.eight, Suit.diamonds),
        ]),
        7,
      );
    });

    test('J+9 different suits → 5, no bonus', () {
      expect(
        botHandStrength([
          c(Rank.jack, Suit.hearts),
          c(Rank.nine, Suit.clubs),
          c(Rank.seven, Suit.spades),
          c(Rank.eight, Suit.diamonds),
        ]),
        5,
      );
    });

    test('J+9+A+10 same suit → 3+2+1+1 + 2 bonus = 9', () {
      expect(
        botHandStrength([
          c(Rank.jack, Suit.spades),
          c(Rank.nine, Suit.spades),
          c(Rank.ace, Suit.spades),
          c(Rank.ten, Suit.spades),
        ]),
        9,
      );
    });

    test('two J+9 pairs in different suits → 14 (5+5+2+2)', () {
      expect(
        botHandStrength([
          c(Rank.jack, Suit.hearts),
          c(Rank.nine, Suit.hearts),
          c(Rank.jack, Suit.spades),
          c(Rank.nine, Suit.spades),
        ]),
        14,
      );
    });
  });

  // ── botMaxBidForStrength ────────────────────────────────────────────────────
  group('botMaxBidForStrength', () {
    test('0 → 13 (pass)', () => expect(botMaxBidForStrength(0), 13));
    test('2 → 13 (below threshold)', () => expect(botMaxBidForStrength(2), 13));
    test('boundary 4 → 14', () => expect(botMaxBidForStrength(4), 14));
    test('5 → 15', () => expect(botMaxBidForStrength(5), 15));
    test('boundary 6 → 15', () => expect(botMaxBidForStrength(6), 15));
    test('7 → 17 (J+9 combo)', () => expect(botMaxBidForStrength(7), 17));
    test('boundary 8 → 17', () => expect(botMaxBidForStrength(8), 17));
    test('9 → 20', () => expect(botMaxBidForStrength(9), 20));
    test('boundary 10 → 20', () => expect(botMaxBidForStrength(10), 20));
    test('11 → 22', () => expect(botMaxBidForStrength(11), 22));
    test('15 → 22 (caps at 22)', () => expect(botMaxBidForStrength(15), 22));
  });

  // ── botChooseTrump ──────────────────────────────────────────────────────────
  group('botChooseTrump', () {
    test('all cards same suit → that suit', () {
      final hand = [
        c(Rank.jack, Suit.clubs),
        c(Rank.nine, Suit.clubs),
        c(Rank.ace, Suit.clubs),
        c(Rank.ten, Suit.clubs),
      ];
      expect(botChooseTrump(hand), Suit.clubs.index);
    });

    test('lone Jack beats zero-point short suits', () {
      final hand = [
        c(Rank.jack, Suit.hearts),
        c(Rank.seven, Suit.spades),
        c(Rank.eight, Suit.diamonds),
        c(Rank.queen, Suit.clubs),
      ];
      expect(botChooseTrump(hand), Suit.hearts.index);
    });

    test('4-card suit (7,8,K,Q) beats lone Jack in another suit via length bonus', () {
      // spades: 0+1+3+2 = 6 + 8 (length) = 14
      // clubs J: 3*2+7 = 13
      final hand = [
        c(Rank.seven, Suit.spades),
        c(Rank.eight, Suit.spades),
        c(Rank.king, Suit.spades),
        c(Rank.queen, Suit.spades),
        c(Rank.jack, Suit.clubs),
      ];
      expect(botChooseTrump(hand), Suit.spades.index);
    });

    test('3-card suit does NOT beat lone Jack', () {
      // hearts 7,8,K: 0+1+3 = 4 + 3 (length) = 7
      // clubs J: 13 → clubs wins
      final hand = [
        c(Rank.seven, Suit.hearts),
        c(Rank.eight, Suit.hearts),
        c(Rank.king, Suit.hearts),
        c(Rank.jack, Suit.clubs),
      ];
      expect(botChooseTrump(hand), Suit.clubs.index);
    });

    test('J+9 of same suit wins over lone J of another', () {
      // hearts J+9: (3*2+7)+(2*2+6) = 13+10 = 23
      // clubs J: 13
      final hand = [
        c(Rank.jack, Suit.hearts),
        c(Rank.nine, Suit.hearts),
        c(Rank.jack, Suit.clubs),
      ];
      expect(botChooseTrump(hand), Suit.hearts.index);
    });
  });

  // ── botShouldAskTrump ───────────────────────────────────────────────────────
  group('botShouldAskTrump', () {
    test('empty trick → false', () {
      final state = playingState(myHand: [], trick: {});
      expect(botShouldAskTrump(state), false);
    });

    test('trick has only K,Q,8,7 → false', () {
      final state = playingState(
        myHand: [],
        trick: {
          p2: c(Rank.king, Suit.spades),
          p3: c(Rank.queen, Suit.hearts),
        },
      );
      expect(botShouldAskTrump(state), false);
    });

    test('trick has Ace (pts=1) → true (threshold is ≥1)', () {
      final state = playingState(
        myHand: [],
        trick: {p2: c(Rank.ace, Suit.spades)},
      );
      expect(botShouldAskTrump(state), true);
    });

    test('trick has Ten (pts=1) → true', () {
      final state = playingState(
        myHand: [],
        trick: {p2: c(Rank.ten, Suit.clubs)},
      );
      expect(botShouldAskTrump(state), true);
    });

    test('trick has Jack (pts=3) → true', () {
      final state = playingState(
        myHand: [],
        trick: {p2: c(Rank.jack, Suit.spades)},
      );
      expect(botShouldAskTrump(state), true);
    });

    test('trick has Nine (pts=2) → true', () {
      final state = playingState(
        myHand: [],
        trick: {p2: c(Rank.nine, Suit.hearts)},
      );
      expect(botShouldAskTrump(state), true);
    });

    test('trick has J and K → true (J present)', () {
      final state = playingState(
        myHand: [],
        trick: {
          p2: c(Rank.jack, Suit.spades),
          p3: c(Rank.king, Suit.spades),
        },
      );
      expect(botShouldAskTrump(state), true);
    });
  });

  // ── botChooseCard ───────────────────────────────────────────────────────────
  group('botChooseCard — leading (empty trick)', () {
    test('holds J♥: leads small non-trump non-point card (7 or 8)', () {
      final hand = [
        c(Rank.jack, Suit.hearts),
        c(Rank.seven, Suit.spades),
        c(Rank.eight, Suit.diamonds),
      ];
      final state = playingState(myHand: hand, trick: {});
      final idx = botChooseCard(state, p1, hand, null);
      final chosen = hand[idx];
      // Should be 7♠ (smallest non-point non-trump non-J card)
      expect(chosen.rank, Rank.seven);
    });

    test('holds 9♣: leads smallest non-trump non-point card', () {
      final hand = [
        c(Rank.nine, Suit.clubs),
        c(Rank.king, Suit.hearts),
        c(Rank.eight, Suit.spades),
      ];
      final state = playingState(myHand: hand, trick: {});
      final idx = botChooseCard(state, p1, hand, null);
      // 9♣ is trump? No trump declared. Has high-power 9, so leads smallest non-point = 8♠
      expect(hand[idx].rank, Rank.eight);
    });

    test('no J/9: leads highest non-trump non-point card', () {
      final hand = [
        c(Rank.king, Suit.spades),
        c(Rank.queen, Suit.hearts),
        c(Rank.eight, Suit.clubs),
        c(Rank.seven, Suit.diamonds),
      ];
      final state = playingState(myHand: hand, trick: {});
      final idx = botChooseCard(state, p1, hand, null);
      expect(hand[idx].rank, Rank.king);
    });

    test('all trump cards: leads lowest trump', () {
      final hand = [
        c(Rank.jack, Suit.clubs),
        c(Rank.nine, Suit.clubs),
        c(Rank.seven, Suit.clubs),
      ];
      final state = playingState(myHand: hand, trick: {}, trumpSuit: Suit.clubs.index);
      final idx = botChooseCard(state, p1, hand, Suit.clubs.index);
      // All trump, fallback to lowest card = 7♣
      expect(hand[idx].rank, Rank.seven);
    });

    test('single card: always returns index 0', () {
      final hand = [c(Rank.ace, Suit.hearts)];
      final state = playingState(myHand: hand, trick: {});
      expect(botChooseCard(state, p1, hand, null), 0);
    });
  });

  group('botChooseCard — following lead suit (partner winning)', () {
    test('partner has J♠, bot has 9♠+7♠: throws 9♠ (safe point throw)', () {
      // p3 is p1's partner (both team 0); p3 played J♠
      final hand = [c(Rank.nine, Suit.spades), c(Rank.seven, Suit.spades)];
      final state = playingState(
        myHand: hand,
        trick: {p3: c(Rank.jack, Suit.spades)},
        leadSuit: Suit.spades.index,
        currentTurn: p1,
      );
      final idx = botChooseCard(state, p1, hand, null);
      expect(hand[idx].rank, Rank.nine); // 9 has pts=2, strength=6 < J strength=7 ✓
    });

    test('partner has J♠, bot has only 7♠ (no safe point): plays 7♠', () {
      final hand = [c(Rank.seven, Suit.spades)];
      final state = playingState(
        myHand: hand,
        trick: {p3: c(Rank.jack, Suit.spades)},
        leadSuit: Suit.spades.index,
      );
      expect(botChooseCard(state, p1, hand, null), 0);
    });

    test('partner has 9♠, bot has J♠+7♠: plays 7♠ (J would steal trick)', () {
      // J strength=7 > 9 strength=6, so J would steal the trick — excluded
      final hand = [c(Rank.jack, Suit.spades), c(Rank.seven, Suit.spades)];
      final state = playingState(
        myHand: hand,
        trick: {p3: c(Rank.nine, Suit.spades)},
        leadSuit: Suit.spades.index,
      );
      final idx = botChooseCard(state, p1, hand, null);
      expect(hand[idx].rank, Rank.seven);
    });

    test('partner winning with K♠ (0 pts): plays lowest card', () {
      final hand = [c(Rank.ace, Suit.spades), c(Rank.seven, Suit.spades)];
      final state = playingState(
        myHand: hand,
        trick: {p3: c(Rank.king, Suit.spades)},
        leadSuit: Suit.spades.index,
      );
      final idx = botChooseCard(state, p1, hand, null);
      expect(hand[idx].rank, Rank.seven); // conserve; K is 0pts so no high-value throw
    });
  });

  group('botChooseCard — following lead suit (opponent winning)', () {
    test('opponent has K♥, bot has A♥+7♥: plays A♥ (lowest that beats K)', () {
      // p2 is opponent of p1
      final hand = [c(Rank.ace, Suit.hearts), c(Rank.seven, Suit.hearts)];
      final state = playingState(
        myHand: hand,
        trick: {p2: c(Rank.king, Suit.hearts)},
        leadSuit: Suit.hearts.index,
      );
      final idx = botChooseCard(state, p1, hand, null);
      expect(hand[idx].rank, Rank.ace);
    });

    test('opponent has J♥ (unbeatable), bot has A♥+7♥: plays 7♥ (lowest)', () {
      final hand = [c(Rank.ace, Suit.hearts), c(Rank.seven, Suit.hearts)];
      final state = playingState(
        myHand: hand,
        trick: {p2: c(Rank.jack, Suit.hearts)},
        leadSuit: Suit.hearts.index,
      );
      final idx = botChooseCard(state, p1, hand, null);
      expect(hand[idx].rank, Rank.seven);
    });

    test('opponent has J♥, bot has only 9♥: must follow, plays 9♥', () {
      final hand = [c(Rank.nine, Suit.hearts)];
      final state = playingState(
        myHand: hand,
        trick: {p2: c(Rank.jack, Suit.hearts)},
        leadSuit: Suit.hearts.index,
      );
      expect(botChooseCard(state, p1, hand, null), 0);
    });

    test('opponent has 9♥ (str=6), bot has J♥+A♥+7♥: plays J♥ (only card > 9)', () {
      final hand = [
        c(Rank.jack, Suit.hearts),
        c(Rank.ace, Suit.hearts),
        c(Rank.seven, Suit.hearts),
      ];
      final state = playingState(
        myHand: hand,
        trick: {p2: c(Rank.nine, Suit.hearts)},
        leadSuit: Suit.hearts.index,
      );
      final idx = botChooseCard(state, p1, hand, null);
      expect(hand[idx].rank, Rank.jack);
    });

    test('opponent has A♥ (str=5), bot has J♥+10♥: plays 10♥ (lowest that beats A)', () {
      // J str=7 beats A str=5; 10 str=4 does NOT beat A. So only J beats A.
      final hand = [c(Rank.jack, Suit.hearts), c(Rank.ten, Suit.hearts)];
      final state = playingState(
        myHand: hand,
        trick: {p2: c(Rank.ace, Suit.hearts)},
        leadSuit: Suit.hearts.index,
      );
      final idx = botChooseCard(state, p1, hand, null);
      expect(hand[idx].rank, Rank.jack); // only J beats A
    });
  });

  group('botChooseCard — void in lead suit (discard)', () {
    test('partner has J♠ winning, bot has 9♥+7♣ (no trump): throws 9♥', () {
      // lead=spades, p3=partner winning with J♠, bot has non-spade non-trump cards
      final hand = [c(Rank.nine, Suit.hearts), c(Rank.seven, Suit.clubs)];
      final state = playingState(
        myHand: hand,
        trick: {
          p2: c(Rank.king, Suit.spades),
          p3: c(Rank.jack, Suit.spades),
        },
        leadSuit: Suit.spades.index,
        currentTurn: p1,
      );
      final idx = botChooseCard(state, p1, hand, null, shouldPlayTrumpWhenVoid: false);
      expect(hand[idx].rank, Rank.nine); // 9 = 2pts, highest non-trump point card
    });

    test('opponent has J♠ winning, bot has 9♥+7♣: throws 7♣ (safest)', () {
      final hand = [c(Rank.nine, Suit.hearts), c(Rank.seven, Suit.clubs)];
      final state = playingState(
        myHand: hand,
        trick: {p2: c(Rank.jack, Suit.spades)}, // p2 = opponent of p1
        leadSuit: Suit.spades.index,
      );
      final idx = botChooseCard(state, p1, hand, null, shouldPlayTrumpWhenVoid: false);
      expect(hand[idx].rank, Rank.seven); // safest discard
    });

    test('partner has K♠ winning (0 pts), bot has 9♥+7♣: throws 7♣ (not worth throwing pts)', () {
      final hand = [c(Rank.nine, Suit.hearts), c(Rank.seven, Suit.clubs)];
      final state = playingState(
        myHand: hand,
        trick: {p3: c(Rank.king, Suit.spades)},
        leadSuit: Suit.spades.index,
      );
      final idx = botChooseCard(state, p1, hand, null, shouldPlayTrumpWhenVoid: false);
      expect(hand[idx].rank, Rank.seven);
    });

    test('partner has 9♠ winning, bot has A♥+7♣: throws A♥ (1pt onto 2pt win)', () {
      final hand = [c(Rank.ace, Suit.hearts), c(Rank.seven, Suit.clubs)];
      final state = playingState(
        myHand: hand,
        trick: {p3: c(Rank.nine, Suit.spades)},
        leadSuit: Suit.spades.index,
      );
      final idx = botChooseCard(state, p1, hand, null, shouldPlayTrumpWhenVoid: false);
      expect(hand[idx].rank, Rank.ace);
    });

    test('void in lead, shouldPlayTrump=true, holds trump: plays highest trump', () {
      final hand = [
        c(Rank.nine, Suit.clubs),
        c(Rank.seven, Suit.clubs),
        c(Rank.eight, Suit.diamonds),
      ];
      final state = playingState(
        myHand: hand,
        trick: {p2: c(Rank.king, Suit.spades)},
        leadSuit: Suit.spades.index,
        trumpSuit: Suit.clubs.index,
        trumpRevealed: true,
      );
      final idx = botChooseCard(state, p1, hand, Suit.clubs.index,
          shouldPlayTrumpWhenVoid: true);
      expect(hand[idx].rank, Rank.nine); // 9♣ strongest trump
    });

    test('void in lead, shouldPlayTrump=false: discards safely instead', () {
      final hand = [
        c(Rank.nine, Suit.clubs),
        c(Rank.seven, Suit.diamonds),
      ];
      final state = playingState(
        myHand: hand,
        trick: {p2: c(Rank.king, Suit.spades)},
        leadSuit: Suit.spades.index,
        trumpSuit: Suit.clubs.index,
      );
      final idx = botChooseCard(state, p1, hand, Suit.clubs.index,
          shouldPlayTrumpWhenVoid: false);
      // Safest discard: non-trump non-point = 7♦
      expect(hand[idx].rank, Rank.seven);
    });
  });

  group('botChooseCard — trumpRevealRequired forced trump', () {
    test('void in lead, trumpRevealRequired=true, holds J♣+7♣: plays J♣ (highest trump)', () {
      final hand = [
        c(Rank.jack, Suit.clubs),
        c(Rank.seven, Suit.clubs),
      ];
      final state = playingState(
        myHand: hand,
        trick: {p2: c(Rank.king, Suit.spades)},
        leadSuit: Suit.spades.index,
        trumpSuit: Suit.clubs.index,
        trumpRevealed: true,
        trumpRevealRequired: true,
      );
      final idx = botChooseCard(state, p1, hand, Suit.clubs.index);
      expect(hand[idx].rank, Rank.jack);
    });

    test('has lead suit even with trumpRevealRequired: normal follow logic applies', () {
      // trumpRevealRequired but NOT void — follow lead suit normally
      final hand = [
        c(Rank.ace, Suit.spades),
        c(Rank.jack, Suit.clubs),
      ];
      final state = playingState(
        myHand: hand,
        trick: {p2: c(Rank.king, Suit.spades)},
        leadSuit: Suit.spades.index,
        trumpSuit: Suit.clubs.index,
        trumpRevealRequired: true,
      );
      final idx = botChooseCard(state, p1, hand, Suit.clubs.index);
      // Must follow spades → plays A♠ (only spade, also beats K)
      expect(hand[idx].suit, Suit.spades);
    });
  });

  group('botChooseCard — edge cases', () {
    test('single card in hand always returns index 0', () {
      final hand = [c(Rank.seven, Suit.hearts)];
      final state = playingState(
        myHand: hand,
        trick: {p2: c(Rank.king, Suit.hearts)},
        leadSuit: Suit.hearts.index,
      );
      expect(botChooseCard(state, p1, hand, null), 0);
    });

    test('partner A♥+7♠ in discard: A thrown (highest non-trump point) onto partner J', () {
      // partner has J♥, lead=hearts, bot void: has A♠ and 7♦
      final hand = [c(Rank.ace, Suit.spades), c(Rank.seven, Suit.diamonds)];
      final state = playingState(
        myHand: hand,
        trick: {p3: c(Rank.jack, Suit.hearts)},
        leadSuit: Suit.hearts.index,
      );
      final idx = botChooseCard(state, p1, hand, null, shouldPlayTrumpWhenVoid: false);
      expect(hand[idx].rank, Rank.ace);
    });

    test('leading with J♠ and trump=spades: J is trump, leads lowest card (fallback)', () {
      // All cards are trump (spades), so no non-trump non-point leads exist
      final hand = [
        c(Rank.jack, Suit.spades),
        c(Rank.nine, Suit.spades),
        c(Rank.seven, Suit.spades),
      ];
      final state = playingState(
        myHand: hand,
        trick: {},
        trumpSuit: Suit.spades.index,
      );
      final idx = botChooseCard(state, p1, hand, Suit.spades.index);
      expect(hand[idx].rank, Rank.seven); // fallback: lowest card
    });
  });
}
