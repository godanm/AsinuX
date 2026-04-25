import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/rummy_models.dart';
import '../services/rummy_service.dart';
import '../services/rummy_bot_service.dart';
import '../widgets/player_avatar.dart';
import '../widgets/ad_banner_widget.dart';
import '../services/admob_service.dart';
import '../services/auth_service.dart';
import '../services/stats_service.dart';
import '../widgets/how_to_play_overlay.dart';
import '../services/sound_service.dart';
import '../services/game_logger.dart';

// ── Flying card state ─────────────────────────────────────────────────────────

class _FlyCard {
  final Offset start;
  final Offset end;
  final RummyCard? card; // null = show card back
  final int wildRank;
  const _FlyCard({
    required this.start,
    required this.end,
    this.card,
    required this.wildRank,
  });
}

class RummyGameScreen extends StatefulWidget {
  final String roomId;
  final String playerId;
  final String playerName;
  /// Bot player IDs in this room. Empty for non-host players.
  /// The host receives these so it can subscribe to bot hand streams
  /// and drive bot moves.
  final List<String> botIds;

  const RummyGameScreen({
    super.key,
    required this.roomId,
    required this.playerId,
    required this.playerName,
    this.botIds = const [],
  });

  @override
  State<RummyGameScreen> createState() => _RummyGameScreenState();
}

class _RummyGameScreenState extends State<RummyGameScreen> {
  StreamSubscription<RummyGameState?>? _sub;
  RummyGameState? _state;
  bool _busy = false;
  String? _lastBotActionKey; // prevents double-firing bot actions

  bool _gameOverAdFired = false;
  bool _statsRecorded = false;
  bool _isMuted = false;
  bool _gameLogInitialized = false;
  bool _gameLogEndFired = false;

  // Flying card animation
  _FlyCard? _flyCard;
  final _closedDeckKey = GlobalKey();
  final _openDeckKey   = GlobalKey();
  final _opponentKeys  = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    AdMobService.instance.suppressAppOpenAd = true;
    _sub = RummyService.instance
        .gameStream(widget.roomId, widget.playerId, widget.botIds)
        .listen(_onStateChange);
  }

  @override
  void dispose() {
    AdMobService.instance.suppressAppOpenAd = false;
    _sub?.cancel();
    super.dispose();
  }

  void _onStateChange(RummyGameState? state) {
    if (!mounted) return;
    setState(() => _state = state);
    if (state == null) return;

    // Log game start once
    if (!_gameLogInitialized) {
      _gameLogInitialized = true;
      final names = state.players.map((id, p) => MapEntry(id, p.name));
      GameLogger.instance.rummyGameStart(
        roomId: widget.roomId,
        playerNames: names,
        wildJokerRank: state.wildJoker.rankLabel,
      );
    }

    if (state.currentTurn == widget.playerId &&
        state.phase == RummyPhase.draw) {
      HapticFeedback.mediumImpact();
      SoundService.instance.playYourTurn();
    }

    // Fire rewarded ad + record stats + log once when game over
    if (state.phase == RummyPhase.gameOver) {
      if (!_gameOverAdFired) {
        _gameOverAdFired = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) AdMobService.instance.showRewardedAsync(context);
          });
        });
      }

      if (!_statsRecorded && !RummyBotService.isBot(widget.playerId)) {
        _statsRecorded = true;
        final won = state.winnerId == widget.playerId;
        final dropped =
            state.players[widget.playerId]?.hasDropped ?? false;
        final penalty = state.scores[widget.playerId] ?? 0;
        AuthService.instance.signInAnonymously().then((user) {
          StatsService.instance.recordRummyResult(
            uid: user.uid,
            won: won,
            dropped: dropped,
            penalty: penalty,
          );
        });
      }

      if (!_gameLogEndFired) {
        _gameLogEndFired = true;
        final winner = state.winnerId ?? '';
        final winnerName = state.players[winner]?.name ?? winner;
        GameLogger.instance.rummyGameEnd(
          roomId: widget.roomId,
          winnerId: winner,
          winnerName: winnerName,
          scores: state.scores,
        );
      }
    }

    // Drive bot turns — only the first real player in turnOrder acts as host
    final firstReal = state.turnOrder
        .firstWhere((id) => !RummyBotService.isBot(id), orElse: () => '');
    if (firstReal != widget.playerId) return;
    if (!RummyBotService.isBot(state.currentTurn)) return;

    final actionKey = '${state.currentTurn}:${state.phase.name}';
    if (_lastBotActionKey == actionKey) return;
    _lastBotActionKey = actionKey;

    if (state.phase == RummyPhase.draw) {
      Future.delayed(const Duration(milliseconds: 2400), () => _botDraw(state.currentTurn));
    } else {
      Future.delayed(const Duration(milliseconds: 1800), () => _botDiscard(state.currentTurn));
    }
  }

  Offset? _centerOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  Future<void> _botDraw(String botId) async {
    if (!mounted) return;
    final state = _state;
    if (state == null || state.currentTurn != botId) return;

    final hand = state.players[botId]?.hand ?? [];
    final useOpen = RummyBotService.shouldDrawFromOpen(
      state.topOfOpen, hand, state.wildJoker,
    );

    // Animate: source deck → opponent tile
    final src = _centerOf(useOpen ? _openDeckKey : _closedDeckKey);
    final dst = _centerOf(_opponentKeys[botId] ?? GlobalKey());
    if (src != null && dst != null) {
      setState(() => _flyCard = _FlyCard(
        start: src, end: dst,
        card: useOpen ? state.topOfOpen : null,
        wildRank: state.wildJoker.rank,
      ));
      await Future.delayed(const Duration(milliseconds: 480));
      if (mounted) setState(() => _flyCard = null);
    }

    if (!mounted) return;
    if (useOpen) {
      await RummyService.instance.drawFromOpen(widget.roomId, botId);
    } else {
      await RummyService.instance.drawFromClosed(widget.roomId, botId);
    }
  }

  Future<void> _botDiscard(String botId) async {
    if (!mounted) return;
    final state = _state;
    if (state == null || state.currentTurn != botId) return;
    final hand = state.players[botId]?.hand ?? [];
    if (hand.isEmpty) return;
    final idx = RummyBotService.chooseDiscard(hand, state.wildJoker);

    // Animate card face: opponent tile → open deck
    final src = _centerOf(_opponentKeys[botId] ?? GlobalKey());
    final dst = _centerOf(_openDeckKey);
    if (src != null && dst != null) {
      setState(() => _flyCard = _FlyCard(
        start: src, end: dst,
        card: hand[idx], wildRank: state.wildJoker.rank,
      ));
      await Future.delayed(const Duration(milliseconds: 480));
      if (mounted) setState(() => _flyCard = null);
    }

    if (!mounted) return;
    await RummyService.instance.discardCard(widget.roomId, botId, idx);
  }

  bool get _isMyTurn => _state?.currentTurn == widget.playerId;
  bool get _isDrawPhase => _state?.phase == RummyPhase.draw;
  bool get _isDiscardPhase => _state?.phase == RummyPhase.discard;

  Future<void> _drawFromClosed() async {
    if (_busy || !_isMyTurn || !_isDrawPhase) return;
    setState(() => _busy = true);
    try {
      await RummyService.instance.drawFromClosed(widget.roomId, widget.playerId);
      SoundService.instance.playCardSlap();
      GameLogger.instance.rummyDraw(
        roomId: widget.roomId,
        playerId: widget.playerId,
        playerName: widget.playerName,
        fromOpen: false,
        handSizeAfter: (_state?.players[widget.playerId]?.hand.length ?? 0),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _drawFromOpen() async {
    if (_busy || !_isMyTurn || !_isDrawPhase) return;
    final state = _state;
    if (state?.topOfOpen == null) return;
    final drawnCard = state!.topOfOpen?.toString();
    setState(() => _busy = true);
    try {
      await RummyService.instance.drawFromOpen(widget.roomId, widget.playerId);
      SoundService.instance.playCardSlap();
      GameLogger.instance.rummyDraw(
        roomId: widget.roomId,
        playerId: widget.playerId,
        playerName: widget.playerName,
        fromOpen: true,
        cardDrawn: drawnCard,
        handSizeAfter: (_state?.players[widget.playerId]?.hand.length ?? 0),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discardCard(int cardIdx) async {
    if (_busy || !_isMyTurn || !_isDiscardPhase) return;
    final hand = _state?.players[widget.playerId]?.hand ?? [];
    final cardLabel = cardIdx < hand.length ? hand[cardIdx].toString() : null;
    setState(() => _busy = true);
    try {
      await RummyService.instance.discardCard(
          widget.roomId, widget.playerId, cardIdx);
      SoundService.instance.playCardSlap();
      if (cardLabel != null) {
        GameLogger.instance.rummyDiscard(
          roomId: widget.roomId,
          playerId: widget.playerId,
          playerName: widget.playerName,
          cardLabel: cardLabel,
          handSizeAfter: (hand.length - 1).clamp(0, 99),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exitGame() async {
    await _sub?.cancel();
    _sub = null;
    await RummyService.instance.leaveRoom(widget.roomId, widget.playerId);
    if (!mounted) return;
    final nav = Navigator.of(context);
    await AdMobService.instance.showInterstitialAsync(context);
    nav.popUntil((r) => r.isFirst);
  }

  void _confirmDrop() {
    if (!_isMyTurn) return;
    final penalty = _isDrawPhase ? 20 : 40;
    final label = _isDrawPhase ? 'First drop' : 'Middle drop';
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0a0820),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'You will incur a $penalty-point penalty and leave the game.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await RummyService.instance.dropPlayer(widget.roomId, widget.playerId);
              if (!mounted) return;
              final nav = Navigator.of(context);
              await AdMobService.instance.showInterstitialAsync(context);
              nav.popUntil((r) => r.isFirst);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('DROP', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openDeclareSheet() {
    if (!_isMyTurn || !_isDiscardPhase) return;
    final state = _state;
    if (state == null) return;
    final hand = state.players[widget.playerId]?.hand ?? [];
    if (hand.length < 14) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeclareSheet(
        hand: hand,
        wildRank: state.wildJoker.rank,
        onDeclare: (melds, discardIdx) async {
          final error = await RummyService.instance.declareGame(
            widget.roomId,
            widget.playerId,
            melds,
          );
          if (!mounted) return;
          if (error != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Invalid: $error'),
              backgroundColor: Colors.red.shade700,
            ));
          }
          // Success path: sheet closes, gameStream fires gameOver overlay
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF04061a),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF4FC3F7))),
      );
    }

    final me = state.players[widget.playerId];
    final opponents = state.activePlayers
        .where((p) => p.id != widget.playerId)
        .toList();

    // Ensure every opponent has a GlobalKey
    for (final p in opponents) {
      _opponentKeys.putIfAbsent(p.id, () => GlobalKey());
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF04061a),
        body: Stack(
          children: [
            SafeArea(
              child: Column(
                children: [
              // ── Top bar ──────────────────────────────────────
              _TopBar(
                wildJoker: state.wildJoker,
                muted: _isMuted,
                onToggleMute: () => setState(() {
                  _isMuted = !_isMuted;
                  SoundService.instance.toggleMute();
                }),
                onExit: _confirmExit,
              ),

              // ── Opponents ────────────────────────────────────
              Flexible(
                fit: FlexFit.loose,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 80),
                  child: _OpponentsRow(
                    players: opponents,
                    currentTurn: state.currentTurn,
                    wildRank: state.wildJoker.rank,
                    opponentKeys: _opponentKeys,
                  ),
                ),
              ),

              // ── Table (decks) ─────────────────────────────────
              Expanded(
                flex: 3,
                child: _TableArea(
                  state: state,
                  isMyTurn: _isMyTurn,
                  isDrawPhase: _isDrawPhase,
                  busy: _busy,
                  onDrawClosed: _drawFromClosed,
                  onDrawOpen: _drawFromOpen,
                  closedDeckKey: _closedDeckKey,
                  openDeckKey: _openDeckKey,
                ),
              ),

              // ── Status bar ────────────────────────────────────
              _StatusBar(
                isMyTurn: _isMyTurn,
                phase: state.phase,
                currentPlayerName:
                    state.players[state.currentTurn]?.name ?? '',
                myId: widget.playerId,
              ),

              // ── My hand ───────────────────────────────────────
              Expanded(
                flex: 4,
                child: _MyHand(
                  hand: me?.hand ?? [],
                  isMyTurn: _isMyTurn,
                  isDiscardPhase: _isDiscardPhase,
                  wildRank: state.wildJoker.rank,
                  busy: _busy,
                  onCardTap: _discardCard,
                ),
              ),

              // ── Action bar ────────────────────────────────────
              _ActionBar(
                isMyTurn: _isMyTurn,
                canDeclare: _isMyTurn && _isDiscardPhase,
                onDeclare: _openDeclareSheet,
                onDrop: _confirmDrop,
              ),

              const Flexible(fit: FlexFit.loose, child: AdBannerWidget()),
                ],
              ),
            ),
            // ── Flying card overlay ───────────────────────────
            if (_flyCard != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: _FlyCardOverlay(fly: _flyCard!),
                ),
              ),

            // ── Game over overlay ─────────────────────────────
            if (state.phase == RummyPhase.gameOver)
              Positioned.fill(
                child: _GameOverOverlay(
                  state: state,
                  myId: widget.playerId,
                  onPlayAgain: () => Navigator.of(context)
                      .popUntil((r) => r.isFirst),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmExit() {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0a0820),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Leave game?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'You will forfeit this round.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('STAY',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _exitGame();
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE63946)),
            child: const Text('LEAVE',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ── Flying card overlay ───────────────────────────────────────────────────────

class _FlyCardOverlay extends StatelessWidget {
  final _FlyCard fly;
  const _FlyCardOverlay({required this.fly});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeInOut,
      builder: (context2, t, child2) {
        final pos = Offset.lerp(fly.start, fly.end, t)!;
        // Arc: lift card up in the middle of the flight
        final arc = -sin(t * pi) * 55.0;
        final rot = sin(t * pi) *
            (fly.end.dx > fly.start.dx ? 0.25 : -0.25);
        return Stack(
          children: [
            Positioned(
              left: pos.dx - 32,
              top:  pos.dy - 45 + arc,
              child: Transform.rotate(
                angle: rot,
                child: fly.card != null
                    ? _RummyCardFace(
                        card: fly.card!,
                        wildRank: fly.wildRank,
                        width: 64,
                        height: 90,
                      )
                    : const _CardBack(width: 64, height: 90),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final RummyCard wildJoker;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onExit;

  const _TopBar({
    required this.wildJoker,
    required this.muted,
    required this.onToggleMute,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.black26,
      child: Row(
        children: [
          // Wild joker indicator
          Row(
            children: [
              Text(
                'Wild: ',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
              ),
              _MiniCard(card: wildJoker, isWild: false),
              Text(
                '  +all ${wildJoker.rankLabel}s',
                style: TextStyle(
                    color: Colors.amber.withValues(alpha: 0.7), fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Color(0xFF4FC3F7), Color(0xFF1565C0)],
            ).createShader(b),
            child: const Text('RUMMY',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: Colors.white)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => showHowToPlay(context, game: 'rummy'),
            child: Icon(Icons.help_outline_rounded,
                color: Colors.white.withValues(alpha: 0.45), size: 20),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onToggleMute,
            child: Icon(
              muted ? Icons.volume_off : Icons.volume_up,
              color: Colors.white.withValues(alpha: 0.45),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onExit,
            child: Icon(Icons.exit_to_app,
                color: Colors.white.withValues(alpha: 0.45), size: 20),
          ),
        ],
      ),
    );
  }
}

// ── Opponents row ─────────────────────────────────────────────────────────────

class _OpponentsRow extends StatelessWidget {
  final List<RummyPlayer> players;
  final String currentTurn;
  final int wildRank;
  final Map<String, GlobalKey> opponentKeys;

  const _OpponentsRow({
    required this.players,
    required this.currentTurn,
    required this.wildRank,
    required this.opponentKeys,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF070920),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: players.map((p) {
          final isTheirTurn = p.id == currentTurn;
          return _OpponentTile(
            key: opponentKeys[p.id],
            player: p,
            isTheirTurn: isTheirTurn,
            wildRank: wildRank,
          );
        }).toList(),
      ),
    );
  }
}

class _OpponentTile extends StatelessWidget {
  final RummyPlayer player;
  final bool isTheirTurn;
  final int wildRank;

  const _OpponentTile({
    super.key,
    required this.player,
    required this.isTheirTurn,
    required this.wildRank,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isTheirTurn
            ? const Color(0xFF1565C0).withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTheirTurn
              ? const Color(0xFF4FC3F7).withValues(alpha: 0.6)
              : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LocalPlayerAvatar(
            radius: 16,
            playerId: player.id,
            playerName: player.name,
          ),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                player.name.replaceAll('_', ' '),
                style: TextStyle(
                  color: isTheirTurn ? const Color(0xFF4FC3F7) : Colors.white,
                  fontSize: 11,
                  fontWeight: isTheirTurn ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  Text(
                    '${player.handSize} cards',
                    style: TextStyle(
                      color: player.handSize <= 3
                          ? Colors.redAccent
                          : Colors.white.withValues(alpha: 0.4),
                      fontSize: 9,
                      fontWeight: player.handSize <= 3
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  if (isTheirTurn) ...[
                    const SizedBox(width: 4),
                    Text('thinking…',
                        style: TextStyle(
                          color: const Color(0xFF4FC3F7).withValues(alpha: 0.7),
                          fontSize: 9,
                        ))
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .fadeIn(duration: 500.ms),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Table area ────────────────────────────────────────────────────────────────

class _TableArea extends StatelessWidget {
  final RummyGameState state;
  final bool isMyTurn;
  final bool isDrawPhase;
  final bool busy;
  final VoidCallback onDrawClosed;
  final VoidCallback onDrawOpen;
  final GlobalKey closedDeckKey;
  final GlobalKey openDeckKey;

  const _TableArea({
    required this.state,
    required this.isMyTurn,
    required this.isDrawPhase,
    required this.busy,
    required this.onDrawClosed,
    required this.onDrawOpen,
    required this.closedDeckKey,
    required this.openDeckKey,
  });

  @override
  Widget build(BuildContext context) {
    final canDraw = isMyTurn && isDrawPhase && !busy;
    final topOpen = state.topOfOpen;

    return Container(
      color: const Color(0xFF0d1230),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Closed deck
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: canDraw ? onDrawClosed : null,
                  child: AnimatedContainer(
                    key: closedDeckKey,
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: canDraw
                          ? [
                              BoxShadow(
                                color: const Color(0xFF4FC3F7)
                                    .withValues(alpha: 0.4),
                                blurRadius: 16,
                                spreadRadius: 2,
                              )
                            ]
                          : null,
                    ),
                    child: _CardBack(
                      width: 64,
                      height: 90,
                      highlighted: canDraw,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${state.closedDeckCount} cards',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'DRAW',
                  style: TextStyle(
                    color: canDraw
                        ? const Color(0xFF4FC3F7)
                        : Colors.white.withValues(alpha: 0.2),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),

            const SizedBox(width: 32),

            // Open deck
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: canDraw && topOpen != null ? onDrawOpen : null,
                  child: AnimatedContainer(
                    key: openDeckKey,
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: canDraw && topOpen != null
                          ? [
                              BoxShadow(
                                color: const Color(0xFF4FC3F7)
                                    .withValues(alpha: 0.3),
                                blurRadius: 12,
                              )
                            ]
                          : null,
                    ),
                    child: topOpen != null
                        ? _RummyCardFace(
                            card: topOpen,
                            wildRank: state.wildJoker.rank,
                            width: 64,
                            height: 90,
                            glow: canDraw,
                          )
                        : _EmptySlot(width: 64, height: 90),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${state.openDeck.length} discarded',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'PICK UP',
                  style: TextStyle(
                    color: canDraw && topOpen != null
                        ? const Color(0xFF4FC3F7)
                        : Colors.white.withValues(alpha: 0.2),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status bar ────────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final bool isMyTurn;
  final RummyPhase phase;
  final String currentPlayerName;
  final String myId;

  const _StatusBar({
    required this.isMyTurn,
    required this.phase,
    required this.currentPlayerName,
    required this.myId,
  });

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;

    if (!isMyTurn) {
      text = '${currentPlayerName.replaceAll('_', ' ')} is playing…';
      color = Colors.white.withValues(alpha: 0.35);
    } else if (phase == RummyPhase.draw) {
      text = 'Draw a card from either deck';
      color = const Color(0xFF4FC3F7);
    } else {
      text = 'Tap a card to discard';
      color = const Color(0xFF4FC3F7);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      color: const Color(0xFF070920),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── My hand ───────────────────────────────────────────────────────────────────

class _MyHand extends StatelessWidget {
  final List<RummyCard> hand;
  final bool isMyTurn;
  final bool isDiscardPhase;
  final int wildRank;
  final bool busy;
  final void Function(int) onCardTap;

  const _MyHand({
    required this.hand,
    required this.isMyTurn,
    required this.isDiscardPhase,
    required this.wildRank,
    required this.busy,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    if (hand.isEmpty) {
      return Container(
        color: const Color(0xFF090c25),
        alignment: Alignment.center,
        child: const Text('🎉 Hand empty!',
            style: TextStyle(color: Colors.white54, fontSize: 16)),
      );
    }

    final canDiscard = isMyTurn && isDiscardPhase && !busy;

    // Group by suit: jokers last
    final groups = <int, List<MapEntry<int, RummyCard>>>{
      0: [], 1: [], 2: [], 3: [], -1: [], // -1 = jokers
    };
    for (final e in hand.asMap().entries) {
      final key = e.value.isPrintedJoker ? -1 : e.value.suit;
      groups[key]!.add(e);
    }
    // Sort within each suit by rank
    for (final list in groups.values) {
      list.sort((a, b) => a.value.rank.compareTo(b.value.rank));
    }

    final suits = [0, 1, 2, 3, -1]
        .where((s) => groups[s]!.isNotEmpty)
        .toList();

    const double cardH = 85.0;
    const double peekH = 22.0;

    return Container(
      color: const Color(0xFF090c25),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      child: LayoutBuilder(builder: (context, constraints) {
        final colH = (MediaQuery.of(context).size.height * 0.26)
            .clamp(120.0, 200.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: suits.map((suit) {
            final cards = groups[suit]!;
            final isRed = suit == 1 || suit == 2;
            final suitSymbol = switch (suit) {
              0 => '♠',
              1 => '♥',
              2 => '♦',
              3 => '♣',
              _ => '★',
            };
            final count = cards.length;
            final double offset = count <= 1 ? 0 : peekH;

            final ordered = List<MapEntry<int, MapEntry<int, RummyCard>>>.from(
              cards.asMap().entries,
            );

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Suit header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: canDiscard
                            ? (isRed
                                ? Colors.red.shade800.withValues(alpha: 0.4)
                                : const Color(0xFF1565C0)
                                    .withValues(alpha: 0.4))
                            : Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$suitSymbol ${cards.length}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: suit == -1
                              ? Colors.amber
                              : (isRed
                                  ? Colors.red.shade200
                                  : Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: colH,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: ordered.map((entry) {
                          final stackIdx = entry.key;
                          final globalIdx = entry.value.key;
                          final card = entry.value.value;
                          final isWild = !card.isPrintedJoker &&
                              card.rank == wildRank;

                          return Positioned(
                            top: stackIdx * offset,
                            left: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: canDiscard
                                  ? () => onCardTap(globalIdx)
                                  : null,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                height: cardH,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: isWild
                                      ? Border.all(
                                          color: Colors.amber
                                              .withValues(alpha: 0.5),
                                          width: 1.5)
                                      : null,
                                ),
                                child: _RummyCardFace(
                                  card: card,
                                  wildRank: wildRank,
                                  width: double.infinity,
                                  height: cardH,
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
        );
      }),
    );
  }
}

// ── Action bar ────────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  final bool isMyTurn;
  final bool canDeclare;
  final VoidCallback onDeclare;
  final VoidCallback onDrop;

  const _ActionBar({
    required this.isMyTurn,
    required this.canDeclare,
    required this.onDeclare,
    required this.onDrop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black26,
      child: Row(
        children: [
          OutlinedButton(
            onPressed: isMyTurn ? onDrop : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: BorderSide(
                  color: isMyTurn
                      ? Colors.redAccent.withValues(alpha: 0.5)
                      : Colors.white12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              'DROP',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: isMyTurn
                    ? Colors.redAccent
                    : Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: canDeclare ? onDeclare : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            child: Text(
              'DECLARE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: canDeclare
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card face widget ──────────────────────────────────────────────────────────

class _RummyCardFace extends StatelessWidget {
  final RummyCard card;
  final int wildRank;
  final double width;
  final double height;
  final bool glow;

  const _RummyCardFace({
    required this.card,
    required this.wildRank,
    required this.width,
    required this.height,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    if (card.isPrintedJoker) return _PrintedJokerCard(width: width, height: height);

    final isWild = card.rank == wildRank;
    final color = card.isRed ? const Color(0xFFD32F2F) : const Color(0xFF1A1A1A);

    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isWild
              ? Colors.amber
              : glow
                  ? const Color(0xFF4FC3F7).withValues(alpha: 0.6)
                  : const Color(0xFFDDDDDD),
          width: isWild || glow ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 3,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          children: [
            // Top-left
            Positioned(
              top: 3,
              left: 4,
              child: _CardLabel(
                  rank: card.rankLabel,
                  suit: card.suitSymbol,
                  color: color),
            ),
            // Center suit
            Align(
              alignment: const Alignment(0, 0.15),
              child: Text(
                card.suitSymbol,
                style: TextStyle(
                  fontSize: height * 0.38,
                  color: color.withValues(alpha: 0.8),
                  height: 1,
                ),
              ),
            ),
            // Bottom-right
            Positioned(
              bottom: 3,
              right: 4,
              child: Transform.rotate(
                angle: 3.14159,
                child: _CardLabel(
                    rank: card.rankLabel,
                    suit: card.suitSymbol,
                    color: color),
              ),
            ),
            // Wild joker badge
            if (isWild)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('W',
                      style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                          color: Colors.black)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CardLabel extends StatelessWidget {
  final String rank;
  final String suit;
  final Color color;

  const _CardLabel(
      {required this.rank, required this.suit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(rank,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: color,
                height: 1)),
        Text(suit,
            style: TextStyle(fontSize: 10, color: color, height: 1)),
      ],
    );
  }
}

class _PrintedJokerCard extends StatelessWidget {
  final double width;
  final double height;

  const _PrintedJokerCard({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final w = width == double.infinity ? null : width;
    final emojiSize = (height * 0.52).clamp(28.0, 56.0);
    final cornerSize = (height * 0.12).clamp(8.0, 14.0);

    return Container(
      width: w,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1a0033), Color(0xFF3d005e), Color(0xFF1a0033)],
          stops: [0.0, 0.5, 1.0],
        ),
        border: Border.all(color: Colors.amber, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.45),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            // Diamond pattern background
            Positioned.fill(
              child: CustomPaint(painter: _DiamondPatternPainter()),
            ),

            // Corner label top-left
            Positioned(
              top: 3,
              left: 4,
              child: _JokerCornerLabel(fontSize: cornerSize),
            ),

            // Corner label bottom-right (rotated)
            Positioned(
              bottom: 3,
              right: 4,
              child: Transform.rotate(
                angle: pi,
                child: _JokerCornerLabel(fontSize: cornerSize),
              ),
            ),

            // Central emoji — the "image"
            Center(
              child: Text(
                '🃏',
                style: TextStyle(fontSize: emojiSize, height: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JokerCornerLabel extends StatelessWidget {
  final double fontSize;
  const _JokerCornerLabel({required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('J',
            style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                color: Colors.amber,
                height: 1)),
        Text('★',
            style: TextStyle(
                fontSize: fontSize * 0.7,
                color: Colors.amber.shade300,
                height: 1)),
      ],
    );
  }
}

class _DiamondPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.amber.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;

    const spacing = 14.0;
    const half = 5.0;

    for (double x = 0; x < size.width + spacing; x += spacing) {
      for (double y = 0; y < size.height + spacing; y += spacing) {
        final path = Path()
          ..moveTo(x, y - half)
          ..lineTo(x + half, y)
          ..lineTo(x, y + half)
          ..lineTo(x - half, y)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DiamondPatternPainter old) => false;
}

class _CardBack extends StatelessWidget {
  final double width;
  final double height;
  final bool highlighted;

  const _CardBack(
      {required this.width,
      required this.height,
      this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1565C0), Color(0xFF0d47a1)],
        ),
        border: Border.all(
          color: highlighted
              ? const Color(0xFF4FC3F7)
              : const Color(0xFF1976D2),
          width: highlighted ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 4, offset: Offset(1, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
                color: const Color(0xFF4FC3F7).withValues(alpha: 0.3),
                width: 1.5),
          ),
          child: Center(
            child: Icon(Icons.style,
                color: const Color(0xFF4FC3F7).withValues(alpha: 0.4),
                size: width * 0.4),
          ),
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  final double width;
  final double height;

  const _EmptySlot({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.1), style: BorderStyle.solid),
      ),
      child: Center(
        child: Icon(Icons.add,
            color: Colors.white.withValues(alpha: 0.15), size: 20),
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final RummyCard card;
  final bool isWild;

  const _MiniCard({required this.card, required this.isWild});

  @override
  Widget build(BuildContext context) {
    if (card.isPrintedJoker) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.amber, width: 1.5),
        ),
        child: const Text('JKR',
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber)),
      );
    }
    final color = card.isRed ? const Color(0xFFD32F2F) : const Color(0xFF1A1A1A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Text(
        '${card.rankLabel}${card.suitSymbol}',
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

// ── Game over overlay ─────────────────────────────────────────────────────────

class _GameOverOverlay extends StatelessWidget {
  final RummyGameState state;
  final String myId;
  final VoidCallback onPlayAgain;

  const _GameOverOverlay({
    required this.state,
    required this.myId,
    required this.onPlayAgain,
  });

  @override
  Widget build(BuildContext context) {
    final winner = state.players[state.winnerId]?.name ?? 'Unknown';
    final iWon = state.winnerId == myId;

    // Build sorted score rows: winner first, then ascending points
    final allIds = state.players.keys.toList();
    allIds.sort((a, b) {
      final sa = state.scores[a] ?? 0;
      final sb = state.scores[b] ?? 0;
      return sa.compareTo(sb);
    });

    return Container(
      color: Colors.black.withValues(alpha: 0.82),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF0d1230),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: iWon
                  ? Colors.amber.withValues(alpha: 0.6)
                  : const Color(0xFF4FC3F7).withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (iWon ? Colors.amber : const Color(0xFF1565C0))
                    .withValues(alpha: 0.25),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(iWon ? '🏆' : '🃏',
                  style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              Text(
                iWon ? 'You Win!' : '$winner Wins!',
                style: TextStyle(
                  color: iWon ? Colors.amber : Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 20),

              // Score table
              ...allIds.map((id) {
                final player = state.players[id];
                if (player == null) return const SizedBox.shrink();
                final score = state.scores[id] ?? 0;
                final isWinner = id == state.winnerId;
                final isMe = id == myId;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isWinner
                        ? Colors.amber.withValues(alpha: 0.1)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isWinner
                          ? Colors.amber.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (isWinner)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Text('👑',
                              style: TextStyle(fontSize: 14)),
                        ),
                      Expanded(
                        child: Text(
                          isMe ? 'You' : player.name.replaceAll('_', ' '),
                          style: TextStyle(
                            color: isWinner ? Colors.amber : Colors.white,
                            fontWeight: isWinner
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        isWinner ? '0 pts' : '$score pts',
                        style: TextStyle(
                          color: isWinner
                              ? Colors.amber
                              : score >= 60
                                  ? Colors.redAccent
                                  : Colors.white.withValues(alpha: 0.7),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: onPlayAgain,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'PLAY AGAIN',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Declare sheet ─────────────────────────────────────────────────────────────

class _DeclareSheet extends StatefulWidget {
  final List<RummyCard> hand; // 14 cards (post-draw)
  final int wildRank;
  final Future<void> Function(List<List<RummyCard>> melds, int discardIdx) onDeclare;

  const _DeclareSheet({
    required this.hand,
    required this.wildRank,
    required this.onDeclare,
  });

  @override
  State<_DeclareSheet> createState() => _DeclareSheetState();
}

class _DeclareSheetState extends State<_DeclareSheet> {
  // groupOf[i] = group index (0 = discard, 1-4 = melds)
  late final List<int> _groupOf;
  bool _submitting = false;

  static const _groupColors = [
    Colors.white38,       // 0 = discard (grey)
    Color(0xFF1565C0),    // 1 = blue
    Color(0xFF2E7D32),    // 2 = green
    Color(0xFFE65100),    // 3 = orange
    Color(0xFF6A1B9A),    // 4 = purple
  ];
  static const _groupLabels = ['Discard', 'G1', 'G2', 'G3', 'G4'];

  @override
  void initState() {
    super.initState();
    _groupOf = List.filled(widget.hand.length, 0);
  }

  // Cards in each group
  List<int> _indicesFor(int g) => [
        for (int i = 0; i < _groupOf.length; i++)
          if (_groupOf[i] == g) i
      ];

  // Build meld lists (groups 1-4)
  List<List<RummyCard>> get _melds => [
        for (int g = 1; g <= 4; g++)
          [for (final i in _indicesFor(g)) widget.hand[i]]
      ].where((m) => m.isNotEmpty).toList();

  int? get _discardIdx {
    final d = _indicesFor(0);
    return d.length == 1 ? d.first : null;
  }

  // Live validation
  String? get _validationError {
    final d = _indicesFor(0);
    if (d.length != 1) return 'Mark exactly 1 card as Discard';
    return validateDeclaration(_melds, widget.wildRank);
  }

  bool get _isValid => _validationError == null;

  // Check list for UI feedback
  bool get _hasDiscard => _indicesFor(0).length == 1;
  bool get _hasPureSeq => _melds.any((m) => isPureSequence(m, widget.wildRank));
  bool get _hasTwoSeqs =>
      _melds.where((m) => isValidSequence(m, widget.wildRank)).length >= 2;
  bool get _allGrouped {
    final grouped = _melds.fold(0, (s, m) => s + m.length);
    return grouped == 13 && _hasDiscard;
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFF0a0820),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                const Text('Arrange Melds',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close,
                      color: Colors.white.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),

          // Validation chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _ValidationChip('1 discard', _hasDiscard),
                const SizedBox(width: 8),
                _ValidationChip('Pure seq', _hasPureSeq),
                const SizedBox(width: 8),
                _ValidationChip('2+ seqs', _hasTwoSeqs),
                const SizedBox(width: 8),
                _ValidationChip('All grouped', _allGrouped),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Card grid
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // All 14 cards — tap to cycle group
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(widget.hand.length, (i) {
                      final card = widget.hand[i];
                      final g = _groupOf[i];
                      final color = _groupColors[g];
                      return GestureDetector(
                        onTap: () => setState(
                            () => _groupOf[i] = (_groupOf[i] + 1) % 5),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: g == 0
                                        ? Colors.white24
                                        : color,
                                    width: 2),
                              ),
                              child: card.isPrintedJoker
                                  ? _PrintedJokerCard(width: 52, height: 72)
                                  : _RummyCardFace(
                                      card: card,
                                      wildRank: widget.wildRank,
                                      width: 52,
                                      height: 72,
                                    ),
                            ),
                            // Group badge
                            Positioned(
                              top: -6,
                              right: -6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: g == 0 ? Colors.grey : color,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: const Color(0xFF0a0820),
                                      width: 1.5),
                                ),
                                child: Text(
                                  _groupLabels[g],
                                  style: const TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 16),

                  // Group preview rows
                  for (int g = 0; g <= 4; g++) ...[
                    if (_indicesFor(g).isNotEmpty) ...[
                      _GroupRow(
                        label: _groupLabels[g],
                        color: _groupColors[g],
                        cards: [
                          for (final i in _indicesFor(g)) widget.hand[i]
                        ],
                        wildRank: widget.wildRank,
                        isValid: g == 0
                            ? _indicesFor(g).length == 1
                            : isValidMeld([
                                for (final i in _indicesFor(g)) widget.hand[i]
                              ], widget.wildRank),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
            ),
          ),

          // Declare button
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isValid && !_submitting
                    ? () async {
                        setState(() => _submitting = true);
                        final nav = Navigator.of(context);
                        await widget.onDeclare(_melds, _discardIdx!);
                        if (mounted) nav.pop();
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _isValid
                            ? 'DECLARE  ✓'
                            : (_validationError ?? 'DECLARE'),
                        style: TextStyle(
                          color: _isValid
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.3),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          fontSize: 13,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValidationChip extends StatelessWidget {
  final String label;
  final bool ok;
  const _ValidationChip(this.label, this.ok);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ok
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ok
              ? Colors.green.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Text(
        '${ok ? "✓" : "·"} $label',
        style: TextStyle(
          color: ok ? Colors.greenAccent : Colors.white38,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  final String label;
  final Color color;
  final List<RummyCard> cards;
  final int wildRank;
  final bool isValid;

  const _GroupRow({
    required this.label,
    required this.color,
    required this.cards,
    required this.wildRank,
    required this.isValid,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
              Icon(isValid ? Icons.check_circle : Icons.cancel,
                  color: isValid ? Colors.greenAccent : Colors.red.shade300,
                  size: 12),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: cards.map((card) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: card.isPrintedJoker
                    ? _PrintedJokerCard(width: 40, height: 56)
                    : _RummyCardFace(
                        card: card,
                        wildRank: wildRank,
                        width: 40,
                        height: 56,
                      ),
              )).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
