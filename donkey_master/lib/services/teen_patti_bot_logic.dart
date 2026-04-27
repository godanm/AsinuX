import 'dart:math';
import '../models/card_model.dart';
import '../models/teen_patti_state.dart';

enum BotAction { fold, chaal, raise, requestSideshow }

class TeenPattiBotLogic {
  /// Decide the bot's next action given its hand and game state.
  /// Pass an empty [hand] for blind bots — they reason without card knowledge.
  static BotAction decide({
    required TeenPattiPlayer bot,
    required List<PlayingCard> hand,
    required TeenPattiState state,
    required Random rng,
  }) {
    final strength = hand.length == 3 ? _handStrength(hand) : _blindStrength(rng);
    final potPressure = (state.pot / state.potLimit).clamp(0.0, 1.0);

    // Very strong hand — mostly raise, sometimes just chaal to trap
    if (strength > 0.72) {
      return rng.nextDouble() < 0.45 ? BotAction.raise : BotAction.chaal;
    }

    // Strong hand — consider raising when pot pressure is low
    if (strength > 0.50) {
      if (potPressure < 0.4 && rng.nextDouble() < 0.25) return BotAction.raise;
      return BotAction.chaal;
    }

    // Mid-range hand — stay in, maybe sideshow if eligible
    if (strength > 0.28) {
      if (rng.nextDouble() < 0.12) return BotAction.requestSideshow;
      return BotAction.chaal;
    }

    // Weak hand — fold probability increases with pot pressure
    final foldChance = ((0.45 - strength) + potPressure * 0.15).clamp(0.05, 0.65);
    if (rng.nextDouble() < foldChance) return BotAction.fold;

    return BotAction.chaal;
  }

  /// Whether the bot should peek at its cards this turn.
  /// Bots go Seen once the pot has grown meaningfully, with some randomness
  /// so different bots reveal at different times.
  static bool shouldSeeCards({
    required TeenPattiPlayer bot,
    required TeenPattiState state,
    required Random rng,
  }) {
    if (!bot.isBlind) return false;
    // See once pot is 3× boot (simulates player curiosity under pressure)
    final potRatio = state.bootAmount > 0 ? state.pot / state.bootAmount : 0.0;
    return potRatio > 3.0 && rng.nextDouble() < 0.45;
  }

  // ── Hand strength 0.0 – 1.0 ───────────────────────────────────────────────

  static double _handStrength(List<PlayingCard> hand) {
    final result = evaluateHand(hand);
    final t = result.tiebreakers;
    switch (result.rank) {
      case HandRank.trail:
        // 0.88 – 1.00  (2-2-2 = 0.88, A-A-A = 1.00)
        return 0.88 + (t[0] / 12.0) * 0.12;
      case HandRank.pureSequence:
        // 0.74 – 0.87  (seqVal 2–14 mapped linearly)
        return 0.74 + ((t[0] - 2) / 12.0) * 0.13;
      case HandRank.sequence:
        // 0.60 – 0.72
        return 0.60 + ((t[0] - 2) / 12.0) * 0.12;
      case HandRank.color:
        // 0.44 – 0.58  (by top card rank)
        return 0.44 + (t[0] / 12.0) * 0.14;
      case HandRank.pair:
        // 0.22 – 0.42  (by pair rank)
        return 0.22 + (t[0] / 12.0) * 0.20;
      case HandRank.highCard:
        // 0.00 – 0.20  (by top card)
        return (t[0] / 12.0) * 0.20;
    }
  }

  /// Simulated strength for a bot that hasn't looked at its cards yet.
  /// Uses the statistical distribution of Teen Patti hands.
  static double _blindStrength(Random rng) {
    final v = rng.nextDouble();
    if (v < 0.0024) return 0.90; // trail
    if (v < 0.005)  return 0.80; // pure sequence
    if (v < 0.035)  return 0.65; // sequence
    if (v < 0.20)   return 0.50; // color
    if (v < 0.45)   return 0.32; // pair
    return 0.12;                  // high card
  }
}
