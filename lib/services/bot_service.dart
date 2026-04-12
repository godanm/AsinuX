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

// ── Game Memory ──────────────────────────────────────────────────────────────

class _GameMemory {
  final Set<String> _gone = {};
  final Map<String, Set<int>> _voids = {};

  void reset() {
    _gone.clear();
    _voids.clear();
  }

  void markGone(PlayingCard card) => _gone.add(_k(card));

  void recordCut(String playerId, int leadSuitIndex) =>
      _voids.putIfAbsent(playerId, () => {}).add(leadSuitIndex);

  bool isVoidIn(String playerId, int suitIndex) =>
      _voids[playerId]?.contains(suitIndex) ?? false;

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

  // ── EASY: pure random ────────────────────────────────────────
  //
  // Picks any valid card at random. Follows suit if it has one
  // (Firebase rejects invalid plays), otherwise plays anything.

  int _chooseEasy(Player bot, GameState state) {
    final hand = bot.hand;
    if (state.currentSuit == null) return _random.nextInt(hand.length);

    final suit = state.currentSuit!;
    final matching = [for (int i = 0; i < hand.length; i++) if (hand[i].suit.index == suit) i];
    if (matching.isNotEmpty) return matching[_random.nextInt(matching.length)];
    return _random.nextInt(hand.length);
  }

  // ── MEDIUM: suit-aware, no memory ────────────────────────────
  //
  // Follows suit. When following, avoids being the table high
  // (picks a safe card below current highest if possible).
  // When cutting, dumps highest rank.

  int _chooseMedium(Player bot, GameState state) {
    final hand = bot.hand;
    if (state.currentSuit == null) return _random.nextInt(hand.length);

    final suit = state.currentSuit!;
    final matching = [for (int i = 0; i < hand.length; i++) if (hand[i].suit.index == suit) i];

    if (matching.isNotEmpty) {
      int tableHigh = -1;
      for (final played in state.playedCards.values) {
        if (played.suit.index == suit && played.rank.index > tableHigh) {
          tableHigh = played.rank.index;
        }
      }
      final safe = matching.where((i) => hand[i].rank.index < tableHigh).toList();
      if (safe.isNotEmpty) {
        safe.sort((a, b) => hand[b].rank.index.compareTo(hand[a].rank.index));
        return safe.first;
      }
      // No safe card — play lowest to minimise pickup damage
      matching.sort((a, b) => hand[a].rank.index.compareTo(hand[b].rank.index));
      return matching.first;
    }

    // Cutting — dump highest card
    return hand.indexed
        .reduce((a, b) => a.$2.rank.index > b.$2.rank.index ? a : b)
        .$1;
  }

  // ── HARD: full memory + void tracking ────────────────────────
  //
  // Uses _GameMemory to lead safely, follow aggressively when
  // protected, and cut with the most dangerous card.

  int _chooseHard(Player bot, GameState state) {
    if (state.currentSuit == null) return _leadCard(bot, state);

    final suit = state.currentSuit!;
    final matching = [for (int i = 0; i < bot.hand.length; i++) if (bot.hand[i].suit.index == suit) i];

    if (matching.isNotEmpty) return _followCard(bot, state, matching, suit);
    return _cutCard(bot, state);
  }

  int _leadCard(Player bot, GameState state) {
    final hand = bot.hand;
    final opponentIds = state.activePlayers
        .where((p) => p.id != bot.id)
        .map((p) => p.id)
        .toList();

    int bestIdx = 0;
    double bestScore = double.infinity;

    _log('${bot.name} LEADING — evaluating ${hand.length} cards:');
    for (int i = 0; i < hand.length; i++) {
      final card = hand[i];
      final s = card.suit.index;
      final topCard = _memory.isTopCard(card) ? 25.0 : 0.0;
      final voids = _memory.knownVoidCount(opponentIds, s).toDouble();
      final score = card.rank.index + topCard + voids * 8;
      _log('  ${card.rank.name} of ${Suit.values[s].name} → score=$score');
      if (score < bestScore) { bestScore = score; bestIdx = i; }
    }

    _log('${bot.name} CHOSE: ${hand[bestIdx].rank.name} of ${hand[bestIdx].suit.name}');
    return bestIdx;
  }

  int _followCard(Player bot, GameState state, List<int> matching, int leadSuit) {
    final hand = bot.hand;
    int tableHigh = -1;
    for (final played in state.playedCards.values) {
      if (played.suit.index == leadSuit && played.rank.index > tableHigh) {
        tableHigh = played.rank.index;
      }
    }

    final safe = matching.where((i) => hand[i].rank.index < tableHigh).toList();
    if (safe.isNotEmpty) {
      safe.sort((a, b) => hand[b].rank.index.compareTo(hand[a].rank.index));
      return safe.first;
    }

    final sorted = List<int>.from(matching)
      ..sort((a, b) => hand[b].rank.index.compareTo(hand[a].rank.index));
    return sorted.first;
  }

  int _cutCard(Player bot, GameState state) {
    final hand = bot.hand;
    int bestIdx = 0;
    double bestDanger = -1;

    for (int i = 0; i < hand.length; i++) {
      final card = hand[i];
      final top = _memory.highestLiveRank(card.suit.index) ?? card.rank.index;
      final isTop = card.rank.index >= top ? 15.0 : 0.0;
      final danger = card.rank.index + isTop;
      if (danger > bestDanger) { bestDanger = danger; bestIdx = i; }
    }

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
