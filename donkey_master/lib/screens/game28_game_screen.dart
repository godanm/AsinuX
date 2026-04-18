import 'dart:async';
import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../models/game28_state.dart';
import '../services/game28_service.dart';
import '../services/game28_bot_service.dart';
import '../services/admob_service.dart';
import '../services/auth_service.dart';
import '../widgets/card_widget.dart';
import '../widgets/player_avatar.dart';

// ── Constants ──────────────────────────────────────────────────────────────────
const _kTeamA = Color(0xFF00c6ff);
const _kTeamB = Color(0xFFE63946);
const _kGold = Color(0xFFFFD700);
const _kBg = Color(0xFF0a0008);

// ── Screen ────────────────────────────────────────────────────────────────────
class Game28GameScreen extends StatefulWidget {
  final String roomId;
  final String playerId;
  const Game28GameScreen(
      {super.key, required this.roomId, required this.playerId});

  @override
  State<Game28GameScreen> createState() => _Game28GameScreenState();
}

class _Game28GameScreenState extends State<Game28GameScreen> {
  StreamSubscription<Game28State?>? _sub;
  Game28State? _state;
  int? _selectedTrump; // index during trump selection
  bool _trickEndHandled = false;
  Timer? _trickEndTimer;
  Timer? _reviewTimer;
  int _reviewCountdown = 8;

  @override
  void initState() {
    super.initState();
    AdMobService.instance.suppressAppOpenAd = true;
    _sub = Game28Service.instance
        .roomStream(widget.roomId)
        .listen(_onStateChange);
  }

  @override
  void dispose() {
    AdMobService.instance.suppressAppOpenAd = false;
    _sub?.cancel();
    _trickEndTimer?.cancel();
    _reviewTimer?.cancel();
    Game28BotService.instance.stop();
    super.dispose();
  }

  void _onStateChange(Game28State? state) {
    if (!mounted) return;
    if (state == null) {
      // Room deleted
      Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    final prev = _state;
    setState(() => _state = state);

    // Start card-review countdown (auto-advances to bidding)
    if (state.phase == Game28Phase.cardReview &&
        prev?.phase != Game28Phase.cardReview) {
      _reviewTimer?.cancel();
      _reviewCountdown = 8;
      _reviewTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) { t.cancel(); return; }
        if (_reviewCountdown <= 1) {
          t.cancel();
          Game28Service.instance.confirmCardReview(_state!);
        } else {
          setState(() => _reviewCountdown--);
        }
      });
    }

    // Auto-advance trickEnd for human leader
    if (state.phase == Game28Phase.trickEnd &&
        state.currentTurn == widget.playerId &&
        (prev?.phase != Game28Phase.trickEnd ||
            prev?.trickNumber != state.trickNumber)) {
      _trickEndHandled = false;
      _trickEndTimer?.cancel();
      _trickEndTimer = Timer(const Duration(milliseconds: 1800), () {
        if (!mounted || _trickEndHandled) return;
        _trickEndHandled = true;
        Game28Service.instance.startNextTrick(state);
      });
    }
  }

  // ── Card validation ───────────────────────────────────────────────────────

  bool _canPlay(PlayingCard card) {
    final state = _state!;
    if (state.currentTurn != widget.playerId) return false;
    final leadSuit = state.leadSuit;
    if (leadSuit == null) return true; // leader, play anything
    final hand = state.players[widget.playerId]!.hand;
    final hasLead = hand.any((c) => c.suit.index == leadSuit);
    if (hasLead) return card.suit.index == leadSuit;
    return true; // no lead suit — play anything
  }

  Future<void> _playCard(int idx) async {
    final state = _state;
    if (state == null) return;
    await Game28Service.instance.playCard(state, widget.playerId, idx);
  }

  Future<void> _nextRound() async {
    final state = _state;
    if (state == null) return;
    await Game28Service.instance.startNextRound(state);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      return const Scaffold(
        backgroundColor: _kBg,
        body: Center(child: CircularProgressIndicator(color: _kGold)),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        await Game28Service.instance.leaveRoom(state.roomId, widget.playerId);
        return true;
      },
      child: Scaffold(
        backgroundColor: _kBg,
        body: SafeArea(child: _buildPhase(state)),
      ),
    );
  }

  Widget _buildPhase(Game28State state) {
    switch (state.phase) {
      case Game28Phase.cardReview:
        return _CardReviewView(
          state: state,
          playerId: widget.playerId,
          countdown: _reviewCountdown,
          onReady: () {
            _reviewTimer?.cancel();
            Game28Service.instance.confirmCardReview(state);
          },
        );
      case Game28Phase.bidding:
        return _BiddingView(
          state: state,
          playerId: widget.playerId,
          onBid: (v) => Game28Service.instance
              .placeBid(state, widget.playerId, bidValue: v),
          onPass: () =>
              Game28Service.instance.placeBid(state, widget.playerId),
        );
      case Game28Phase.trumpSelection:
        return _TrumpSelectionView(
          state: state,
          playerId: widget.playerId,
          selectedSuit: _selectedTrump,
          onSuitTap: (i) => setState(() => _selectedTrump = i),
          onLock: _selectedTrump == null
              ? null
              : () => Game28Service.instance
                  .selectTrump(state, widget.playerId, _selectedTrump!),
        );
      case Game28Phase.playing:
      case Game28Phase.trickEnd:
        return _GameTableView(
          state: state,
          playerId: widget.playerId,
          canPlay: _canPlay,
          onCardTap: _playCard,
        );
      case Game28Phase.roundEnd:
        return _RoundEndView(
          state: state,
          playerId: widget.playerId,
          onNext: _nextRound,
        );
      case Game28Phase.gameOver:
        return _GameOverView(
          state: state,
          playerId: widget.playerId,
          onHome: () =>
              Navigator.of(context).popUntil((r) => r.isFirst),
          onPlayAgain: _nextRound,
        );
      default:
        return const Center(
            child: CircularProgressIndicator(color: _kGold));
    }
  }
}

// ── Card review view ──────────────────────────────────────────────────────────

class _CardReviewView extends StatelessWidget {
  final Game28State state;
  final String playerId;
  final int countdown;
  final VoidCallback onReady;

  const _CardReviewView({
    required this.state,
    required this.playerId,
    required this.countdown,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    final hand = state.players[playerId]?.hand ?? [];
    final reviewCards = hand.take(4).toList();
    final hiddenCount = (hand.length - 4).clamp(0, 4);

    return Column(
      children: [
        // ── Header ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(
            children: [
              const Text('REVIEW HAND',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      color: Colors.white54)),
              const Spacer(),
              _tag('ROUND ${state.roundNumber}', _kGold),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Info pill ───────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _kGold.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kGold.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Text('⚡', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'These 4 cards determine your bid. The remaining 4 are hidden until played.',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.6)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Section labels ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: _kGold),
                      ),
                      const SizedBox(width: 6),
                      const Text('BID CARDS',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                              color: _kGold)),
                    ],
                  ),
                ),
              ),
              Container(width: 1.5, height: 16, color: Colors.white12),
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      const SizedBox(width: 6),
                      Text('HIDDEN',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                              color: Colors.white.withValues(alpha: 0.3))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // ── Cards ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Face-up: first 4
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: _kGold.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kGold.withValues(alpha: 0.25)),
                    boxShadow: [
                      BoxShadow(
                        color: _kGold.withValues(alpha: 0.08),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: reviewCards
                        .map((c) => CardWidget(card: c, width: 54, height: 76))
                        .toList(),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Face-down: remaining 4
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      hiddenCount,
                      (_) => const CardBackWidget(width: 54, height: 76),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Point summary ───────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _ReviewPointSummary(cards: reviewCards),
        ),

        const Spacer(),

        // ── Ready button with countdown ─────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _FilledBtn(
            'START BIDDING${countdown > 0 ? '  ($countdown)' : ''}',
            onReady,
            color: _kGold,
            textColor: Colors.black,
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}

class _ReviewPointSummary extends StatelessWidget {
  final List<PlayingCard> cards;
  const _ReviewPointSummary({required this.cards});

  @override
  Widget build(BuildContext context) {
    final total = cards.fold(0, (s, c) => s + cardPoints28(c.rank));
    final jacks = cards.where((c) => c.rank == Rank.jack).length;
    final nines = cards.where((c) => c.rank == Rank.nine).length;
    final aces  = cards.where((c) => c.rank == Rank.ace).length;
    final tens  = cards.where((c) => c.rank == Rank.ten).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Text(
            'Visible pts: $total / 28',
            style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.5)),
          ),
          const Spacer(),
          if (jacks > 0) _PtBadge('J×$jacks', _kGold),
          if (nines > 0) _PtBadge('9×$nines', _kTeamA),
          if (aces  > 0) _PtBadge('A×$aces', Colors.greenAccent),
          if (tens  > 0) _PtBadge('10×$tens', Colors.greenAccent),
          if (total == 0)
            Text('No point cards visible',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.3))),
        ],
      ),
    );
  }
}

class _PtBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _PtBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color)),
      );
}

// ── Bidding view ──────────────────────────────────────────────────────────────

class _BiddingView extends StatelessWidget {
  final Game28State state;
  final String playerId;
  final void Function(int) onBid;
  final VoidCallback onPass;

  const _BiddingView({
    required this.state,
    required this.playerId,
    required this.onBid,
    required this.onPass,
  });

  bool get _isMyTurn => state.biddingTurn == playerId;
  bool get _iPassed => state.passedPlayers.contains(playerId);

  @override
  Widget build(BuildContext context) {
    final nextBid = state.currentBid + 1;
    return Column(
      children: [
        // header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Text('BIDDING',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      color: Colors.white54)),
              const Spacer(),
              _tag('ROUND ${state.roundNumber}', _kGold),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // current bid display
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              Text('CURRENT BID',
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2,
                      color: Colors.white.withValues(alpha: 0.4))),
              const SizedBox(height: 4),
              ShaderMask(
                shaderCallback: (b) => const LinearGradient(
                  colors: [Color(0xFF00c6ff), Color(0xFF0066ff)],
                ).createShader(b),
                child: Text(
                  state.currentBid < 14 ? '—' : '${state.currentBid}',
                  style: const TextStyle(
                      fontSize: 58,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1),
                ),
              ),
              if (state.currentBidder != null)
                Text(
                  'by ${_displayName(state.players[state.currentBidder!]?.name ?? '')}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.45)),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // bid history
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView(
              children: state.playerOrder.map((id) {
                final p = state.players[id]!;
                final isPassed = state.passedPlayers.contains(id);
                final isCurrentTurn = state.biddingTurn == id;
                final isHolder = state.currentBidder == id;
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                  decoration: isCurrentTurn
                      ? BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8))
                      : null,
                  child: Row(
                    children: [
                      PlayerAvatarWidget(
                        radius: 14,
                        playerId: id,
                        playerName: p.name,
                        preset: const AvatarPreset(colorIndex: -1, iconIndex: -1),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _displayName(p.name) +
                              (id == playerId ? ' (you)' : ''),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: isCurrentTurn
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: isCurrentTurn
                                  ? Colors.white
                                  : Colors.white70),
                        ),
                      ),
                      if (isPassed)
                        _tag('PASS', Colors.white24)
                      else if (isHolder)
                        _tag('${state.currentBid}', _kTeamColor(p.teamIndex))
                      else if (isCurrentTurn)
                        _tag('← TURN', _kGold)
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // action buttons
        if (_isMyTurn && !_iPassed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _OutlineBtn('PASS', onPass),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FilledBtn('BID $nextBid', () => onBid(nextBid),
                          color: _kTeamA),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Quick-pick higher bids
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final extra in [2, 3, 4, 5])
                      if (state.currentBid + extra <= 28)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _SmallBidBtn(
                              '${state.currentBid + extra}',
                              () => onBid(state.currentBid + extra)),
                        ),
                  ],
                ),
              ],
            ),
          )
        else if (_iPassed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text('You passed · Waiting for others…',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.3))),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                    'Waiting for ${_displayName(state.players[state.biddingTurn ?? '']?.name ?? '')}…',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.3))),
              ),
            ),
          ),

        const SizedBox(height: 20),
      ],
    );
  }
}

// ── Trump selection view ──────────────────────────────────────────────────────

class _TrumpSelectionView extends StatelessWidget {
  final Game28State state;
  final String playerId;
  final int? selectedSuit;
  final void Function(int) onSuitTap;
  final VoidCallback? onLock;

  const _TrumpSelectionView({
    required this.state,
    required this.playerId,
    required this.selectedSuit,
    required this.onSuitTap,
    required this.onLock,
  });

  bool get _isBidWinner => state.bidWinnerId == playerId;

  @override
  Widget build(BuildContext context) {
    final bidWinnerName = _displayName(
        state.players[state.bidWinnerId ?? '']?.name ?? 'Someone');

    if (_isBidWinner) {
      // Bidder picks trump
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Win banner
          Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF003d1a),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: Colors.green.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                const Text('🏆', style: TextStyle(fontSize: 36)),
                const SizedBox(height: 6),
                const Text('BID WON',
                    style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 3,
                        color: Colors.white54)),
                const SizedBox(height: 4),
                Text('${state.currentBid} pts',
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: _kGold)),
                Text('Your team must score ≥${state.currentBid} to win',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5))),
              ],
            ),
          ),

          Text('Choose trump suit',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.6),
                  letterSpacing: 1)),
          Text('Only you can see this',
              style: TextStyle(
                  fontSize: 11,
                  color: _kTeamB.withValues(alpha: 0.7))),
          const SizedBox(height: 20),

          // Suit picker
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) {
              final suit = Suit.values[i];
              final symbol = _suitSymbol(suit);
              final isRed = suit == Suit.hearts || suit == Suit.diamonds;
              final selected = selectedSuit == i;
              return GestureDetector(
                onTap: () => onSuitTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: selected
                        ? _kGold.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? _kGold : Colors.white24,
                      width: selected ? 2 : 1,
                    ),
                    boxShadow: selected
                        ? [BoxShadow(color: _kGold.withValues(alpha: 0.3), blurRadius: 12)]
                        : null,
                  ),
                  child: Center(
                    child: Text(symbol,
                        style: TextStyle(
                            fontSize: 34,
                            color: isRed
                                ? const Color(0xFFD32F2F)
                                : Colors.white)),
                  ),
                ),
              );
            }),
          ),

          const SizedBox(height: 28),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _FilledBtn(
              selectedSuit == null ? 'SELECT A SUIT' : 'LOCK IN TRUMP',
              onLock,
              color: selectedSuit == null ? Colors.white24 : _kGold,
              textColor: selectedSuit == null ? Colors.white38 : Colors.black,
            ),
          ),
        ],
      );
    }

    // Others wait
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              const Text('🤫', style: TextStyle(fontSize: 42)),
              const SizedBox(height: 12),
              Text('$bidWinnerName is choosing trump…',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('Bid: ${state.currentBid} pts',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.45))),
              const SizedBox(height: 16),
              Text('Trump is secret until the first trump card is played',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.35)),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
        // Your hand preview
        _HandPreview(
          hand: state.players[playerId]?.hand ?? [],
          trumpSuit: null,
          showTrump: false,
        ),
      ],
    );
  }
}

// ── Game table view ───────────────────────────────────────────────────────────

class _GameTableView extends StatelessWidget {
  final Game28State state;
  final String playerId;
  final bool Function(PlayingCard) canPlay;
  final void Function(int) onCardTap;

  const _GameTableView({
    required this.state,
    required this.playerId,
    required this.canPlay,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    final me = state.players[playerId]!;
    final order = state.playerOrder;
    final myIdx = order.indexOf(playerId);

    // Reorder so I'm always at the bottom (index 0), then clockwise
    final reordered = List.generate(
        4, (i) => order[(myIdx + i) % order.length]);

    final top = state.players[reordered[2]]!;    // across
    final left = state.players[reordered[3]]!;   // left
    final right = state.players[reordered[1]]!;  // right

    final isTrickEnd = state.phase == Game28Phase.trickEnd;
    final myTurn = state.currentTurn == playerId;

    return Column(
      children: [
        // ── Score strip ────────────────────────────────────────────
        _ScoreStrip(state: state, playerId: playerId),

        // ── Table ──────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Top opponent
                _OpponentSeat(
                  player: top,
                  isMyTurn: state.currentTurn == top.id,
                  isTrickEnd: isTrickEnd,
                ),

                // Middle row: left, trick table, right
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _OpponentSeat(
                      player: left,
                      isMyTurn: state.currentTurn == left.id,
                      isTrickEnd: isTrickEnd,
                      horizontal: true,
                    ),
                    _TrickArea(
                      state: state,
                      orderedSeats: reordered,
                    ),
                    _OpponentSeat(
                      player: right,
                      isMyTurn: state.currentTurn == right.id,
                      isTrickEnd: isTrickEnd,
                      horizontal: true,
                    ),
                  ],
                ),

                // Info bar: trump + lead suit + turn pill
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TrumpPill(
                      trumpSuit: state.trumpSuit,
                      revealed: state.trumpRevealed,
                      isBidWinner: state.bidWinnerId == playerId,
                    ),
                    if (state.leadSuit != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('LEAD ',
                                style: TextStyle(
                                    fontSize: 9,
                                    letterSpacing: 1.5,
                                    color: Colors.white.withValues(alpha: 0.4))),
                            Text(
                              _suitSymbol(Suit.values[state.leadSuit!]),
                              style: TextStyle(
                                  fontSize: 18,
                                  color: _suitIsRed(Suit.values[state.leadSuit!])
                                      ? const Color(0xFFD32F2F)
                                      : Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (myTurn && !isTrickEnd) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: _kGold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: _kGold.withValues(alpha: 0.45)),
                        ),
                        child: const Text('YOUR TURN',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: _kGold,
                                letterSpacing: 1.2)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 4),

        // ── My hand ────────────────────────────────────────────────
        _MyHand(
          hand: me.hand,
          trumpSuit: state.trumpSuit,
          isBidWinner: state.bidWinnerId == playerId,
          canPlay: canPlay,
          onTap: onCardTap,
        ),

        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Round end view ────────────────────────────────────────────────────────────

class _RoundEndView extends StatelessWidget {
  final Game28State state;
  final String playerId;
  final VoidCallback onNext;

  const _RoundEndView(
      {required this.state,
      required this.playerId,
      required this.onNext});

  @override
  Widget build(BuildContext context) {
    final bidTeam = state.bidWinnerTeam!;
    final bidTeamPts = state.teamTrickPoints['t$bidTeam'] ?? 0;
    final bidMet = bidTeamPts >= state.currentBid;
    final myTeam = state.players[playerId]!.teamIndex;
    final iWon = bidMet ? myTeam == bidTeam : myTeam != bidTeam;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Result banner
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            decoration: BoxDecoration(
              color: iWon
                  ? const Color(0xFF003d1a)
                  : const Color(0xFF3d0010),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: iWon
                    ? Colors.green.withValues(alpha: 0.4)
                    : _kTeamB.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              children: [
                Text(iWon ? '🏆' : '💔',
                    style: const TextStyle(fontSize: 36)),
                const SizedBox(height: 6),
                Text(
                  bidMet ? 'BID MET' : 'BID FAILED',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      color: Colors.white.withValues(alpha: 0.55)),
                ),
                const SizedBox(height: 4),
                Text(
                  bidMet ? 'Team ${bidTeam == 0 ? 'A' : 'B'} wins!' : 'Team ${bidTeam == 0 ? 'B' : 'A'} wins!',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: iWon ? Colors.greenAccent : _kTeamB),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bid team scored $bidTeamPts / needed ${state.currentBid}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Card points
          _SectionLabel('CARD POINTS THIS ROUND'),
          const SizedBox(height: 6),
          _ScoreCard(
            label: 'Team A',
            pts: state.teamTrickPoints['t0'] ?? 0,
            color: _kTeamA,
            badge: bidTeam == 0 ? 'BID TEAM' : null,
            bid: bidTeam == 0 ? state.currentBid : null,
          ),
          const SizedBox(height: 6),
          _ScoreCard(
            label: 'Team B',
            pts: state.teamTrickPoints['t1'] ?? 0,
            color: _kTeamB,
            badge: bidTeam == 1 ? 'BID TEAM' : null,
            bid: bidTeam == 1 ? state.currentBid : null,
          ),

          const SizedBox(height: 16),

          // Game score
          _SectionLabel('GAME SCORE'),
          const SizedBox(height: 6),
          _ScoreCard(
            label: 'Team A',
            pts: state.teamGamePoints['t0'] ?? 0,
            color: _kTeamA,
            total: state.targetScore,
          ),
          const SizedBox(height: 6),
          _ScoreCard(
            label: 'Team B',
            pts: state.teamGamePoints['t1'] ?? 0,
            color: _kTeamB,
            total: state.targetScore,
          ),

          const SizedBox(height: 24),

          _FilledBtn('NEXT ROUND →', onNext, color: Colors.green.shade700),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Game over view ────────────────────────────────────────────────────────────

class _GameOverView extends StatelessWidget {
  final Game28State state;
  final String playerId;
  final VoidCallback onHome;
  final VoidCallback onPlayAgain;

  const _GameOverView({
    required this.state,
    required this.playerId,
    required this.onHome,
    required this.onPlayAgain,
  });

  @override
  Widget build(BuildContext context) {
    final pts0 = state.teamGamePoints['t0'] ?? 0;
    final pts1 = state.teamGamePoints['t1'] ?? 0;
    final winTeam = pts0 >= state.targetScore ? 0 : 1;
    final myTeam = state.players[playerId]!.teamIndex;
    final iWon = myTeam == winTeam;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Text(iWon ? '🏆' : '💔', style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 12),
          Text(
            'WINNERS',
            style: TextStyle(
                fontSize: 12,
                letterSpacing: 3,
                color: Colors.white.withValues(alpha: 0.4)),
          ),
          Text(
            'Team ${winTeam == 0 ? 'A' : 'B'}',
            style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: _kGold),
          ),

          const SizedBox(height: 24),

          _SectionLabel('FINAL SCORE'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _ScoreCard(
                      label: 'Team A',
                      pts: pts0,
                      color: _kTeamA,
                      total: state.targetScore)),
              const SizedBox(width: 10),
              Expanded(
                  child: _ScoreCard(
                      label: 'Team B',
                      pts: pts1,
                      color: _kTeamB,
                      total: state.targetScore)),
            ],
          ),

          const SizedBox(height: 16),

          _SectionLabel('PLAYERS'),
          const SizedBox(height: 6),
          ...state.orderedPlayers.map((p) {
            final won = p.teamIndex == winTeam;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  PlayerAvatarWidget(
                    radius: 18,
                    playerId: p.id,
                    playerName: p.name,
                    preset: const AvatarPreset(colorIndex: -1, iconIndex: -1),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName(p.name) +
                              (p.id == playerId ? ' (you)' : ''),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Team ${p.teamIndex == 0 ? 'A' : 'B'}',
                          style: TextStyle(
                              fontSize: 10,
                              color: _kTeamColor(p.teamIndex)
                                  .withValues(alpha: 0.8)),
                        ),
                      ],
                    ),
                  ),
                  _tag(won ? 'WIN' : 'LOSS',
                      won ? Colors.greenAccent : _kTeamB),
                ],
              ),
            );
          }),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(child: _OutlineBtn('HOME', onHome)),
              const SizedBox(width: 10),
              Expanded(
                  child: _FilledBtn('PLAY AGAIN', onPlayAgain,
                      color: Colors.green.shade700)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ScoreStrip extends StatelessWidget {
  final Game28State state;
  final String playerId;
  const _ScoreStrip({required this.state, required this.playerId});

  @override
  Widget build(BuildContext context) {
    final pts0 = state.teamTrickPoints['t0'] ?? 0;
    final pts1 = state.teamTrickPoints['t1'] ?? 0;
    final game0 = state.teamGamePoints['t0'] ?? 0;
    final game1 = state.teamGamePoints['t1'] ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(child: _TeamScore('A', pts0, game0, _kTeamA, state.bidWinnerTeam == 0)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                Text('BID',
                    style: TextStyle(
                        fontSize: 8,
                        letterSpacing: 1,
                        color: Colors.white.withValues(alpha: 0.3))),
                Text('${state.currentBid}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: _kGold)),
                Text('T${state.trickNumber}/8',
                    style: TextStyle(
                        fontSize: 9,
                        color: Colors.white.withValues(alpha: 0.25))),
              ],
            ),
          ),
          Expanded(child: _TeamScore('B', pts1, game1, _kTeamB, state.bidWinnerTeam == 1)),
        ],
      ),
    );
  }
}

class _TeamScore extends StatelessWidget {
  final String label;
  final int trickPts;
  final int gamePts;
  final Color color;
  final bool isBidTeam;

  const _TeamScore(this.label, this.trickPts, this.gamePts, this.color,
      this.isBidTeam);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Team $label',
                  style: TextStyle(
                      fontSize: 9,
                      color: color.withValues(alpha: 0.8),
                      letterSpacing: 0.5)),
              Text('$trickPts pts',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isBidTeam)
                Text('BIDDER',
                    style: TextStyle(
                        fontSize: 8,
                        color: _kGold.withValues(alpha: 0.8),
                        letterSpacing: 0.5)),
              Text('$gamePts game pts',
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.5))),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrumpPill extends StatelessWidget {
  final int? trumpSuit;
  final bool revealed;
  final bool isBidWinner;

  const _TrumpPill(
      {required this.trumpSuit,
      required this.revealed,
      required this.isBidWinner});

  @override
  Widget build(BuildContext context) {
    final showSuit = revealed || isBidWinner;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('TRUMP ',
              style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.5,
                  color: Colors.white.withValues(alpha: 0.4))),
          if (showSuit && trumpSuit != null)
            Text(
              _suitSymbol(Suit.values[trumpSuit!]),
              style: TextStyle(
                  fontSize: 18,
                  color: _suitIsRed(Suit.values[trumpSuit!])
                      ? const Color(0xFFD32F2F)
                      : Colors.white),
            )
          else
            Text('?',
                style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.3))),
          if (isBidWinner && !revealed)
            Text(' (secret)',
                style: TextStyle(
                    fontSize: 9,
                    color: _kGold.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

class _TrickArea extends StatelessWidget {
  final Game28State state;
  final List<String> orderedSeats; // [me, right, across, left]

  const _TrickArea(
      {required this.state, required this.orderedSeats});

  @override
  Widget build(BuildContext context) {
    // Positions: [me=bottom, right=right, across=top, left=left]
    const positions = [
      Alignment.bottomCenter,
      Alignment.centerRight,
      Alignment.topCenter,
      Alignment.centerLeft,
    ];

    final isTrickEnd = state.phase == Game28Phase.trickEnd;

    return SizedBox(
      width: 224,
      height: 224,
      child: Stack(
        children: [
          // Table surface — radial gradient with outer glow
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF1e0f38),
                  const Color(0xFF0d0618),
                ],
                stops: const [0.0, 1.0],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7c3aff).withValues(alpha: 0.18),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          // Inner ring
          Center(
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
          ),
          // Trick number watermark (visible when table is empty)
          if (state.currentTrick.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${state.trickNumber}',
                    style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        color: Colors.white.withValues(alpha: 0.07)),
                  ),
                  Text(
                    'OF 8',
                    style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 2.5,
                        color: Colors.white.withValues(alpha: 0.05)),
                  ),
                ],
              ),
            ),
          // Cards
          for (int i = 0; i < 4; i++)
            if (state.currentTrick.containsKey(orderedSeats[i]))
              Align(
                alignment: positions[i],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: CardWidget(
                    card: state.currentTrick[orderedSeats[i]]!,
                    width: 52,
                    height: 72,
                  ),
                ),
              ),
          // My empty slot when it's my turn
          if (!state.currentTrick.containsKey(orderedSeats[0]) &&
              state.currentTurn == orderedSeats[0] &&
              !isTrickEnd)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  width: 52,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                        color: _kGold.withValues(alpha: 0.65),
                        width: 2),
                    color: _kGold.withValues(alpha: 0.06),
                    boxShadow: [
                      BoxShadow(
                        color: _kGold.withValues(alpha: 0.2),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text('▲',
                        style: TextStyle(
                            fontSize: 13,
                            color: _kGold.withValues(alpha: 0.75))),
                  ),
                ),
              ),
            ),
          // Trick end — dim overlay
          if (isTrickEnd)
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.25),
              ),
            ),
        ],
      ),
    );
  }
}

class _OpponentSeat extends StatelessWidget {
  final Game28Player player;
  final bool isMyTurn;
  final bool isTrickEnd;
  final bool horizontal;

  const _OpponentSeat({
    required this.player,
    required this.isMyTurn,
    required this.isTrickEnd,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    final teamColor = _kTeamColor(player.teamIndex);
    final children = [
      Stack(
        children: [
          PlayerAvatarWidget(
            radius: 18,
            playerId: player.id,
            playerName: player.name,
            preset: const AvatarPreset(colorIndex: -1, iconIndex: -1),
          ),
          if (isMyTurn && !isTrickEnd)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _kGold, width: 2.5),
                ),
              ),
            ),
        ],
      ),
      SizedBox(width: horizontal ? 4 : 0, height: horizontal ? 0 : 3),
      Text(
        _displayName(player.name),
        style: TextStyle(
            fontSize: 9,
            color: teamColor.withValues(alpha: 0.7),
            letterSpacing: 0.3),
        overflow: TextOverflow.ellipsis,
      ),
      Text(
        '${player.hand.length}🃏',
        style: TextStyle(
            fontSize: 9,
            color: Colors.white.withValues(alpha: 0.3)),
      ),
    ];

    return horizontal
        ? Column(mainAxisSize: MainAxisSize.min, children: children)
        : Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _MyHand extends StatelessWidget {
  final List<PlayingCard> hand;
  final int? trumpSuit;
  final bool isBidWinner;
  final bool Function(PlayingCard) canPlay;
  final void Function(int) onTap;

  const _MyHand({
    required this.hand,
    required this.trumpSuit,
    required this.isBidWinner,
    required this.canPlay,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (hand.isEmpty) {
      return const SizedBox(height: 80);
    }
    // Sort by suit then rank
    final sorted = hand.asMap().entries.toList()
      ..sort((a, b) {
        final suitDiff = a.value.suit.index - b.value.suit.index;
        if (suitDiff != 0) return suitDiff;
        return a.value.rank.index - b.value.rank.index;
      });

    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: sorted.length,
        itemBuilder: (_, i) {
          final origIdx = sorted[i].key;
          final card = sorted[i].value;
          final playable = canPlay(card);
          final isTrump = trumpSuit != null && card.suit.index == trumpSuit;
          final pts = cardPoints28(card.rank);

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: playable ? 1.0 : 0.35,
                  child: CardWidget(
                    card: card,
                    width: 54,
                    height: 78,
                    onTap: playable ? () => onTap(origIdx) : null,
                  ),
                ),
                // Trump indicator
                if (isTrump)
                  Positioned(
                    top: -5,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kGold,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('T',
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                color: Colors.black)),
                      ),
                    ),
                  ),
                // Point badge
                if (pts > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: _kGold,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('$pts',
                            style: const TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                color: Colors.black)),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HandPreview extends StatelessWidget {
  final List<PlayingCard> hand;
  final int? trumpSuit;
  final bool showTrump;

  const _HandPreview(
      {required this.hand,
      required this.trumpSuit,
      required this.showTrump});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR HAND',
              style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 2,
                  color: Colors.white.withValues(alpha: 0.35))),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: hand.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: CardWidget(card: hand[i], width: 50, height: 72),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Gold badge = point card (J·3, 9·2, A·1, 10·1)',
              style: TextStyle(
                  fontSize: 9,
                  color: Colors.white.withValues(alpha: 0.3))),
        ],
      ),
    );
  }
}

// ── Reusable score widgets ────────────────────────────────────────────────────

class _ScoreCard extends StatelessWidget {
  final String label;
  final int pts;
  final Color color;
  final String? badge;
  final int? bid;
  final int? total;

  const _ScoreCard({
    required this.label,
    required this.pts,
    required this.color,
    this.badge,
    this.bid,
    this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
              width: 10, height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          if (badge != null) ...[
            const SizedBox(width: 8),
            _tag(badge!, _kGold),
          ],
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$pts',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: color)),
              if (bid != null)
                Text('need $bid',
                    style: TextStyle(
                        fontSize: 9,
                        color: Colors.white.withValues(alpha: 0.4))),
              if (total != null)
                Text('/ $total',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.4))),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
            fontSize: 10,
            letterSpacing: 2,
            color: Colors.white.withValues(alpha: 0.4)),
      );
}

// ── Button helpers ────────────────────────────────────────────────────────────

class _FilledBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final Color textColor;

  const _FilledBtn(this.label, this.onTap,
      {this.color = _kTeamA, this.textColor = Colors.black});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            disabledBackgroundColor: Colors.white12,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: onTap == null ? Colors.white24 : textColor)),
        ),
      );
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _OutlineBtn(this.label, this.onTap);

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white30),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: Colors.white70)),
        ),
      );
}

class _SmallBidBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SmallBidBtn(this.label, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70)),
        ),
      );
}

// ── Utility ───────────────────────────────────────────────────────────────────

Widget _tag(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: color)),
    );

Color _kTeamColor(int teamIndex) =>
    teamIndex == 0 ? _kTeamA : _kTeamB;

String _suitSymbol(Suit suit) {
  switch (suit) {
    case Suit.hearts:
      return '♥';
    case Suit.diamonds:
      return '♦';
    case Suit.clubs:
      return '♣';
    case Suit.spades:
      return '♠';
  }
}

bool _suitIsRed(Suit suit) =>
    suit == Suit.hearts || suit == Suit.diamonds;

String _displayName(String name) =>
    name.replaceAll('_', ' ').split(' ').take(2).join(' ');
