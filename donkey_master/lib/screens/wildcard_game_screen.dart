import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/wildcard_models.dart';
import '../services/stats_service.dart';
import '../services/wildcard_service.dart';
import '../widgets/how_to_play_overlay.dart';

class WildCardGameScreen extends StatefulWidget {
  final String roomId;
  final String playerId;
  final String playerName;

  const WildCardGameScreen({
    super.key,
    required this.roomId,
    required this.playerId,
    required this.playerName,
  });

  @override
  State<WildCardGameScreen> createState() => _WildCardGameScreenState();
}

class _WildCardGameScreenState extends State<WildCardGameScreen> {
  StreamSubscription<WildCardGameState?>? _gameSub;
  StreamSubscription<List<WildPlayCard>?>? _handSub;

  WildCardGameState? _game;
  List<WildPlayCard> _hand = [];
  bool _statsRecorded = false;
  bool _botBusy = false;
  String? _toastMessage;
  Timer? _toastTimer;

  static const _accent = Color(0xFF7B1FA2);
  static const _accentLight = Color(0xFFCE93D8);

  @override
  void initState() {
    super.initState();
    _gameSub = WildCardService.instance
        .gameStream(widget.roomId)
        .listen(_onGameUpdate);
    _handSub = WildCardService.instance
        .handStream(widget.roomId, widget.playerId)
        .listen(_onHandUpdate);
  }

  @override
  void dispose() {
    _gameSub?.cancel();
    _handSub?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  void _onHandUpdate(List<WildPlayCard>? hand) {
    if (!mounted) return;
    debugPrint('[WildCard] _onHandUpdate: ${hand == null ? "null" : "${hand.length} cards: ${hand.map((c) => c.label).join(",")}"}');
    setState(() => _hand = hand ?? []);
  }

  void _onGameUpdate(WildCardGameState? state) {
    if (!mounted) return;
    setState(() => _game = state);

    if (state == null) {
      debugPrint('[WildCard] _onGameUpdate: null state received');
      return;
    }
    debugPrint('[WildCard] _onGameUpdate: phase=${state.phase} currentPlayer=${state.currentPlayerId} idx=${state.currentPlayerIdx} order=${state.playerOrder}');

    if (state.isMyTurn(widget.playerId) && _hand.isNotEmpty) {
      final hasPlayable = _hand.any((c) => c.canPlayOn(state.discardTop, state.currentColor));
      debugPrint('[WildCard] _onGameUpdate: myTurn=true hand=${_hand.map((c) => c.label).join(",")} hasPlayable=$hasPlayable discardTop=${state.discardTop.label} color=${state.currentColor}');
      if (!hasPlayable) {
        _showToast('No playable card — tap the deck to draw');
      }
    }

    if (state.phase == 'gameOver' &&
        !_statsRecorded &&
        !widget.playerId.startsWith('bot_')) {
      _statsRecorded = true;
      final won = state.winner == widget.playerId;
      StatsService.instance.recordWildCardGame(
        uid: widget.playerId,
        won: won,
        wildCardsPlayed: 0,
      );
    }

    _maybeRunBot(state);
  }

  void _maybeRunBot(WildCardGameState state) {
    if (state.phase != 'playing') {
      debugPrint('[WildCard] _maybeRunBot: phase=${state.phase}, skip');
      return;
    }
    final currentPid = state.currentPlayerId;
    if (!currentPid.startsWith('bot_')) {
      debugPrint('[WildCard] _maybeRunBot: current=$currentPid is not a bot, skip');
      return;
    }
    if (_botBusy) {
      debugPrint('[WildCard] _maybeRunBot: _botBusy=true, skip');
      return;
    }

    final isHost = _isHost(state);
    debugPrint('[WildCard] _maybeRunBot: current=$currentPid isHost=$isHost myId=${widget.playerId}');
    if (!isHost) return;

    debugPrint('[WildCard] _maybeRunBot: triggering bot turn for $currentPid');
    _botBusy = true;
    WildCardService.instance.botPlayTurn(widget.roomId).whenComplete(() {
      debugPrint('[WildCard] _maybeRunBot: bot turn complete, resetting _botBusy');
      if (!mounted) return;
      setState(() => _botBusy = false);
      // Game state update may have arrived while _botBusy was true and been
      // skipped — re-check immediately so the next bot isn't left waiting.
      if (_game != null) _maybeRunBot(_game!);
    });
  }

  bool _isHost(WildCardGameState state) {
    final isHost = !widget.playerId.startsWith('bot_');
    debugPrint('[WildCard] _isHost: playerId=${widget.playerId}, result=$isHost, playerOrder=${state.playerOrder}');
    return isHost;
  }

  void _showToast(String msg) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = msg);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  Future<void> _onCardTap(WildPlayCard card) async {
    final game = _game;
    if (game == null || !game.isMyTurn(widget.playerId)) return;
    if (!card.canPlayOn(game.discardTop, game.currentColor)) return;

    WildCardColor? chosenColor;
    if (card.type == WildCardType.wild ||
        card.type == WildCardType.wildDraw4) {
      chosenColor = await _pickColor();
      if (chosenColor == null) return;
    }

    final error = await WildCardService.instance.playCard(
      roomId: widget.roomId,
      playerId: widget.playerId,
      card: card,
      chosenColor: chosenColor,
    );
    if (error != null && mounted) {
      _showToast(error);
    }
  }

  Future<void> _onDeckTap() async {
    final game = _game;
    debugPrint('[WildCard] _onDeckTap: isMyTurn=${game?.isMyTurn(widget.playerId)} phase=${game?.phase}');
    if (game == null || !game.isMyTurn(widget.playerId)) return;
    await WildCardService.instance.drawCard(widget.roomId, widget.playerId);
  }

  Future<WildCardColor?> _pickColor() async {
    return showDialog<WildCardColor>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => _ColorPickerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (game?.phase == 'gameOver') {
          nav.popUntil((r) => r.isFirst);
          return;
        }
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0a0820),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Leave game?',
                style: TextStyle(color: Colors.white)),
            content: const Text(
              'You will forfeit your hand.',
              style: TextStyle(color: Colors.white54),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('STAY',
                    style: TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style:
                    TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: const Text('LEAVE'),
              ),
            ],
          ),
        );
        if (leave == true) {
          await WildCardService.instance
              .leaveRoom(widget.roomId, widget.playerId);
          nav.popUntil((r) => r.isFirst);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF04061a),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(),
                  if (game != null) _buildOpponentsRow(game),
                  const SizedBox(height: 8),
                  if (game != null) _buildGameArea(game),
                  const SizedBox(height: 8),
                  _buildWildCardButton(game),
                  const SizedBox(height: 8),
                  _buildTurnIndicator(game),
                  const SizedBox(height: 8),
                  if (game != null) _buildHand(game),
                  const SizedBox(height: 8),
                ],
              ),

              if (_toastMessage != null)
                Positioned(
                  top: 8,
                  left: 16,
                  right: 16,
                  child: _Toast(message: _toastMessage!),
                ),

              if (game?.phase == 'gameOver')
                _GameOverOverlay(
                  game: game!,
                  myPlayerId: widget.playerId,
                  onDone: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                ),

              if (game == null)
                const Center(
                  child: CircularProgressIndicator(color: _accent),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 8),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Color(0xFF7B1FA2), Color(0xFFCE93D8)],
            ).createShader(b),
            child: const Text(
              'WILD CARD',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          Text(
            widget.playerName,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Colors.white38),
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => showHowToPlay(context, game: 'wildcard'),
          ),
        ],
      ),
    );
  }

  Widget _buildOpponentsRow(WildCardGameState game) {
    final opponents = game.playerOrder
        .where((pid) => pid != widget.playerId)
        .toList();

    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: opponents.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final pid = opponents[i];
          final name = game.playerNames[pid] ?? pid;
          final count = game.cardCounts[pid] ?? 0;
          final isCurrent = game.currentPlayerId == pid;
          return _OpponentCard(
            name: name,
            cardCount: count,
            isCurrentPlayer: isCurrent,
          );
        },
      ),
    );
  }

  Widget _buildGameArea(WildCardGameState game) {
    final isWild = game.discardTop.color == WildCardColor.wild;
    final displayColor = isWild
        ? game.currentColor.colorValue
        : game.discardTop.colorValue;
    final isMyTurn = game.isMyTurn(widget.playerId);
    final mustDraw = isMyTurn &&
        _hand.isNotEmpty &&
        _hand.every((c) => !c.canPlayOn(game.discardTop, game.currentColor));
    final noCards = isMyTurn && _hand.isEmpty;

    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _onDeckTap,
                child: _CardFace(
                  label: '🂠',
                  backgroundColor: const Color(0xFF1a1040),
                  borderColor: (mustDraw || noCards)
                      ? _accentLight
                      : isMyTurn
                          ? _accent
                          : Colors.white.withValues(alpha: 0.15),
                  isGlowing: isMyTurn,
                ).animate(
                  onPlay: (c) => c.repeat(reverse: true),
                ).scaleXY(
                  begin: 1.0,
                  end: (mustDraw || noCards) ? 1.06 : 1.0,
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOut,
                ),
              ),
              const SizedBox(height: 6),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: (mustDraw || noCards) ? 1.0 : 0.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accentLight.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _accentLight.withValues(alpha: 0.6)),
                  ),
                  child: const Text(
                    'TAP TO DRAW',
                    style: TextStyle(
                      color: Color(0xFFCE93D8),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CardFace(
                label: game.discardTop.label,
                backgroundColor: displayColor,
                borderColor: displayColor,
                isGlowing: false,
                textColor: Colors.white,
              ),
              const SizedBox(height: 6),
              _ColorPill(color: game.currentColor, fromWild: isWild),
              const SizedBox(height: 4),
              Text(
                game.direction == 1 ? '↻' : '↺',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWildCardButton(WildCardGameState? game) {
    final hasOneCard = _hand.length == 1;
    final active = hasOneCard && game?.phase == 'playing';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        height: 40,
        child: ElevatedButton(
          onPressed: active ? () => _showToast('Wild Card! 🃏') : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: active ? _accent : Colors.white.withValues(alpha: 0.05),
            disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: Text(
            'Wild Card!',
            style: TextStyle(
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.2),
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTurnIndicator(WildCardGameState? game) {
    if (game == null) return const SizedBox.shrink();
    final isMyTurn = game.isMyTurn(widget.playerId);
    final currentName =
        game.playerNames[game.currentPlayerId] ?? game.currentPlayerId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Container(
          key: ValueKey(game.currentPlayerId),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isMyTurn
                ? _accent.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isMyTurn
                  ? _accent.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Text(
            isMyTurn ? 'Your Turn' : 'Waiting for $currentName…',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isMyTurn ? _accentLight : Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
              fontWeight: isMyTurn ? FontWeight.w900 : FontWeight.normal,
              letterSpacing: isMyTurn ? 1 : 0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHand(WildCardGameState game) {
    final isMyTurn = game.isMyTurn(widget.playerId);

    return SizedBox(
      height: 100,
      child: _hand.isEmpty
          ? Center(
              child: Text(
                'No cards',
                style:
                    TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
              ),
            )
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _hand.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final card = _hand[i];
                final playable = isMyTurn &&
                    card.canPlayOn(game.discardTop, game.currentColor);
                return GestureDetector(
                  onTap: playable ? () => _onCardTap(card) : null,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isMyTurn ? (playable ? 1.0 : 0.4) : 0.7,
                    child: _HandCard(card: card, playable: playable),
                  ),
                );
              },
            ),
    );
  }
}

// ── Color value extension ─────────────────────────────────────────────────────

extension on WildCardColor {
  Color get colorValue {
    switch (this) {
      case WildCardColor.red:
        return const Color(0xFFD32F2F);
      case WildCardColor.blue:
        return const Color(0xFF1565C0);
      case WildCardColor.green:
        return const Color(0xFF2E7D32);
      case WildCardColor.yellow:
        return const Color(0xFFF9A825);
      case WildCardColor.wild:
        return const Color(0xFF37474F);
    }
  }
}

// ── Opponent card widget ──────────────────────────────────────────────────────

class _OpponentCard extends StatelessWidget {
  final String name;
  final int cardCount;
  final bool isCurrentPlayer;

  const _OpponentCard({
    required this.name,
    required this.cardCount,
    required this.isCurrentPlayer,
  });

  static const _accent = Color(0xFF7B1FA2);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isCurrentPlayer
            ? _accent.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentPlayer
              ? _accent.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
          width: isCurrentPlayer ? 1.5 : 1,
        ),
        boxShadow: isCurrentPlayer
            ? [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.3),
                  blurRadius: 10,
                )
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name.length > 8 ? '${name.substring(0, 7)}…' : name,
            style: TextStyle(
              color:
                  isCurrentPlayer ? Colors.white : Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: isCurrentPlayer ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isCurrentPlayer
                  ? _accent.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$cardCount cards',
              style: TextStyle(
                color: isCurrentPlayer
                    ? const Color(0xFFCE93D8)
                    : Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card face widget (deck or discard) ────────────────────────────────────────

class _CardFace extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color borderColor;
  final bool isGlowing;
  final Color textColor;

  const _CardFace({
    required this.label,
    required this.backgroundColor,
    required this.borderColor,
    required this.isGlowing,
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 68,
      height: 96,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: isGlowing ? 2 : 1.5),
        boxShadow: isGlowing
            ? [
                BoxShadow(
                  color: borderColor.withValues(alpha: 0.5),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: label.length > 2 ? 18 : 24,
          fontWeight: FontWeight.w900,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Hand card widget ──────────────────────────────────────────────────────────

class _HandCard extends StatelessWidget {
  final WildPlayCard card;
  final bool playable;

  const _HandCard({required this.card, required this.playable});

  @override
  Widget build(BuildContext context) {
    final bg = card.colorValue;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 60,
      height: 88,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: playable ? Colors.white : Colors.white.withValues(alpha: 0.3),
          width: playable ? 2 : 1,
        ),
        boxShadow: playable
            ? [
                BoxShadow(
                  color: bg.withValues(alpha: 0.6),
                  blurRadius: 12,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            card.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (card.type != WildCardType.number)
            Text(
              card.type == WildCardType.skip
                  ? 'SKIP'
                  : card.type == WildCardType.reverse
                      ? 'REV'
                      : card.type == WildCardType.draw2
                          ? 'D+2'
                          : card.type == WildCardType.wild
                              ? 'WILD'
                              : 'W+4',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 7,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Active color pill ─────────────────────────────────────────────────────────

class _ColorPill extends StatelessWidget {
  final WildCardColor color;
  final bool fromWild;

  const _ColorPill({required this.color, required this.fromWild});

  static const _labels = {
    WildCardColor.red: 'RED',
    WildCardColor.blue: 'BLUE',
    WildCardColor.green: 'GREEN',
    WildCardColor.yellow: 'YELLOW',
    WildCardColor.wild: 'WILD',
  };

  @override
  Widget build(BuildContext context) {
    final c = color.colorValue;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: fromWild ? 0.25 : 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: fromWild ? 0.8 : 0.4), width: fromWild ? 1.5 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            _labels[color] ?? '',
            style: TextStyle(
              color: c,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Color picker dialog ───────────────────────────────────────────────────────

class _ColorPickerDialog extends StatelessWidget {
  const _ColorPickerDialog();

  static const _colors = [
    (WildCardColor.red, Color(0xFFD32F2F), 'RED'),
    (WildCardColor.blue, Color(0xFF1565C0), 'BLUE'),
    (WildCardColor.green, Color(0xFF2E7D32), 'GREEN'),
    (WildCardColor.yellow, Color(0xFFF9A825), 'YELLOW'),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0a0820),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'CHOOSE COLOR',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: _colors.map((entry) {
                final (color, hex, label) = entry;
                return GestureDetector(
                  onTap: () => Navigator.pop(context, color),
                  child: Container(
                    decoration: BoxDecoration(
                      color: hex,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).scale(
        begin: const Offset(0.9, 0.9), duration: 200.ms);
  }
}

// ── Toast ─────────────────────────────────────────────────────────────────────

class _Toast extends StatelessWidget {
  final String message;
  const _Toast({required this.message});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1a0d30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFF7B1FA2).withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🃏', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.3, duration: 200.ms);
  }
}

// ── Game over overlay ─────────────────────────────────────────────────────────

class _GameOverOverlay extends StatelessWidget {
  final WildCardGameState game;
  final String myPlayerId;
  final VoidCallback onDone;

  const _GameOverOverlay({
    required this.game,
    required this.myPlayerId,
    required this.onDone,
  });

  static const _accent = Color(0xFF7B1FA2);

  @override
  Widget build(BuildContext context) {
    final didWin = game.winner == myPlayerId;
    final winnerName =
        game.playerNames[game.winner ?? ''] ?? game.winner ?? '?';

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF0a0820),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: didWin
                  ? _accent.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.1),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                didWin ? '🎉' : '🃏',
                style: const TextStyle(fontSize: 52),
              ),
              const SizedBox(height: 12),
              Text(
                didWin ? 'You won!' : '$winnerName wins!',
                style: TextStyle(
                  color: didWin ? const Color(0xFFCE93D8) : Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                didWin
                    ? 'First to empty their hand!'
                    : 'Better luck next time',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              Column(
                children: game.playerOrder.map((pid) {
                  final name = game.playerNames[pid] ?? pid;
                  final count = game.cardCounts[pid] ?? 0;
                  final isWinner = game.winner == pid;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        if (isWinner)
                          const Text('👑 ',
                              style: TextStyle(fontSize: 12))
                        else
                          const SizedBox(width: 20),
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              color: isWinner
                                  ? const Color(0xFFCE93D8)
                                  : Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                              fontWeight: isWinner
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        Text(
                          isWinner ? '0 cards' : '$count cards',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'DONE',
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
    ).animate().fadeIn(duration: 300.ms);
  }
}
