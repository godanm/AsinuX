import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/game_state.dart';
import '../models/player_model.dart';
import '../models/card_model.dart';
import 'firebase_service.dart';

// ── Difficulty ───────────────────────────────────────────────────────────────

enum BotDifficulty { easy, medium, hard }

extension BotDifficultyLabel on BotDifficulty {
  String get label => switch (this) {
        BotDifficulty.easy => 'Easy',
        BotDifficulty.medium => 'Medium',
        BotDifficulty.hard => 'Hard',
      };

  String get description => switch (this) {
        BotDifficulty.easy => 'Plays randomly — great for beginners',
        BotDifficulty.medium => 'Follows suit & avoids obvious traps',
        BotDifficulty.hard => 'Tracks cards & reads who cuts what',
      };
}

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
  // Count of cards seen per suit (played onto the table)
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

  /// How many cards of this suit have gone "outside" (been played/discarded).
  /// 13 total per suit in a standard deck.
  int goneCount(int suitIndex) => _suitGoneCount[suitIndex] ?? 0;

  /// Danger score for holding a card of this suit (0–1).
  /// Higher = more cards gone = harder for others to follow suit = vettu risk.
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
  BotDifficulty get difficulty => _difficulty;

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

  void start(String roomId, {BotDifficulty difficulty = BotDifficulty.medium}) {
    _roomId = roomId;
    _difficulty = difficulty;
    _memory.reset();
    _stateSubscription?.cancel();
    _stateSubscription =
        FirebaseService.instance.roomStream(roomId).listen(_onStateChanged);
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
        // Easy: slow — 2–5s (feels human, but dumb)
        BotDifficulty.easy   => Duration(milliseconds: 2000 + _random.nextInt(3000)),
        // Medium: 1–4s
        BotDifficulty.medium => Duration(milliseconds: 1000 + _random.nextInt(3000)),
        // Hard: fast — 0.5–2s (sharp, decisive)
        BotDifficulty.hard   => Duration(milliseconds: 500 + _random.nextInt(1500)),
      };

  // ── State handler ────────────────────────────────────────────

  void _onStateChanged(GameState? state) {
    if (state == null) { stop(); return; }

    if (_difficulty != BotDifficulty.easy) {
      _syncVoidsFromTrick(state);
      _maybePurgeTrick(state);
    }

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
        final suitName = Suit.values[leadSuit].name;
        final cutSuitName = entry.value.suit.name;
        final playerName = state.players[entry.key]?.name ?? entry.key;
        _log('VOID recorded: $playerName cut $suitName with $cutSuitName '
            '(trick ${state.trickNumber})');
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
    _log('TRICK END — currentSuit=$leadSuit playedCards=${state.playedCards.length}');

    if (leadSuit == null) {
      _log('WARNING: currentSuit is null at trickEnd');
      return;
    }

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

    final bot = state.players[botId];
    if (bot == null || bot.isEliminated || bot.hand.isEmpty) return;

    _acting.add(botId);
    try {
      final cardIndex = _chooseCard(bot, state);
      if (cardIndex >= bot.hand.length) return;
      await FirebaseService.instance.playCard(
        state: state,
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
        BotDifficulty.easy   => _chooseEasy(bot, state),
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

  // ── EASY: pure random ────────────────────────────────────────

  int _chooseEasy(Player bot, GameState state) {
    final hand = bot.hand;
    if (state.currentSuit == null) return _random.nextInt(hand.length);
    final suit = state.currentSuit!;
    final matching = [for (int i = 0; i < hand.length; i++) if (hand[i].suit.index == suit) i];
    if (matching.isNotEmpty) return matching[_random.nextInt(matching.length)];
    return _random.nextInt(hand.length);
  }

  // ── MEDIUM: phase-aware, no memory ───────────────────────────
  //
  // Early: dump highest cards when leading.
  // Late: play under the table, never be highest unless forced.
  // Cut: dump highest danger card.

  int _chooseMedium(Player bot, GameState state) {
    final hand = bot.hand;
    final phase = _gamePhase(state);

    if (state.currentSuit == null) {
      // Leading
      if (phase == _Phase.early) {
        // Early: dump highest card (A, K, Q) — low vettu risk
        return hand.indexed
            .reduce((a, b) => a.$2.rank.index > b.$2.rank.index ? a : b)
            .$1;
      } else {
        // Mid/Late: play lowest card — stay under the radar
        return hand.indexed
            .reduce((a, b) => a.$2.rank.index < b.$2.rank.index ? a : b)
            .$1;
      }
    }

    final suit = state.currentSuit!;
    final matching = [for (int i = 0; i < hand.length; i++) if (hand[i].suit.index == suit) i];

    if (matching.isNotEmpty) {
      int tableHigh = -1;
      for (final played in state.playedCards.values) {
        if (played.suit.index == suit && played.rank.index > tableHigh) {
          tableHigh = played.rank.index;
        }
      }
      // Late game: always try to play under — never be top card
      final safe = matching.where((i) => hand[i].rank.index < tableHigh).toList();
      if (safe.isNotEmpty) {
        // Play highest safe card (use up big cards while staying below table high)
        safe.sort((a, b) => hand[b].rank.index.compareTo(hand[a].rank.index));
        return safe.first;
      }
      // Forced to play — go lowest
      matching.sort((a, b) => hand[a].rank.index.compareTo(hand[b].rank.index));
      return matching.first;
    }

    // Cutting — dump highest rank (vettu is a weapon, clean your hand)
    return hand.indexed
        .reduce((a, b) => a.$2.rank.index > b.$2.rank.index ? a : b)
        .$1;
  }

  // ── HARD: full memory + phase + targeting ─────────────────────
  //
  // Early:  aggressively dump Aces/Kings when leading.
  // Mid:    track voids, lead depleted suits to target the player
  //         closest to winning (fewest cards).
  // Late:   never be highest on table. Play under everyone.
  // Cut:    dump highest danger card into the pile.
  // Vettu target: always aim at the player with fewest cards.

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

    // ── Target: the opponent closest to winning (fewest cards) ──
    // We want to force a vettu onto them.
    final target = opponents.isEmpty
        ? null
        : opponents.reduce((a, b) => a.hand.length < b.hand.length ? a : b);

    _log('${bot.name} LEADING [${phase.name}] — target=${target?.name} (${target?.hand.length} cards)');

    // ── Early game: dump high cards aggressively ─────────────────
    if (phase == _Phase.early) {
      // Pick highest card in a suit where NO opponent is void
      // (safe to play high — everyone can follow)
      int bestIdx = 0;
      int bestRank = -1;
      for (int i = 0; i < hand.length; i++) {
        final card = hand[i];
        final voids = _memory.knownVoidCount(opponentIds, card.suit.index);
        if (voids == 0 && card.rank.index > bestRank) {
          bestRank = card.rank.index;
          bestIdx = i;
        }
      }
      // If all suits have known voids, fall through to safe lead
      if (bestRank >= 0) {
        _log('${bot.name} EARLY: dumping high card ${hand[bestIdx].rank.name}');
        return bestIdx;
      }
    }

    // ── Mid/Late: target the leader with a depleted suit ─────────
    // If we know the target is void in a suit, lead that suit to force a vettu on them.
    if (target != null && phase != _Phase.early) {
      for (int s = 0; s < 4; s++) {
        if (_memory.isVoidIn(target.id, s)) {
          // Find lowest card of this suit in hand to lead — low card, big damage
          final ofSuit = [for (int i = 0; i < hand.length; i++) if (hand[i].suit.index == s) i];
          if (ofSuit.isNotEmpty) {
            ofSuit.sort((a, b) => hand[a].rank.index.compareTo(hand[b].rank.index));
            _log('${bot.name} TARGETING ${target.name} with depleted suit ${Suit.values[s].name}');
            return ofSuit.first;
          }
        }
      }
    }

    // ── Default lead: safest card ─────────────────────────────────
    // Score = rank + isTopCard penalty + void risk + suit danger
    // Lower score = safer to lead.
    int bestIdx = 0;
    double bestScore = double.infinity;

    for (int i = 0; i < hand.length; i++) {
      final card = hand[i];
      final s = card.suit.index;
      final topPenalty = _memory.isTopCard(card) ? 30.0 : 0.0;
      final voidRisk = _memory.knownVoidCount(opponentIds, s) * 10.0;
      final dangerRisk = _memory.suitDanger(s) * 20.0; // many cards gone = risky suit to lead
      final rankBase = phase == _Phase.late ? (12 - card.rank.index).toDouble() : card.rank.index.toDouble();
      final score = rankBase + topPenalty + voidRisk + dangerRisk;

      _log('  ${card.rank.name}/${Suit.values[s].name} top=$topPenalty void=$voidRisk danger=$dangerRisk → $score');
      if (score < bestScore) { bestScore = score; bestIdx = i; }
    }

    _log('${bot.name} CHOSE: ${hand[bestIdx].rank.name} of ${hand[bestIdx].suit.name}');
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

    // Safe cards: below the current table high (won't be top card)
    final safe = matching.where((i) => hand[i].rank.index < tableHigh).toList();

    if (safe.isNotEmpty) {
      if (phase == _Phase.early) {
        // Early: use highest safe card — dump big cards while still protected
        safe.sort((a, b) => hand[b].rank.index.compareTo(hand[a].rank.index));
      } else {
        // Mid/Late: use lowest safe card — stay as low as possible
        safe.sort((a, b) => hand[a].rank.index.compareTo(hand[b].rank.index));
      }
      return safe.first;
    }

    // No safe card — forced to potentially be top card
    // Late game: play absolute lowest to minimise pickup damage
    // Early game: doesn't matter much, play lowest anyway
    final sorted = List<int>.from(matching)
      ..sort((a, b) => hand[a].rank.index.compareTo(hand[b].rank.index));
    return sorted.first;
  }

  int _cutCard(Player bot, GameState state) {
    final hand = bot.hand;
    // Vettu is a weapon — dump the most dangerous card in your hand.
    // Danger = high rank + high suit danger (many cards of that suit already gone
    // means you're likely to face a vettu on that suit soon anyway).
    int bestIdx = 0;
    double bestDanger = -1;

    for (int i = 0; i < hand.length; i++) {
      final card = hand[i];
      final suitDanger = _memory.suitDanger(card.suit.index) * 15.0;
      final isTop = _memory.isTopCard(card) ? 20.0 : 0.0;
      final danger = card.rank.index + isTop + suitDanger;
      if (danger > bestDanger) { bestDanger = danger; bestIdx = i; }
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
