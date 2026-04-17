import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/game_state.dart';
import '../models/player_model.dart';
import '../models/card_model.dart';
import 'firebase_service.dart';

// ── Difficulty ───────────────────────────────────────────────────────────────
// Randomly assigned between medium and hard — not user-selectable.

enum BotDifficulty { medium, hard }

const _botNames = [
  // Indian
  'Arjun', 'Priya', 'Rahul', 'Ananya',
  'Vikram', 'Sneha', 'Karthik', 'Divya',
  'Rohan', 'Meera', 'Aditya', 'Kavya',
  'Siddharth', 'Pooja', 'Nikhil', 'Isha',
  'Abhishek', 'Shreya', 'Varun', 'Riya',
  'Akash', 'Nisha', 'Manish', 'Tanvi',
  'Gaurav', 'Simran', 'Kunal', 'Deepa',
  'Ajay', 'Kritika', 'Yash', 'Sonali',
  // Non-Indian
  'Alex', 'Emma', 'Jake', 'Olivia',
  'Liam', 'Sophia', 'Noah', 'Ava',
  'Ethan', 'Mia', 'Mason', 'Chloe',
  'Logan', 'Zoe', 'Lucas', 'Lily',
  'Ryan', 'Natalie', 'Dylan', 'Hannah',
  'Jordan', 'Kayla', 'Chase', 'Amber',
  'Max', 'Jade', 'Sam', 'Brooke',
];

// ── Game Phase ───────────────────────────────────────────────────────────────

enum _Phase { early, mid, late }

// ── Game Memory ──────────────────────────────────────────────────────────────

class _GameMemory {
  final Set<String> _gone = {};
  final Map<String, Set<int>> _voids = {};
  final Map<int, int> _suitGoneCount = {};

  void reset() {
    _gone.clear();
    _voids.clear();
    _suitGoneCount.clear();
  }

  void markGone(PlayingCard card) {
    _gone.add(_k(card));
    _suitGoneCount[card.suit.index] = (_suitGoneCount[card.suit.index] ?? 0) + 1;
  }

  void recordCut(String playerId, int leadSuitIndex) =>
      _voids.putIfAbsent(playerId, () => {}).add(leadSuitIndex);

  bool isVoidIn(String playerId, int suitIndex) =>
      _voids[playerId]?.contains(suitIndex) ?? false;

  int goneCount(int suitIndex) => _suitGoneCount[suitIndex] ?? 0;

  /// Danger score for holding a card of this suit (0–1).
  /// Higher = more cards gone = fewer followers = high vettu risk.
  double suitDanger(int suitIndex) => goneCount(suitIndex) / 13.0;

  int? highestLiveRank(int suitIndex) {
    for (int r = 12; r >= 0; r--) {
      if (!_gone.contains('${suitIndex}_$r')) return r;
    }
    return null;
  }

  bool isTopCard(PlayingCard card) {
    final top = highestLiveRank(card.suit.index);
    return top == null || card.rank.index >= top;
  }

  int knownVoidCount(Iterable<String> opponentIds, int suitIndex) =>
      opponentIds.where((id) => isVoidIn(id, suitIndex)).length;

  String _k(PlayingCard c) => '${c.suit.index}_${c.rank.index}';
}

// ── Bot Service ──────────────────────────────────────────────────────────────

class BotService {
  static final BotService _instance = BotService._();
  static BotService get instance => _instance;
  BotService._();

  final _random = Random();
  final _timers = <String, Timer>{};
  final _acting = <String>{};
  final _memory = _GameMemory();
  StreamSubscription<GameState?>? _stateSubscription;
  String? _roomId;
  GameState? _lastState;

  BotDifficulty _difficulty = BotDifficulty.medium;

  // ── Public API ───────────────────────────────────────────────

  Future<void> addBots(GameState state, int count, {List<String>? names}) async {
    final db = FirebaseDatabase.instance;
    final roomRef = db.ref('rooms/${state.roomId}');
    final List<String> availableNames;
    if (names != null && names.length >= count) {
      availableNames = names;
    } else {
      final usedNames = state.players.values.map((p) => p.name).toSet();
      availableNames =
          _botNames.where((n) => !usedNames.contains(n)).toList()
            ..shuffle(_random);
    }

    final newOrder = List<String>.from(state.playerOrder);

    for (int i = 0; i < count && i < availableNames.length; i++) {
      final botId = 'bot_${DateTime.now().millisecondsSinceEpoch}_$i';
      final bot = Player(id: botId, name: availableNames[i], isBot: true);
      await roomRef.child('players/$botId').set(bot.toMap());
      newOrder.add(botId);
    }

    await roomRef.child('playerOrder').set(newOrder);
  }

  /// Randomly assigns medium or hard difficulty — not user-configurable.
  void start(String roomId) {
    _roomId = roomId;
    _difficulty = _random.nextBool() ? BotDifficulty.medium : BotDifficulty.hard;
    _memory.reset();
    _stateSubscription?.cancel();
    _stateSubscription =
        FirebaseService.instance.roomStream(roomId).listen(_onStateChanged);
    _log('started with difficulty=${_difficulty.name}');
  }

  void stop() {
    _cancelAllTimers();
    _stateSubscription?.cancel();
    _stateSubscription = null;
    _acting.clear();
    _lastState = null;
    _roomId = null;
    _memory.reset();
  }

  bool get isRunning => _roomId != null;

  // ── Delay by difficulty ──────────────────────────────────────

  Duration _thinkTime() => switch (_difficulty) {
        BotDifficulty.medium => Duration(milliseconds: 800 + _random.nextInt(2200)),  // 0.8–3s  feels human
        BotDifficulty.hard   => Duration(milliseconds: 2500 + _random.nextInt(2500)), // 2.5–5s  feels calculating
      };

  // ── State handler ────────────────────────────────────────────

  void _onStateChanged(GameState? state) {
    if (state == null) { stop(); return; }

    final prev = _lastState;
    if (prev != null && state.roundNumber != prev.roundNumber) {
      _log('Round ${state.roundNumber} started — resetting card memory');
      _memory.reset();
    }

    _syncVoidsFromTrick(state);
    _maybePurgeTrick(state);

    _lastState = state;

    if (state.phase == GamePhase.playing) {
      _maybeActForCurrentBot(state);
    } else if (state.phase == GamePhase.trickEnd) {
      _scheduleTrickStart(state);
    } else if (state.phase == GamePhase.gameOver ||
        state.phase == GamePhase.waiting) {
      stop();
    }
  }

  void _log(String msg) => debugPrint('[BotService] $msg');

  void _syncVoidsFromTrick(GameState state) {
    final leadSuit = state.currentSuit;
    if (leadSuit == null) return;
    if (state.playedCards.isEmpty) return;
    for (final entry in state.playedCards.entries) {
      if (entry.value.suit.index != leadSuit) {
        _memory.recordCut(entry.key, leadSuit);
      }
    }
  }

  void _maybePurgeTrick(GameState state) {
    final prev = _lastState;
    if (prev == null) return;
    if (state.phase != GamePhase.trickEnd) return;
    if (prev.phase == GamePhase.trickEnd) return;

    final leadSuit = state.currentSuit;
    if (leadSuit == null) return;

    for (final entry in state.playedCards.entries) {
      if (entry.value.suit.index != leadSuit) {
        _memory.recordCut(entry.key, leadSuit);
      }
    }

    final hasCut = state.playedCards.values.any((c) => c.suit.index != leadSuit);
    if (!hasCut) {
      for (final card in state.playedCards.values) {
        _memory.markGone(card);
      }
    }
  }

  // ── Bot turn logic ───────────────────────────────────────────

  void _maybeActForCurrentBot(GameState state) {
    final currentTurn = state.currentTurn;
    if (currentTurn == null) return;
    if (state.players[currentTurn]?.isBot != true) return;
    if (_acting.contains(currentTurn)) return;
    if (_timers[currentTurn]?.isActive == true) return;

    _timers[currentTurn] = Timer(_thinkTime(), () => _botTakeTurn(currentTurn));
  }

  Future<void> _botTakeTurn(String botId) async {
    _timers.remove(botId);
    if (_acting.contains(botId)) return;

    final state = _lastState;
    if (state == null || state.phase != GamePhase.playing) return;
    if (state.currentTurn != botId) return;

    // Fetch fresh state — stale _lastState may not include pickup cards.
    final freshState = await FirebaseService.instance.getFreshState(state.roomId);
    if (freshState == null || freshState.phase != GamePhase.playing) return;
    if (freshState.currentTurn != botId) return;

    final bot = freshState.players[botId];
    if (bot == null || bot.isEliminated || bot.hand.isEmpty) return;

    _acting.add(botId);
    try {
      final cardIndex = _chooseCard(bot, freshState);
      if (cardIndex >= bot.hand.length) return;
      await FirebaseService.instance.playCard(
        state: freshState,
        playerId: botId,
        cardIndex: cardIndex,
      );
    } catch (_) {
      _timers[botId] = Timer(const Duration(seconds: 1), () => _botTakeTurn(botId));
    } finally {
      _acting.remove(botId);
    }
  }

  // ── Difficulty dispatch ──────────────────────────────────────

  int _chooseCard(Player bot, GameState state) => switch (_difficulty) {
        BotDifficulty.medium => _chooseMedium(bot, state),
        BotDifficulty.hard   => _chooseHard(bot, state),
      };

  // ── Game phase ───────────────────────────────────────────────
  //
  // Based on average cards remaining across active players.
  // Early: >8 cards avg  |  Mid: 4–8  |  Late: <4

  _Phase _gamePhase(GameState state) {
    final active = state.activePlayers.where((p) => p.hand.isNotEmpty).toList();
    if (active.isEmpty) return _Phase.late;
    final avg = active.map((p) => p.hand.length).reduce((a, b) => a + b) / active.length;
    if (avg > 8) return _Phase.early;
    if (avg > 4) return _Phase.mid;
    return _Phase.late;
  }

  // ── MEDIUM: phase-aware, limited memory ──────────────────────
  //
  // Early:  dump high cards when leading (low vettu risk).
  // Mid/Late: play the lowest card to stay safe.
  // Follow: always stay below the table high if possible.
  // Cut:    dump the highest-rank card (vettu is a weapon).

  int _chooseMedium(Player bot, GameState state) {
    final hand = bot.hand;
    final phase = _gamePhase(state);
    final opponentIds = state.activePlayers
        .where((p) => p.id != bot.id && p.hand.isNotEmpty)
        .map((p) => p.id)
        .toList();

    // ── Leading ──────────────────────────────────────────────────
    if (state.currentSuit == null) {
      if (phase == _Phase.early) {
        // Dump Aces/Kings first — but only in suits where nobody is known void.
        // Leading into a known void means the bot picks up its own card back
        // (it holds the highest lead-suit card), causing an infinite loop.
        int bestIdx = -1;
        int bestRank = -1;
        for (int i = 0; i < hand.length; i++) {
          final card = hand[i];
          if (_memory.knownVoidCount(opponentIds, card.suit.index) == 0 &&
              card.rank.index > bestRank) {
            bestRank = card.rank.index;
            bestIdx = i;
          }
        }
        if (bestIdx >= 0) return bestIdx;
        // All suits have known voids — fall through to safe default below.
      }
      // Mid/Late (or early with all suits voided):
      // Play the lowest card in the suit with the FEWEST known voids.
      // Never just play the globally-lowest card — that card might be in the
      // worst suit (all opponents void), causing a guaranteed self-pickup loop.
      int fewestVoids = opponentIds.length + 1;
      for (int i = 0; i < hand.length; i++) {
        final v = _memory.knownVoidCount(opponentIds, hand[i].suit.index);
        if (v < fewestVoids) fewestVoids = v;
      }
      // Among cards in the safest suit(s), play the lowest rank.
      int bestIdx = 0;
      int bestRank = hand[0].rank.index + 1; // start high
      for (int i = 0; i < hand.length; i++) {
        final v = _memory.knownVoidCount(opponentIds, hand[i].suit.index);
        if (v == fewestVoids && hand[i].rank.index < bestRank) {
          bestRank = hand[i].rank.index;
          bestIdx = i;
        }
      }
      return bestIdx;
    }

    final suit = state.currentSuit!;
    final matching = [for (int i = 0; i < hand.length; i++) if (hand[i].suit.index == suit) i];

    // ── Following suit ───────────────────────────────────────────
    if (matching.isNotEmpty) {
      int tableHigh = -1;
      for (final played in state.playedCards.values) {
        if (played.suit.index == suit && played.rank.index > tableHigh) {
          tableHigh = played.rank.index;
        }
      }

      // Try to play a card safely under the table high.
      final safe = matching.where((i) => hand[i].rank.index < tableHigh).toList();
      if (safe.isNotEmpty) {
        if (phase == _Phase.early) {
          // Early: use highest safe card — dump big cards while protected.
          safe.sort((a, b) => hand[b].rank.index.compareTo(hand[a].rank.index));
        } else {
          // Mid/Late: use lowest safe card — stay as low as possible.
          safe.sort((a, b) => hand[a].rank.index.compareTo(hand[b].rank.index));
        }
        return safe.first;
      }

      // Forced to potentially be top card — play lowest to minimise damage.
      matching.sort((a, b) => hand[a].rank.index.compareTo(hand[b].rank.index));
      return matching.first;
    }

    // ── Cutting (vettu) ──────────────────────────────────────────
    // Dump highest-rank card — free chance to clean your hand.
    return hand.indexed
        .reduce((a, b) => a.$2.rank.index > b.$2.rank.index ? a : b)
        .$1;
  }

  // ── HARD: full memory + phase + suit targeting ────────────────
  //
  // Early:  aggressively dump Aces/Kings in safe suits (no known voids).
  //         Run same suit if holding 3+ to drain opponents.
  // Mid:    lead suits where the THREAT (fewest cards) is NOT void
  //         but at least one other player IS void → force a pickup on the threat.
  // Late:   never be highest on table. Play the lowest possible.
  // Follow: play highest safe card early, lowest safe card mid/late.
  //         If forced to be top, play absolute lowest to minimise pickup pile.
  // Cut:    dump the most dangerous card (high rank + top-card status + suit danger).

  int _chooseHard(Player bot, GameState state) {
    if (state.currentSuit == null) return _leadCard(bot, state);

    final suit = state.currentSuit!;
    final matching = [for (int i = 0; i < bot.hand.length; i++) if (bot.hand[i].suit.index == suit) i];

    if (matching.isNotEmpty) return _followCard(bot, state, matching, suit);
    return _cutCard(bot, state);
  }

  int _leadCard(Player bot, GameState state) {
    final hand = bot.hand;
    final phase = _gamePhase(state);
    final opponents = state.activePlayers.where((p) => p.id != bot.id && p.hand.isNotEmpty).toList();
    final opponentIds = opponents.map((p) => p.id).toList();

    // The threat: opponent closest to winning (fewest cards).
    final threat = opponents.isEmpty
        ? null
        : opponents.reduce((a, b) => a.hand.length < b.hand.length ? a : b);

    _log('${bot.name} LEADING [${phase.name}] — threat=${threat?.name} (${threat?.hand.length} cards)');

    // ── Early: dump high cards in suits with no known voids ──────
    if (phase == _Phase.early) {
      int bestIdx = -1;
      int bestRank = -1;
      for (int i = 0; i < hand.length; i++) {
        final card = hand[i];
        final voids = _memory.knownVoidCount(opponentIds, card.suit.index);
        if (voids == 0 && card.rank.index > bestRank) {
          bestRank = card.rank.index;
          bestIdx = i;
        }
      }
      if (bestIdx >= 0) {
        _log('${bot.name} EARLY: dumping ${hand[bestIdx].rank.name} (no known voids)');
        return bestIdx;
      }
      // All suits have known voids — fall through to safe default.
    }

    // ── Suit run: if holding 3+ of a suit with no voids, drain it ─
    // Leading the same suit repeatedly exhausts opponents' holdings
    // while safely reducing the bot's hand.
    if (phase != _Phase.late) {
      final suitCounts = <int, List<int>>{};
      for (int i = 0; i < hand.length; i++) {
        suitCounts.putIfAbsent(hand[i].suit.index, () => []).add(i);
      }
      for (final entry in suitCounts.entries) {
        final s = entry.key;
        final indices = entry.value;
        if (indices.length >= 3 && _memory.knownVoidCount(opponentIds, s) == 0) {
          // Lead the lowest of the run to minimise pickup risk.
          indices.sort((a, b) => hand[a].rank.index.compareTo(hand[b].rank.index));
          _log('${bot.name} SUIT RUN: leading ${Suit.values[s].name} (${indices.length} cards)');
          return indices.first;
        }
      }
    }

    // ── Mid/Late: force a pickup on the threat ───────────────────
    // Find a suit where:
    //   • the threat is NOT known void (they likely have it, possibly high)
    //   • at least one OTHER opponent IS void (they will cut)
    // Lead that suit → cutter cuts → threat picks up if holding a high card.
    if (threat != null && phase != _Phase.early) {
      for (int s = 0; s < 4; s++) {
        if (_memory.isVoidIn(threat.id, s)) continue; // threat will cut, not pick up
        final otherCutters = opponentIds
            .where((id) => id != threat.id && _memory.isVoidIn(id, s))
            .length;
        if (otherCutters == 0) continue; // nobody will cut
        final ofSuit = [for (int i = 0; i < hand.length; i++) if (hand[i].suit.index == s) i];
        if (ofSuit.isNotEmpty) {
          ofSuit.sort((a, b) => hand[a].rank.index.compareTo(hand[b].rank.index));
          _log('${bot.name} TARGETING ${threat.name} — lead ${Suit.values[s].name}, cutter will cut');
          return ofSuit.first;
        }
      }
    }

    // ── Default: score each card, pick the safest lead ───────────
    // Lower score = safer to lead.
    int bestIdx = 0;
    double bestScore = double.infinity;

    for (int i = 0; i < hand.length; i++) {
      final card = hand[i];
      final s = card.suit.index;
      final topPenalty = _memory.isTopCard(card) ? 30.0 : 0.0;
      final voids = _memory.knownVoidCount(opponentIds, s);
      final voidRisk = voids * 10.0;
      final dangerRisk = _memory.suitDanger(s) * 20.0;

      // Guaranteed-pickup penalty: if this card is the top card of its suit
      // AND all active opponents are known void, leading it means 100% pickup.
      // Make this essentially unplayable unless there is truly no better option.
      final guaranteedPickup = _memory.isTopCard(card) &&
          opponentIds.isNotEmpty &&
          voids >= opponentIds.length;
      final pickupPenalty = guaranteedPickup ? 200.0 : 0.0;

      // Late: prefer low rank (stay safe). Early/Mid: prefer high rank (dump big cards).
      final rankBase = phase == _Phase.late
          ? (12 - card.rank.index).toDouble()
          : card.rank.index.toDouble();
      final score = rankBase + topPenalty + voidRisk + dangerRisk + pickupPenalty;

      if (score < bestScore) { bestScore = score; bestIdx = i; }
    }

    _log('${bot.name} DEFAULT LEAD: ${hand[bestIdx].rank.name} of ${hand[bestIdx].suit.name}');
    return bestIdx;
  }

  int _followCard(Player bot, GameState state, List<int> matching, int leadSuit) {
    final hand = bot.hand;
    final phase = _gamePhase(state);

    int tableHigh = -1;
    for (final played in state.playedCards.values) {
      if (played.suit.index == leadSuit && played.rank.index > tableHigh) {
        tableHigh = played.rank.index;
      }
    }

    // Safe cards: below the current table high.
    final safe = matching.where((i) => hand[i].rank.index < tableHigh).toList();

    if (safe.isNotEmpty) {
      if (phase == _Phase.early) {
        // Early: use highest safe card — dump big cards while still protected.
        safe.sort((a, b) => hand[b].rank.index.compareTo(hand[a].rank.index));
      } else {
        // Mid/Late: use lowest safe card — stay as low as possible.
        safe.sort((a, b) => hand[a].rank.index.compareTo(hand[b].rank.index));
      }
      return safe.first;
    }

    // No safe card — we WILL be the highest lead-suit player.
    // Check if pickup is inevitable: are all players still to play void in this suit?
    // If so, nobody else will follow, and we will pick up regardless of which card
    // we play. In that case, dump the HIGHEST matching card to minimise hand danger.
    final playedIds = state.playedCards.keys.toSet();
    final stillToPlay = state.playerOrder.where((id) {
      if (id == bot.id) return false;
      if (playedIds.contains(id)) return false;
      final p = state.players[id];
      return p != null && !p.isEliminated && p.hand.isNotEmpty;
    }).toList();

    final allRemainingVoid = stillToPlay.isNotEmpty &&
        stillToPlay.every((id) => _memory.isVoidIn(id, leadSuit));

    final sorted = List<int>.from(matching);
    if (allRemainingVoid) {
      // Pickup is unavoidable — dump highest to get rid of the most dangerous card.
      sorted.sort((a, b) => hand[b].rank.index.compareTo(hand[a].rank.index));
      _log('${bot.name} FORCED PICKUP — dumping highest ${hand[sorted.first].rank.name}♠ (all others void)');
    } else {
      // Minimise pickup pile by playing lowest.
      sorted.sort((a, b) => hand[a].rank.index.compareTo(hand[b].rank.index));
    }
    return sorted.first;
  }

  int _cutCard(Player bot, GameState state) {
    final hand = bot.hand;
    // Tier 1 (priority 100–112): top cards — will definitely pick up if that
    //   suit is led, so dump the highest-rank one first.
    // Tier 0 (priority 0–12): non-top cards — dump highest rank.
    // Using integer tiers prevents the old float formula's side effect where a
    // low-rank top card (e.g. 9♥ after all higher hearts gone) could outscore
    // a high-rank non-top card (e.g. Q♣), making the bot visibly dump small
    // cards while holding large ones.
    int bestIdx = 0;
    int bestPriority = -1;

    for (int i = 0; i < hand.length; i++) {
      final card = hand[i];
      final priority = (_memory.isTopCard(card) ? 100 : 0) + card.rank.index;
      if (priority > bestPriority) { bestPriority = priority; bestIdx = i; }
    }

    _log('${bot.name} CUTTING with ${hand[bestIdx].rank.name} of ${hand[bestIdx].suit.name}');
    return bestIdx;
  }

  // ── Trick start ──────────────────────────────────────────────

  void _scheduleTrickStart(GameState state) {
    if (state.donkeyId != null) return;
    if (!_hasBots(state)) return;
    if (_timers['trickStart']?.isActive == true) return;

    _timers['trickStart'] = Timer(const Duration(seconds: 2), () async {
      _timers.remove('trickStart');
      final s = _lastState;
      if (s != null && s.phase == GamePhase.trickEnd && s.donkeyId == null) {
        await FirebaseService.instance.startNextTrick(s);
      }
    });
  }

  bool _hasBots(GameState state) => state.players.values.any((p) => p.isBot);

  void _cancelAllTimers() {
    for (final t in _timers.values) { t.cancel(); }
    _timers.clear();
  }
}
