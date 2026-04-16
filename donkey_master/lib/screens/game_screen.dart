import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/game_state.dart';
import '../models/player_model.dart';
import '../models/card_model.dart';
import '../services/firebase_service.dart';
import '../services/admob_service.dart';
import '../services/bot_service.dart';
import '../services/sound_service.dart';
import '../services/stats_service.dart';
import '../utils/game_logic.dart';
import '../widgets/card_widget.dart';
import '../widgets/ad_banner_widget.dart';
import '../widgets/how_to_play_overlay.dart';
import '../widgets/player_avatar.dart';
// import '../widgets/chat_overlay.dart'; // TODO: enable chat when ready
import 'results_screen.dart';

class GameScreen extends StatefulWidget {
  final String roomId;
  final String playerId;

  const GameScreen({super.key, required this.roomId, required this.playerId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late Stream<GameState?> _stateStream;
  bool _actionBusy = false;
  Timer? _trickTimer;
  GameState? _lastState;
  String? _escapeeMessage;
  final Set<String> _announcedEscapees = {};
  bool _iEscaped = false;
  bool _iHaveFinished = false; // stays true even when watching after escape

  // Trick fly-out animation state
  Map<String, PlayingCard> _outgoingCards = {};
  String? _outgoingWinnerId;
  bool _outgoingIsCut = false;
  List<String> _outgoingOrder = [];
  Timer? _outgoingTimer;

  @override
  void initState() {
    super.initState();
    _stateStream = FirebaseService.instance.roomStream(widget.roomId);
  }

  @override
  void dispose() {
    _trickTimer?.cancel();
    BotService.instance.stop(); // safety net: stop bots if screen is force-closed
    _outgoingTimer?.cancel();
    super.dispose();
  }

  Future<void> _exitGame() async {
    // If this player escaped but the round isn't over yet, write their stats
    // now before leaving. When leaveRoom() deletes the room (last human gone),
    // bots stop and _resolveTrick never fires — stats would be lost otherwise.
    // Guard: only write early if this is the sole non-bot player, so multi-human
    // games don't double-count when recordRound fires normally at round end.
    final state = _lastState;
    if (_iEscaped && state != null && (state.donkeyId == null || state.donkeyId!.isEmpty)) {
      final humanIds = state.playerOrder.where((id) => !id.startsWith('bot_')).toList();
      if (humanIds.length == 1 && humanIds.first == widget.playerId) {
        final playerNames = {for (final p in state.players.values) p.id: p.name};
        StatsService.instance.recordRound(
          allPlayerIds: [widget.playerId],
          escapedIds: state.finishOrder,
          donkeyId: '',
          winnerId: null,
          isBot: false,
          playerNames: playerNames,
        ).catchError((e) => debugPrint('[GameScreen] early stats write failed: $e'));
      }
    }
    BotService.instance.stop();
    await FirebaseService.instance.leaveRoom(widget.roomId, widget.playerId);
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<bool> _confirmExit(BuildContext context) async {
    // If the round/game is already over, skip the forfeit dialog entirely.
    // trickEnd alone doesn't mean the round is over — only when donkeyId is set.
    final phase = _lastState?.phase;
    final isOver = phase == GamePhase.gameOver ||
        (phase == GamePhase.trickEnd && _lastState?.donkeyId != null);
    if (isOver || _iHaveFinished) {
      await _exitGame();
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a000e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Leave game?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'You\'ll forfeit this round. Your progress will be lost.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('STAY', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), letterSpacing: 1)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE63946)),
            child: const Text('LEAVE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AdMobService.instance.showInterstitialAsync(context);
      await _exitGame();
    }
    return false;
  }

  bool _isMyTurn(GameState state) => state.currentTurn == widget.playerId;
  bool _isHost(GameState state) => state.hostId == widget.playerId;
  bool _iHavePlayed(GameState state) =>
      state.playedCards.containsKey(widget.playerId);

  bool _isLeader(GameState state) =>
      state.currentLeader == widget.playerId && !_iHavePlayed(state);

  /// Can the player play [card]?
  /// - Leader can play any card.
  /// - Followers must match suit if they have it.
  /// - If no matching suit, they can play any card (cut).
  bool _canPlay(PlayingCard card, GameState state) {
    final me = state.players[widget.playerId];
    if (me == null) return false;
    if (_isLeader(state) || state.currentSuit == null) return true;
    final suit = state.currentSuit!;
    final hasMatch = GameLogic.hasMatchingSuit(me.hand, suit);
    if (!hasMatch) return true; // cut — any card allowed
    return card.suit.index == suit; // must follow suit
  }

  bool _wasMyTurn = false;

  void _onStateChange(GameState state) {
    final prev = _lastState;
    _lastState = state;

    // Detect trick being cleared — trigger fly-out animation
    if (prev != null &&
        prev.playedCards.isNotEmpty &&
        state.playedCards.isEmpty) {
      final winnerId = prev.trickWinnerId;
      final isCut = winnerId == null;
      // For a cut the cutter becomes the next leader
      final effectiveId = winnerId ?? state.currentLeader;
      _outgoingTimer?.cancel();
      setState(() {
        _outgoingCards = Map.from(prev.playedCards);
        _outgoingOrder = List.from(prev.playerOrder);
        _outgoingWinnerId = effectiveId;
        _outgoingIsCut = isCut;
      });
      _outgoingTimer = Timer(const Duration(milliseconds: 750), () {
        if (mounted) setState(() => _outgoingCards = {});
      });
    }

    // Your turn notification
    final myTurnNow = _isMyTurn(state) &&
        state.phase == GamePhase.playing &&
        !_iHavePlayed(state);
    if (myTurnNow && !_wasMyTurn) {
      SoundService.instance.playYourTurn();
      HapticFeedback.mediumImpact(); // buzz: it's your turn
    }
    _wasMyTurn = myTurnNow;

    // Detect cuts on the table
    if (state.phase == GamePhase.playing &&
        state.currentSuit != null &&
        state.playedCards.values
            .any((c) => c.suit.index != state.currentSuit)) {
      SoundService.instance.playCut();
    }

    // Detect newly escaped players
    for (final id in state.finishOrder) {
      if (!_announcedEscapees.contains(id) &&
          (state.players[id]?.hand.isEmpty ?? false)) {
        _announcedEscapees.add(id);
        SoundService.instance.playEscape();
        if (id == widget.playerId) {
          HapticFeedback.heavyImpact(); // strong buzz: you escaped!
          setState(() { _iEscaped = true; _iHaveFinished = true; });
        } else {
          final name = state.players[id]?.name ?? '';
          setState(() => _escapeeMessage = '✅ $name escaped!');
          _trickTimer?.cancel();
          _trickTimer = Timer(const Duration(milliseconds: 1500), () {
            if (mounted) setState(() => _escapeeMessage = null);
          });
        }
      }
    }

    // Reset on new round
    if (state.roundNumber != (_lastState?.roundNumber ?? 0) ||
        state.finishOrder.isEmpty) {
      _announcedEscapees.clear();
      if (_iEscaped) setState(() => _iEscaped = false);
    }

    // Human host starts next trick when bots aren't running
    if (state.phase == GamePhase.trickEnd && state.donkeyId == null) {
      if (_isHost(state) && !BotService.instance.isRunning) {
        _trickTimer?.cancel();
        _trickTimer = Timer(const Duration(seconds: 2), () async {
          final s = _lastState;
          if (s != null &&
              s.phase == GamePhase.trickEnd &&
              s.donkeyId == null) {
            await FirebaseService.instance.startNextTrick(s);
          }
        });
      }
    }
  }

  Future<void> _playCard(GameState state, int cardIndex) async {
    if (_actionBusy) return;
    final me = state.players[widget.playerId];
    if (me == null || me.hand.isEmpty) return;

    final card = me.hand[cardIndex];
    if (!_canPlay(card, state)) {
      final suitName = Suit.values[state.currentSuit!].name;
      final capitalized =
          suitName[0].toUpperCase() + suitName.substring(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You must play a $capitalized card!'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _actionBusy = true);
    try {
      SoundService.instance.playCardSlap();
      HapticFeedback.lightImpact(); // light tap: card played
      await FirebaseService.instance.playCard(
        state: state,
        playerId: widget.playerId,
        cardIndex: cardIndex,
      );
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  List<Widget> _escapedBadges(GameState state) {
    if (_escapeeMessage == null) return [];
    final isMe = _escapeeMessage!.startsWith('🎉 You');
    return [
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: _escapeeMessage != null ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              color: isMe
                  ? Colors.green.shade900.withValues(alpha: 0.85)
                  : Colors.black.withValues(alpha: 0.65),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isMe ? '🎉' : '✅',
                      style: const TextStyle(fontSize: 72),
                    ).animate().scale(
                          duration: 500.ms,
                          curve: Curves.elasticOut,
                        ),
                    const SizedBox(height: 16),
                    Text(
                      _escapeeMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMe ? 28 : 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.3),
                    const SizedBox(height: 8),
                    Text(
                      isMe ? 'You made it out!' : 'One fewer opponent',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                      ),
                    ).animate().fadeIn(delay: 300.ms),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit(context);
      },
      child: StreamBuilder<GameState?>(
      stream: _stateStream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFF3d0020),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final state = snap.data;
        if (state == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF3d0020),
            body: Center(
                child: Text('Room closed',
                    style: TextStyle(color: Colors.white))),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _onStateChange(state);
        });

        if (state.phase == GamePhase.gameOver) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => ResultsScreen(
                    state: state,
                    playerId: widget.playerId,
                  ),
                ),
              );
            }
          });
        }

        if (state.phase == GamePhase.trickEnd && state.donkeyId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            SoundService.instance.playDonkey();
            // Strong double-buzz for donkey reveal — noticeable but not annoying
            HapticFeedback.heavyImpact();
            Future.delayed(const Duration(milliseconds: 200), HapticFeedback.heavyImpact);
          });
          return _buildRoundEndScreen(context, state);
        }

        if (_iEscaped) return _buildEscapedScreen(state);

        return _buildTableScreen(state);
      },
    ),
    );
  }

  // ── Escaped screen ───────────────────────────────────────────

  Widget _buildEscapedScreen(GameState state) {
    final remaining = state.activePlayers
        .where((p) => p.id != widget.playerId && p.hand.isNotEmpty)
        .length;

    return Scaffold(
      backgroundColor: const Color(0xFF0a2e0a),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🎉', style: TextStyle(fontSize: 100))
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(begin: const Offset(1, 1), end: const Offset(1.15, 1.15), duration: 800.ms),
                const SizedBox(height: 24),
                const Text(
                  'YOU ESCAPED!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.3),
                const SizedBox(height: 12),
                Text(
                  remaining == 1
                      ? '1 player still fighting...'
                      : '$remaining players still fighting...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ).animate().fadeIn(delay: 400.ms),
                const SizedBox(height: 16),
                _WaitingDots(),
                const SizedBox(height: 48),

                // Watch / Exit buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _iEscaped = false),
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('WATCH'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _exitGame,
                        icon: const Icon(Icons.exit_to_app, size: 18),
                        label: const Text('EXIT'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE63946),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 600.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Main table layout ────────────────────────────────────────

  Widget _buildTableScreen(GameState state) {
    final me = state.players[widget.playerId];
    // Show all opponents in fixed positions — escaped ones stay visible
    final others = state.activePlayers
        .where((p) => p.id != widget.playerId)
        .toList();
    final suit = state.currentSuit != null
        ? Suit.values[state.currentSuit!]
        : null;
    final trickEnded = state.phase == GamePhase.trickEnd;
    final iAmLeader = _isLeader(state);
    final myTurnActive = _isMyTurn(state) && !trickEnded && !_iHavePlayed(state);

    return Scaffold(
      backgroundColor: const Color(0xFF3d0020),
      body: SafeArea(
        child: Column(
          children: [
            _TopInfoBar(
              suit: suit,
              onToggleMute: () => setState(() {
                SoundService.instance.toggleMute();
              }),
              muted: SoundService.instance.muted,
              onExit: () => _confirmExit(context),
            ),

            // Opponents — fixed height so avatars always render consistently
            SizedBox(
              height: 110,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.5,
                    colors: [Color(0xFF4a0028), Color(0xFF220010)],
                  ),
                ),
                child: _OpponentsLayout(
                  players: others,
                  currentTurn: state.currentTurn,
                  playedCards: state.playedCards,
                  leadSuit: state.currentSuit,
                ),
              ),
            ),

            // Center table — sits between opponents and hand, never overlaps either
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xFFF5EDE0),
                    ),
                  ),
                  Center(
                    child: _CenterTable(
                      state: state,
                      myId: widget.playerId,
                    ),
                  ),
                  // Fly-out animation when trick is cleared
                  if (_outgoingCards.isNotEmpty)
                    Center(
                      child: _TrickFlyOut(
                        cards: _outgoingCards,
                        playerOrder: _outgoingOrder,
                        winnerId: _outgoingWinnerId,
                        isCut: _outgoingIsCut,
                        myId: widget.playerId,
                      ),
                    ),
                  if (trickEnded)
                    ..._escapedBadges(state),
                ],
              ),
            ),

            // Hand — always visible
            _MyInfoBar(
              player: me,
              isMyTurn: myTurnActive,
              isLeader: iAmLeader,
            ),
            _MyHand(
              player: me,
              isMyTurn: myTurnActive,
              currentSuit: state.currentSuit,
              isLeader: iAmLeader,
              busy: _actionBusy,
              iHavePlayed: _iHavePlayed(state),
              onPlayCard: (idx) => _playCard(state, idx),
            ),

            const AdBannerWidget(),
          ],
        ),
      ),
    );
  }

  // ── Round end screen ─────────────────────────────────────────

  Widget _buildRoundEndScreen(BuildContext context, GameState state) {
    final donkey = state.donkeyId != null
        ? state.players[state.donkeyId]
        : null;
    final iAmDonkey = state.donkeyId == widget.playerId;

    return Scaffold(
      backgroundColor: const Color(0xFF0d0007),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Dramatic donkey — zooms in from nothing, bounces, then shakes
                      Text(
                        iAmDonkey ? '🫏' : '🎉',
                        style: const TextStyle(fontSize: 100),
                      )
                          .animate()
                          .scale(
                            begin: const Offset(0, 0),
                            end: const Offset(1.3, 1.3),
                            duration: 500.ms,
                            curve: Curves.easeOut,
                          )
                          .then()
                          .scale(
                            begin: const Offset(1.3, 1.3),
                            end: const Offset(1.0, 1.0),
                            duration: 200.ms,
                          )
                          .then(delay: 100.ms)
                          .shake(hz: 5, offset: const Offset(8, 0), duration: 500.ms),

                      const SizedBox(height: 24),

                      // Title — slides up after emoji lands
                      Text(
                        iAmDonkey ? "YOU'RE THE DONKEY!" : 'ROUND OVER!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: iAmDonkey ? Colors.redAccent : Colors.white,
                        ),
                      ).animate().fadeIn(delay: 700.ms, duration: 400.ms).slideY(begin: 0.3),

                      if (donkey != null) ...[
                        const SizedBox(height: 10),
                        // Donkey name reveal — pops in with emphasis
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            iAmDonkey ? 'Better luck next time!' : '🫏  ${donkey.name} is eliminated!',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 1100.ms, duration: 400.ms)
                            .scale(
                              begin: const Offset(0.8, 0.8),
                              delay: 1100.ms,
                              duration: 300.ms,
                              curve: Curves.elasticOut,
                            ),
                      ],

                      const SizedBox(height: 32),

                      // Player pills — stagger in one by one
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: state.activePlayers
                            .asMap()
                            .entries
                            .map((e) => _PlayerPill(
                                  player: e.value,
                                  isMe: e.value.id == widget.playerId,
                                ).animate().fadeIn(
                                  delay: Duration(milliseconds: 1400 + e.key * 120),
                                  duration: 300.ms,
                                ).slideY(begin: 0.3, delay: Duration(milliseconds: 1400 + e.key * 120)))
                            .toList(),
                      ),
                      const SizedBox(height: 32),
                      // Next round button (host only) or waiting label
                      if (_isHost(state))
                        ElevatedButton(
                          onPressed: () async {
                            await AdMobService.instance.showRewardedAsync(context);
                            await Future.delayed(const Duration(seconds: 2));
                            await FirebaseService.instance.startNextRound(state);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE63946),
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          child: const Text(
                            'NEXT ROUND',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2),
                          ),
                        )
                      else
                        Text(
                          'Waiting for next round...',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                        ),
                      const SizedBox(height: 16),
                      // Always show Exit option
                      TextButton.icon(
                        onPressed: _exitGame,
                        icon: Icon(Icons.exit_to_app, size: 16, color: Colors.white.withValues(alpha: 0.4)),
                        label: Text(
                          'EXIT TO HOME',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), letterSpacing: 1.5, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const AdBannerWidget(),
          ],
        ),
      ),
    );
  }
}

// ── Avatar helper ────────────────────────────────────────────────

const _avatarColors = [
  Color(0xFFE63946), Color(0xFF2196F3), Color(0xFF4CAF50), Color(0xFFFF9800),
  Color(0xFF9C27B0), Color(0xFF00BCD4), Color(0xFFFF5722), Color(0xFF607D8B),
  Color(0xFFE91E63), Color(0xFF009688), Color(0xFF8BC34A), Color(0xFF795548),
];

Color playerColor(String id) =>
    _avatarColors[id.codeUnits.fold(0, (a, b) => a + b) % _avatarColors.length];

String playerInitial(String name) =>
    name.isNotEmpty ? name[0].toUpperCase() : '?';

// ── Sub-widgets ──────────────────────────────────────────────────

class _TopInfoBar extends StatelessWidget {
  final Suit? suit;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onExit;

  const _TopInfoBar({
    required this.suit,
    required this.muted,
    required this.onToggleMute,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final suitSymbol = switch (suit) {
      Suit.hearts => '♥',
      Suit.diamonds => '♦',
      Suit.clubs => '♣',
      Suit.spades => '♠',
      null => '—',
    };
    final isRed = suit == Suit.hearts || suit == Suit.diamonds;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black26,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Builder(builder: (context) {
            final widget = Row(
              children: [
                Text(
                  suit != null ? 'Lead suit: ' : 'Choose suit',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                if (suit != null)
                  Text(
                    suitSymbol,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isRed ? Colors.red.shade300 : Colors.white,
                    ),
                  ),
              ],
            );
            if (suit != null) {
              return widget
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fadeIn(duration: 700.ms)
                  .then()
                  .fadeOut(duration: 700.ms);
            }
            return widget;
          }),
          Row(
            children: [
              GestureDetector(
                onTap: () => showHowToPlay(context),
                child: Icon(Icons.help_outline_rounded,
                    color: Colors.white.withValues(alpha: 0.5), size: 18),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onToggleMute,
                child: Icon(
                  muted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              // TODO: enable chat when ready
              // GestureDetector(
              //   onTap: onChat,
              //   child: Icon(Icons.chat_bubble_outline_rounded,
              //       color: Colors.white.withValues(alpha: 0.5), size: 18),
              // ),
              // const SizedBox(width: 12),
              GestureDetector(
                onTap: onExit,
                child: Icon(Icons.exit_to_app,
                    color: Colors.white.withValues(alpha: 0.5), size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OpponentsLayout extends StatelessWidget {
  final List<Player> players;
  final String? currentTurn;
  final Map<String, PlayingCard> playedCards;
  final int? leadSuit;

  const _OpponentsLayout({
    required this.players,
    required this.currentTurn,
    required this.playedCards,
    required this.leadSuit,
  });

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;

      return Stack(
        children: List.generate(players.length.clamp(0, 3), (i) {
          final p = players[i];
          final isTheirTurn = currentTurn == p.id;
          final hasPlayed = playedCards.containsKey(p.id);
          final playedCard = playedCards[p.id];
          final isCut = playedCard != null &&
              leadSuit != null &&
              playedCard.suit.index != leadSuit;

          double top = 12;
          double? left;
          double? right;

          if (i == 0) left = 12;
          if (i == 1) left = w / 2 - 50;
          if (i == 2) right = 12;

          return Positioned(
            top: top,
            left: left,
            right: right,
            child: _OpponentCard(
              player: p,
              isTheirTurn: isTheirTurn,
              hasPlayed: hasPlayed,
              isCut: isCut,
              escaped: p.hand.isEmpty,
            ),
          );
        }),
      );
    });
  }
}

class _OpponentCard extends StatelessWidget {
  final Player player;
  final bool isTheirTurn;
  final bool hasPlayed;
  final bool isCut;
  final bool escaped;

  const _OpponentCard({
    required this.player,
    required this.isTheirTurn,
    required this.hasPlayed,
    required this.isCut,
    required this.escaped,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: escaped
            ? Colors.green.shade900.withValues(alpha: 0.35)
            : Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: escaped
              ? Colors.green.shade700
              : isTheirTurn
                  ? const Color(0xFFE63946)
                  : isCut
                      ? Colors.redAccent
                      : Colors.white.withValues(alpha: 0.1),
          width: escaped || isTheirTurn || isCut ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _SpinningRing(
                active: isTheirTurn && !escaped,
                color: const Color(0xFFE63946),
                radius: 22,
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: escaped
                      ? Colors.green.shade700
                      : playerColor(player.id),
                  child: Text(
                    escaped ? '✓' : playerInitial(player.name),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              // Card count badge — top right of avatar
              if (!escaped && !player.isEliminated)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: player.hand.length <= 2
                          ? const Color(0xFFE63946)
                          : const Color(0xFF1a000e),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: player.hand.length <= 2
                            ? Colors.white
                            : Colors.white30,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${player.hand.length}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: player.hand.length <= 2
                            ? Colors.white
                            : Colors.white70,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            player.name.split('_').first, // show just first name part
            style: TextStyle(
              color: escaped ? Colors.green.shade300 : Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (escaped)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Escaped!',
                style: TextStyle(
                  color: Colors.green.shade400,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (!escaped && isCut)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'CUT!',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (!escaped && hasPlayed && !isCut)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.check_circle,
                color: Colors.greenAccent.shade400,
                size: 14,
              ),
            ),
          if (player.isEliminated)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'OUT',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CenterTable extends StatelessWidget {
  final GameState state;
  final String myId;

  const _CenterTable({required this.state, required this.myId});

  // Slot colors per seat index (matches the colorful placeholder look)
  static const _slotColors = [
    Color(0xFFE8B84B), // amber
    Color(0xFF4A7FD4), // blue
    Color(0xFFD44A8C), // rose
    Color(0xFF4AB87A), // green
  ];

  @override
  Widget build(BuildContext context) {
    final played = state.playedCards;
    final order = state.playerOrder;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: List.generate(order.length.clamp(0, 4), (i) {
        final id = order[i];
        final card = played[id];
        final isMe = id == myId;
        final playerName = isMe ? 'You' : (state.players[id]?.name.split(' ').last ?? '');
        final slotColor = _slotColors[i % _slotColors.length];
        final isCut = card != null &&
            state.currentSuit != null &&
            card.suit.index != state.currentSuit;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (card != null)
              Container(
                decoration: isCut
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent, width: 2.5),
                      )
                    : null,
                child: CardWidget(card: card, width: 62, height: 88),
              )
                  .animate()
                  .slideY(begin: isMe ? 0.6 : -0.6, duration: 300.ms, curve: Curves.easeOut)
                  .fadeIn(duration: 250.ms)
            else
              // Placeholder slot
              Container(
                width: 62,
                height: 88,
                decoration: BoxDecoration(
                  color: slotColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: slotColor.withValues(alpha: 0.55),
                    width: 2.5,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.add_rounded,
                    color: slotColor.withValues(alpha: 0.4),
                    size: 24,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              playerName,
              style: TextStyle(
                color: isCut
                    ? Colors.redAccent
                    : (card != null
                        ? Colors.black54
                        : slotColor.withValues(alpha: 0.6)),
                fontSize: 10,
                fontWeight: isCut ? FontWeight.bold : FontWeight.w500,
              ),
            ).animate().fadeIn(delay: 100.ms, duration: 200.ms),
          ],
        );
      }),
    );
  }
}

class _MyInfoBar extends StatelessWidget {
  final Player? player;
  final bool isMyTurn;
  final bool isLeader;

  const _MyInfoBar({
    required this.player,
    required this.isMyTurn,
    required this.isLeader,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black26,
      child: Row(
        children: [
          _SpinningRing(
            active: isMyTurn,
            color: const Color(0xFFE63946),
            radius: 24,
            child: LocalPlayerAvatar(
              radius: 18,
              playerId: player?.id ?? '',
              playerName: player?.name ?? 'Y',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player?.name ?? 'You',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                if (player?.isEliminated == true)
                  const Text(
                    'OUT',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
              ],
            ),
          ),
          if (isMyTurn)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isLeader
                    ? const Color(0xFF00C853)
                    : const Color(0xFFE63946),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isLeader ? 'LEAD!' : 'YOUR TURN',
                style: TextStyle(
                  color: isLeader ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MyHand extends StatelessWidget {
  final Player? player;
  final bool isMyTurn;
  final int? currentSuit;
  final bool isLeader;
  final bool busy;
  final bool iHavePlayed;
  final void Function(int) onPlayCard;

  const _MyHand({
    required this.player,
    required this.isMyTurn,
    required this.currentSuit,
    required this.isLeader,
    required this.busy,
    required this.iHavePlayed,
    required this.onPlayCard,
  });

  @override
  Widget build(BuildContext context) {
    final hand = player?.hand ?? [];
    if (hand.isEmpty) {
      return Container(
        height: 200,
        color: const Color(0xFF5a1a30),
        alignment: Alignment.center,
        child: const Text('🎉 Hand empty!',
            style: TextStyle(color: Colors.white70, fontSize: 16)),
      );
    }

    // Group cards by suit: ♠ ♥ ♦ ♣
    final suitOrder = [Suit.spades, Suit.hearts, Suit.diamonds, Suit.clubs];
    final bySuit = <Suit, List<MapEntry<int, PlayingCard>>>{};
    for (final s in suitOrder) { bySuit[s] = []; }
    for (final entry in hand.asMap().entries) {
      bySuit[entry.value.suit]!.add(entry);
    }
    // Sort low→high: index 0 = 2 (top/peeking), last = Ace (bottom/fully visible)
    for (final list in bySuit.values) {
      list.sort((a, b) => a.value.rank.index.compareTo(b.value.rank.index));
    }

    final bool canPlayAny = isMyTurn && !iHavePlayed;

    String statusText;
    if (iHavePlayed) {
      statusText = '✓ Played — waiting...';
    } else if (!isMyTurn) {
      statusText = 'Waiting...';
    } else if (isLeader) {
      statusText = 'TAP any card to lead';
    } else {
      final suit = currentSuit != null ? Suit.values[currentSuit!] : null;
      final hasMatch = suit != null && GameLogic.hasMatchingSuit(hand, currentSuit!);
      statusText = hasMatch
          ? 'TAP a ${suit.name} card'
          : 'No ${suit?.name ?? ''} — TAP any card to cut';
    }

    const double cardH = 90.0;
    const double peekH = 26.0; // enough to show rank+suit at top of each card

    return LayoutBuilder(builder: (context, constraints) {
    // Clamp column height so the hand never overflows on small screens.
    // Reserve ~90px for top bar + ~50px for ad + ~70px for info bar + status text.
    final screenH = MediaQuery.of(context).size.height;
    final colHeight = (screenH * 0.30).clamp(130.0, 220.0);

    return Container(
      color: const Color(0xFF5a1a30),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              statusText,
              style: TextStyle(
                color: canPlayAny ? Colors.white : Colors.white.withValues(alpha: 0.35),
                fontSize: 13,
                fontWeight: canPlayAny ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: suitOrder.map((suit) {
              final cards = bySuit[suit]!;
              final isRed = suit == Suit.hearts || suit == Suit.diamonds;
              final suitSymbol = switch (suit) {
                Suit.spades => '♠',
                Suit.hearts => '♥',
                Suit.diamonds => '♦',
                Suit.clubs => '♣',
              };

              final count = cards.length;
              // Each peeking card shows exactly peekH pixels (rank+suit visible)
              // Bottom card is fully shown — so total = peekH*(n-1) + cardH
              final double offset = count <= 1 ? 0 : peekH;

              bool suitValid;
              if (!canPlayAny) {
                suitValid = false;
              } else if (isLeader || currentSuit == null) {
                suitValid = true;
              } else {
                final hasMatch = GameLogic.hasMatchingSuit(hand, currentSuit!);
                suitValid = !hasMatch || suit.index == currentSuit;
              }

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Suit header pill — flashes when this suit is playable
                      Builder(builder: (context) {
                        final pill = Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: suitValid && canPlayAny
                                ? (isRed ? Colors.red.shade600 : Colors.blueGrey.shade700)
                                : Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: suitValid && canPlayAny
                                  ? Colors.white.withValues(alpha: 0.4)
                                  : Colors.white.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '$suitSymbol ${cards.length}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isRed ? Colors.red.shade100 : Colors.white,
                            ),
                          ),
                        );
                        if (suitValid && canPlayAny) {
                          return pill
                              .animate(onPlay: (c) => c.repeat(reverse: true))
                              .fadeIn(duration: 600.ms)
                              .then()
                              .fadeOut(duration: 600.ms);
                        }
                        return pill;
                      }),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: colHeight,
                        child: cards.isEmpty
                            ? Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white10),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              )
                            : Stack(
                                children: cards.asMap().entries.map((entry) {
                                  final stackIdx = entry.key;
                                  final globalIdx = entry.value.key;
                                  final card = entry.value.value;

                                  return Positioned(
                                    top: stackIdx * offset,
                                    left: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: (suitValid && !busy)
                                          ? () => onPlayCard(globalIdx)
                                          : null,
                                      child: Opacity(
                                        opacity: canPlayAny && !suitValid ? 0.3 : 1.0,
                                        child: AnimatedScale(
                                          scale: (suitValid && busy) ? 0.85 : 1.0,
                                          duration: const Duration(milliseconds: 150),
                                          child: Container(
                                          height: cardH,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            boxShadow: suitValid
                                                ? [
                                                    BoxShadow(
                                                      color: const Color(0xFFE63946)
                                                          .withValues(alpha: 0.25),
                                                      blurRadius: 4,
                                                      spreadRadius: 1,
                                                    )
                                                  ]
                                                : [
                                                    BoxShadow(
                                                      color: Colors.black.withValues(alpha: 0.3),
                                                      blurRadius: 3,
                                                      offset: const Offset(0, 1),
                                                    )
                                                  ],
                                          ),
                                          child: CardWidget(
                                            card: card,
                                            width: double.infinity,
                                            height: cardH,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  );
                                }).toList(),
                              ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
    }); // LayoutBuilder
  }
}

// ── Helper widgets ───────────────────────────────────────────────

class _WaitingDots extends StatefulWidget {
  @override
  State<_WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<_WaitingDots> {
  int _step = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _step = (_step + 1) % 4);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final active = i < _step;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: active ? 12 : 8,
          height: active ? 12 : 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? const Color(0xFFE63946)
                : Colors.white.withValues(alpha: 0.2),
          ),
        );
      }),
    );
  }
}


class _PlayerPill extends StatelessWidget {
  final Player player;
  final bool isMe;

  const _PlayerPill({required this.player, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isMe
            ? const Color(0xFF220010).withValues(alpha: 0.5)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: player.isEliminated
              ? Colors.red.shade700
              : isMe
                  ? const Color(0xFFFF6B6B)
                  : Colors.white24,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            player.name,
            style: TextStyle(
              color: player.isEliminated ? Colors.grey : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          if (player.isEliminated)
            const Text(
              'OUT',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Spinning turn indicator ───────────────────────────────────────────────────

class _SpinningRing extends StatefulWidget {
  final bool active;
  final Color color;
  final double radius; // total widget radius — CircleAvatar radius + small gap
  final Widget child;

  const _SpinningRing({
    required this.active,
    required this.color,
    required this.radius,
    required this.child,
  });

  @override
  State<_SpinningRing> createState() => _SpinningRingState();
}

class _SpinningRingState extends State<_SpinningRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(_SpinningRing old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      _ctrl.repeat();
    } else {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => CustomPaint(
          painter: _ArcPainter(
            progress: _ctrl.value,
            color: widget.color,
            active: widget.active,
          ),
          child: child,
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool active;

  _ArcPainter({required this.progress, required this.color, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    if (!active) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Faint track ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Spinning arc (~240°)
    final startAngle = 2 * math.pi * progress - math.pi / 2;
    const sweepAngle = math.pi * 4 / 3;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress || old.active != active;
}

// ── Trick fly-out animation ───────────────────────────────────────────────────

class _TrickFlyOut extends StatelessWidget {
  final Map<String, PlayingCard> cards;
  final List<String> playerOrder;
  final String? winnerId;
  final bool isCut;
  final String myId;

  const _TrickFlyOut({
    required this.cards,
    required this.playerOrder,
    required this.winnerId,
    required this.isCut,
    required this.myId,
  });

  @override
  Widget build(BuildContext context) {
    final winnerIsMe = winnerId == myId;
    // Positive dy = toward bottom (local player), negative = toward top (opponent)
    final dy = winnerIsMe ? 200.0 : -200.0;
    final cutColor = Colors.red.shade700;

    final ordered = playerOrder
        .where(cards.containsKey)
        .map((id) => MapEntry(id, cards[id]!))
        .toList();

    final cardWrap = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: ordered.asMap().entries.map((entry) {
        final i = entry.key;
        final e = entry.value;
        final card = e.value;
        // For cut: converge cards toward center-x as they fly to the recipient.
        // Small offset so cards don't all stack exactly — gives a "dealt into
        // a hand" look rather than a single-point collapse.
        final targetDx = isCut ? (i - (ordered.length - 1) / 2) * 8.0 : 0.0;

        return Container(
          decoration: isCut
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cutColor.withValues(alpha: 0.8), width: 2),
                  boxShadow: [
                    BoxShadow(color: cutColor.withValues(alpha: 0.5), blurRadius: 12, spreadRadius: 2),
                  ],
                )
              : null,
          child: CardWidget(card: card, width: 58, height: 82),
        )
            .animate()
            .then(delay: 100.ms) // brief pause — player sees cards before they fly
            .move(
              begin: Offset.zero,
              end: Offset(targetDx, dy),
              duration: 480.ms,
              curve: Curves.easeIn,
            )
            .scaleXY(
              // Shrink as cards fly away — perspective "going into someone's hand"
              begin: 1.0,
              end: isCut ? 0.25 : 1.0,
              duration: 480.ms,
              curve: Curves.easeIn,
            )
            .fadeOut(duration: 280.ms, delay: 250.ms);
      }).toList(),
    );

    if (!isCut) return IgnorePointer(child: cardWrap);

    // On a cut: wrap cards in a column with a "VETTU! 🫏" label
    // pointing toward the recipient so it's clear who gets punished.
    final vettuLabel = Text(
      'VETTU! 🫏',
      style: TextStyle(
        color: cutColor,
        fontSize: 16,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
        shadows: [Shadow(color: cutColor.withValues(alpha: 0.6), blurRadius: 8)],
      ),
    )
        .animate()
        .fadeIn(duration: 120.ms)
        .scaleXY(begin: 1.3, end: 1.0, duration: 200.ms, curve: Curves.easeOut)
        .then(delay: 350.ms)
        .fadeOut(duration: 250.ms);

    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!winnerIsMe) vettuLabel, // opponent picks up: label above cards
          const SizedBox(height: 6),
          cardWrap,
          const SizedBox(height: 6),
          if (winnerIsMe) vettuLabel,  // I pick up: label below cards
        ],
      ),
    );
  }
}

