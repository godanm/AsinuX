import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/card_model.dart';
import '../models/teen_patti_state.dart';
import '../services/admob_service.dart';
import '../services/sound_service.dart';
import '../services/stats_service.dart';
import '../services/teen_patti_service.dart';
import '../services/teen_patti_bot_service.dart';
import '../widgets/ad_banner_widget.dart';
import '../widgets/card_widget.dart';
import '../widgets/how_to_play_overlay.dart';

class TeenPattiGameScreen extends StatefulWidget {
  final String roomId;
  final String playerId;

  const TeenPattiGameScreen({
    super.key,
    required this.roomId,
    required this.playerId,
  });

  @override
  State<TeenPattiGameScreen> createState() => _TeenPattiGameScreenState();
}

class _TeenPattiGameScreenState extends State<TeenPattiGameScreen> {
  StreamSubscription<TeenPattiState?>? _stateSub;
  StreamSubscription<List<PlayingCard>>? _cardsSub;

  TeenPattiState? _state;
  List<PlayingCard> _myCards = [];
  bool _busy = false;
  Timer? _turnTimer;
  int _secondsLeft = 20;
  bool _isMuted = false;
  String? _lastSoundTurn;
  bool _roundAdFired = false;
  bool _statsRecorded = false;

  static const _accent = Color(0xFF2979FF);

  @override
  void initState() {
    super.initState();
    AdMobService.instance.suppressAppOpenAd = true;
    _stateSub = TeenPattiService.instance
        .roomStream(widget.roomId)
        .listen(_onState);
    _cardsSub = TeenPattiService.instance
        .cardsStream(widget.roomId, widget.playerId)
        .listen((c) {
      if (mounted) setState(() => _myCards = c);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _cardsSub?.cancel();
    _turnTimer?.cancel();
    AdMobService.instance.suppressAppOpenAd = false;
    TeenPattiBotService.instance.stop();
    super.dispose();
  }

  void _onState(TeenPattiState? s) {
    if (!mounted || s == null) return;
    final prev = _state;
    setState(() => _state = s);
    _updateTimer(s);

    // Your-turn sound — once per turn
    if (s.phase == TeenPattiPhase.betting &&
        s.currentTurn == widget.playerId) {
      final key = '${s.roundNumber}:${s.currentTurn}';
      if (_lastSoundTurn != key) {
        _lastSoundTurn = key;
        SoundService.instance.playYourTurn();
      }
    }

    // Payout: win/loss sound + stats + rewarded ad (once per payout)
    if (s.phase == TeenPattiPhase.payout &&
        prev?.phase != TeenPattiPhase.payout) {
      final isWinner = s.winners.contains(widget.playerId);
      if (isWinner) {
        SoundService.instance.playEscape();
      } else {
        SoundService.instance.playDonkey();
      }
      if (!_statsRecorded) {
        _statsRecorded = true;
        if (!widget.playerId.startsWith('bot_')) {
          final potShare = isWinner && s.winners.isNotEmpty
              ? s.pot ~/ s.winners.length
              : 0;
          StatsService.instance.recordTeenPattiRound(
            uid: widget.playerId,
            won: isWinner,
            potShare: potShare,
          );
        }
      }
      if (!_roundAdFired) {
        _roundAdFired = true;
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) AdMobService.instance.showRewardedAsync(context);
        });
      }
    }

    // Reset per-round flags when a new round starts
    if (s.phase == TeenPattiPhase.betting &&
        prev?.phase == TeenPattiPhase.waiting) {
      _roundAdFired = false;
      _statsRecorded = false;
    }
  }

  void _updateTimer(TeenPattiState s) {
    _turnTimer?.cancel();
    if (s.phase != TeenPattiPhase.betting ||
        s.currentTurn != widget.playerId) { return; }
    setState(() => _secondsLeft = 20);
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_secondsLeft > 0) { _secondsLeft--; }
        else { t.cancel(); }
      });
    });
  }

  bool get _isMyTurn =>
      _state?.phase == TeenPattiPhase.betting &&
      _state?.currentTurn == widget.playerId;

  TeenPattiPlayer? get _me => _state?.players[widget.playerId];

  Future<void> _act(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startNextRound(TeenPattiState state) async {
    await TeenPattiService.instance.startNextRound(state);
    final fresh =
        await TeenPattiService.instance.getFreshState(state.roomId);
    if (fresh != null) {
      TeenPattiBotService.instance.start(fresh.roomId);
      await TeenPattiService.instance.startGame(fresh);
    }
  }

  void _leaveGame() {
    TeenPattiBotService.instance.stop();
    TeenPattiService.instance.leaveRoom(widget.roomId, widget.playerId);
    Navigator.pop(context);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0a0008),
        body: Center(
          child: CircularProgressIndicator(color: _accent),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0a0008),
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                _buildHeader(state),
                const SizedBox(height: 8),
                _buildOpponents(state),
                const SizedBox(height: 12),
                _buildPotStrip(state),
                const Spacer(),
                _buildMyHand(state),
                const SizedBox(height: 12),
                _buildActions(state),
                const SizedBox(height: 8),
                const AdBannerWidget(),
              ],
            ),
            if (state.phase == TeenPattiPhase.waiting ||
                state.phase == TeenPattiPhase.showdown)
              _buildProcessingOverlay(),
            if (state.phase == TeenPattiPhase.sideshowPending)
              _buildSideshowOverlay(state),
            if (state.phase == TeenPattiPhase.payout)
              _buildPayoutOverlay(state),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(TeenPattiState state) {
    final me = _me;
    final statusLabel = me == null
        ? ''
        : me.isFolded
            ? 'FOLDED'
            : me.isSeen
                ? 'SEEN'
                : 'BLIND';
    final statusColor = me == null
        ? Colors.white54
        : me.isFolded
            ? Colors.red.shade400
            : me.isSeen
                ? Colors.amber
                : Colors.white60;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white54, size: 20),
            onPressed: _leaveGame,
          ),
          const Spacer(),
          const Text('TEEN PATTI',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Colors.white)),
          const Spacer(),
          if (statusLabel.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(statusLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor)),
            ),
          IconButton(
            icon: Icon(
              _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: Colors.white54, size: 22,
            ),
            onPressed: () => setState(() {
              _isMuted = !_isMuted;
              SoundService.instance.toggleMute();
            }),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded,
                color: Colors.white54, size: 22),
            onPressed: () => showHowToPlay(context, game: 'teen_patti'),
          ),
        ],
      ),
    );
  }

  // ── Opponents ─────────────────────────────────────────────────────────────

  Widget _buildOpponents(TeenPattiState state) {
    final opponents = state.playerOrder
        .where((id) => id != widget.playerId)
        .map((id) => state.players[id])
        .whereType<TeenPattiPlayer>()
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: opponents
            .map((p) => _OpponentSeat(
                  player: p,
                  isCurrentTurn: state.currentTurn == p.id,
                ))
            .toList(),
      ),
    );
  }

  // ── Pot / stake strip ─────────────────────────────────────────────────────

  Widget _buildPotStrip(TeenPattiState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _InfoChip(label: 'POT', value: '${state.pot}'),
            _divider(),
            _InfoChip(label: 'STAKE', value: '${state.currentStake}'),
            if (_isMyTurn) ...[
              _divider(),
              _InfoChip(
                label: 'TIME',
                value: '$_secondsLeft s',
                highlight: _secondsLeft <= 5,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        width: 1,
        height: 24,
        color: Colors.white12,
      );

  // ── My hand ───────────────────────────────────────────────────────────────

  Widget _buildMyHand(TeenPattiState state) {
    final me = _me;
    if (me == null) return const SizedBox();

    final isRevealed = me.isSeen && _myCards.isNotEmpty;

    return Column(
      children: [
        if (_isMyTurn)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'YOUR TURN',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _accent.withValues(alpha: 0.9),
                letterSpacing: 2,
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: isRevealed
              ? _myCards
                  .map((c) => Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 5),
                        child: CardWidget(card: c, width: 64, height: 92),
                      ))
                  .toList()
              : List.generate(
                  3,
                  (_) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: CardBackWidget(width: 64, height: 92),
                  ),
                ),
        ),
        const SizedBox(height: 8),
        if (isRevealed)
          Text(
            evaluateHand(_myCards).label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.amber),
          )
        else
          Text(
            'Cards hidden — tap See Cards to reveal',
            style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.35)),
          ),
      ],
    );
  }

  // ── Action buttons ────────────────────────────────────────────────────────

  Widget _buildActions(TeenPattiState state) {
    final me = _me;
    if (me == null || !_isMyTurn) return const SizedBox(height: 8);

    final active = state.activePlayers;
    final canShow = active.length == 2;
    final canSideshow = me.isSeen &&
        state.lastActorId != null &&
        (state.players[state.lastActorId!]?.isSeen ?? false) &&
        active.length > 2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Row 1: always-available actions
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  'FOLD',
                  Colors.red.shade700,
                  _busy ? null : () {
                    SoundService.instance.playCardSlap();
                    _act(() => TeenPattiService.instance.fold(state, widget.playerId));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  'CHAAL',
                  _accent,
                  _busy ? null : () {
                    SoundService.instance.playCardSlap();
                    _act(() => TeenPattiService.instance.chaal(state, widget.playerId));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  'RAISE',
                  Colors.amber.shade700,
                  _busy ? null : () {
                    SoundService.instance.playCardSlap();
                    _act(() => TeenPattiService.instance.raise(state, widget.playerId));
                  },
                ),
              ),
            ],
          ),
          // Row 2: conditional actions
          if (me.isBlind || canSideshow || canShow) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (me.isBlind)
                  Expanded(
                    child: _ActionButton(
                      'SEE CARDS',
                      Colors.teal,
                      _busy ? null : () {
                        SoundService.instance.playCut();
                        _act(() => TeenPattiService.instance.seeCards(state, widget.playerId));
                      },
                    ),
                  ),
                if (me.isBlind && (canSideshow || canShow))
                  const SizedBox(width: 8),
                if (canSideshow)
                  Expanded(
                    child: _ActionButton(
                      'SIDESHOW',
                      Colors.purple.shade400,
                      _busy ? null : () {
                        SoundService.instance.playCardSlap();
                        _act(() => TeenPattiService.instance.requestSideshow(state, widget.playerId));
                      },
                    ),
                  ),
                if (canSideshow && canShow) const SizedBox(width: 8),
                if (canShow)
                  Expanded(
                    child: _ActionButton(
                      'SHOW',
                      Colors.orange,
                      _busy ? null : () {
                        SoundService.instance.playCardSlap();
                        _act(() => TeenPattiService.instance.callShow(state, widget.playerId));
                      },
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Processing overlay (waiting / showdown) ───────────────────────────────

  Widget _buildProcessingOverlay() {
    return const ColoredBox(
      color: Color(0xAA000000),
      child: Center(
        child: CircularProgressIndicator(color: _accent),
      ),
    );
  }

  // ── Sideshow overlay ──────────────────────────────────────────────────────

  Widget _buildSideshowOverlay(TeenPattiState state) {
    final isTarget = state.sideshowTargetId == widget.playerId;
    final requester =
        state.players[state.sideshowRequesterId ?? '']?.name ?? 'Opponent';

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF12103A),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: _accent.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('SIDESHOW',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 2)),
              const SizedBox(height: 12),
              Text(
                isTarget
                    ? '$requester wants a private sideshow with you.\nLoser folds.'
                    : 'Waiting for sideshow response…',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.8),
                    height: 1.5),
              ),
              if (isTarget) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        'REJECT',
                        Colors.red.shade700,
                        _busy ? null : () {
                          SoundService.instance.playCardSlap();
                          _act(() => TeenPattiService.instance.respondSideshow(state, widget.playerId, false));
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        'ACCEPT',
                        Colors.green.shade600,
                        _busy ? null : () {
                          SoundService.instance.playCut();
                          _act(() => TeenPattiService.instance.respondSideshow(state, widget.playerId, true));
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms);
  }

  // ── Payout overlay ────────────────────────────────────────────────────────

  Widget _buildPayoutOverlay(TeenPattiState state) {
    final me = _me;
    final isWinner = state.winners.contains(widget.playerId);
    final winnerNames = state.winners
        .map((id) => state.players[id]?.name ?? 'Unknown')
        .join(', ');
    final showMyCards = _myCards.isNotEmpty && (me?.isSeen ?? false);

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.78),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0E2A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isWinner
                  ? Colors.amber.withValues(alpha: 0.7)
                  : Colors.red.withValues(alpha: 0.4),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isWinner ? '🎉 YOU WIN!' : '😔 Better luck next time',
                style: TextStyle(
                    fontSize: isWinner ? 22 : 16,
                    fontWeight: FontWeight.w900,
                    color: isWinner ? Colors.amber : Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              if (!isWinner)
                Text('$winnerNames won the pot!',
                    style: const TextStyle(
                        fontSize: 13, color: Colors.white60),
                    textAlign: TextAlign.center),
              Text('Pot: ${state.pot}',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.5))),
              if (showMyCards) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _myCards
                      .map((c) => Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: CardWidget(card: c, width: 56, height: 80),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 6),
                Text(evaluateHand(_myCards).label,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.amber)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white60,
                        side: const BorderSide(color: Colors.white24),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _leaveGame,
                      child: const Text('QUIT'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _busy
                          ? null
                          : () => _act(() => _startNextRound(state)),
                      child: const Text('NEXT ROUND',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.92, 0.92));
  }
}

// ── Opponent seat ─────────────────────────────────────────────────────────────

class _OpponentSeat extends StatelessWidget {
  final TeenPattiPlayer player;
  final bool isCurrentTurn;

  const _OpponentSeat({required this.player, required this.isCurrentTurn});

  @override
  Widget build(BuildContext context) {
    final Color statusColor;
    final String statusLabel;
    if (player.isFolded) {
      statusColor = Colors.red.shade400;
      statusLabel = 'FOLDED';
    } else if (player.isSeen) {
      statusColor = Colors.amber;
      statusLabel = 'SEEN';
    } else {
      statusColor = Colors.white60;
      statusLabel = 'BLIND';
    }

    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: isCurrentTurn
            ? const Color(0xFF2979FF).withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentTurn
              ? const Color(0xFF2979FF).withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.08),
          width: isCurrentTurn ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Three stacked card backs (or X if folded)
          SizedBox(
            height: 38,
            child: player.isFolded
                ? Icon(Icons.block_rounded,
                    color: Colors.red.shade400, size: 24)
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      CardBackWidget(width: 22, height: 32),
                      Positioned(
                          left: 16,
                          child: CardBackWidget(width: 22, height: 32)),
                      Positioned(
                          left: 32,
                          child: CardBackWidget(width: 22, height: 32)),
                    ],
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            player.name,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                  letterSpacing: 0.5),
            ),
          ),
          if (isCurrentTurn) ...[
            const SizedBox(height: 6),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF2979FF)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Info chip ─────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _InfoChip({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.4),
                letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color:
                    highlight ? Colors.red.shade400 : Colors.white)),
      ],
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton(this.label, this.color, this.onPressed);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: onPressed != null ? 1 : 0.4),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      onPressed: onPressed,
      child: Text(label,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
    );
  }
}
