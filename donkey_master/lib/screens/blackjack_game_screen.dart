import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/card_model.dart';
import '../services/admob_service.dart';
import '../services/game_logger.dart';
import '../services/sound_service.dart';
import '../services/stats_service.dart';
import '../widgets/ad_banner_widget.dart';
import '../widgets/card_widget.dart';
import '../widgets/how_to_play_overlay.dart';

// ── Hand helpers ──────────────────────────────────────────────────────────────

int _handValue(List<PlayingCard> hand) {
  int total = 0;
  int aces = 0;
  for (final c in hand) {
    if (c.rank == Rank.ace) {
      aces++;
      total += 11;
    } else if (c.rank.index >= Rank.ten.index) {
      total += 10;
    } else {
      total += c.rank.index + 2; // two=0→2 … nine=7→9
    }
  }
  while (total > 21 && aces > 0) {
    total -= 10;
    aces--;
  }
  return total;
}

bool _isBlackjack(List<PlayingCard> hand) =>
    hand.length == 2 && _handValue(hand) == 21;

// ─────────────────────────────────────────────────────────────────────────────

enum _Phase { betting, playerTurn, dealerTurn, result }

enum _Result { none, blackjack, win, push, bust, loss }

class BlackjackGameScreen extends StatefulWidget {
  final String playerId;
  final String playerName;

  const BlackjackGameScreen({
    super.key,
    required this.playerId,
    required this.playerName,
  });

  @override
  State<BlackjackGameScreen> createState() => _BlackjackGameScreenState();
}

class _BlackjackGameScreenState extends State<BlackjackGameScreen> {
  final _rng = Random();

  _Phase _phase = _Phase.betting;
  _Result _result = _Result.none;

  List<PlayingCard> _deck = [];
  List<PlayingCard> _playerHand = [];
  List<PlayingCard> _dealerHand = [];
  bool _dealerHidden = true;

  int _chips = 1000;
  int _bet = 50;
  int _betSnapshot = 50; // pre-double-down bet; restored at new hand

  bool _busy = false;
  bool _isMuted = false;
  bool _statsRecorded = false;
  int _handCount = 0;
  late String _bjSessionKey;

  static const _accent = Color(0xFFFFD700);
  static const _betOptions = [25, 50, 100, 250, 500];

  @override
  void initState() {
    super.initState();
    AdMobService.instance.suppressAppOpenAd = true;
    _bjSessionKey = '${widget.playerId}_bj_${DateTime.now().millisecondsSinceEpoch}';
    _deck = _freshDeck();
    _loadChips();
  }

  @override
  void dispose() {
    AdMobService.instance.suppressAppOpenAd = false;
    super.dispose();
  }

  Future<void> _loadChips() async {
    final stats = await StatsService.instance.getStats(widget.playerId);
    if (mounted) {
      setState(() => _chips = stats.totalPoints > 0 ? stats.totalPoints : 1000);
      GameLogger.instance.bjGameStart(
        sessionKey: _bjSessionKey,
        playerName: widget.playerName,
        chips: _chips,
      );
    }
  }

  List<PlayingCard> _freshDeck() => [
        for (final s in Suit.values)
          for (final r in Rank.values) PlayingCard(suit: s, rank: r),
      ]..shuffle(_rng);

  PlayingCard _dealCard() {
    if (_deck.length < 15) _deck = _freshDeck();
    return _deck.removeLast();
  }

  // ── Round control ─────────────────────────────────────────────────────────

  Future<void> _startRound() async {
    if (_busy || _bet > _chips || _chips <= 0) return;
    setState(() {
      _busy = true;
      _betSnapshot = _bet;
      _playerHand = [_dealCard(), _dealCard()];
      _dealerHand = [_dealCard(), _dealCard()];
      _dealerHidden = true;
      _result = _Result.none;
      _statsRecorded = false;
    });
    SoundService.instance.playCardSlap();
    GameLogger.instance.bjRoundStart(
      sessionKey: _bjSessionKey,
      bet: _bet,
      chips: _chips,
      playerHand: GameLogger.handLabel(_playerHand),
      playerValue: _handValue(_playerHand),
      dealerVisible: GameLogger.cardLabel(_dealerHand.first),
    );

    // Check player blackjack — reveal dealer card and check for dealer blackjack
    if (_isBlackjack(_playerHand)) {
      await Future.delayed(const Duration(milliseconds: 700));
      setState(() => _dealerHidden = false);
      await Future.delayed(const Duration(milliseconds: 400));
      await _endRound(
          _isBlackjack(_dealerHand) ? _Result.push : _Result.blackjack);
      return;
    }

    setState(() {
      _phase = _Phase.playerTurn;
      _busy = false;
    });
  }

  Future<void> _hit() async {
    if (_busy || _phase != _Phase.playerTurn) return;
    setState(() => _busy = true);
    SoundService.instance.playCardSlap();
    setState(() {
      _playerHand = [..._playerHand, _dealCard()];
      _busy = false;
    });
    GameLogger.instance.bjAction(
      sessionKey: _bjSessionKey,
      action: 'HIT',
      hand: GameLogger.handLabel(_playerHand),
      value: _handValue(_playerHand),
    );
    if (_handValue(_playerHand) > 21) {
      await Future.delayed(const Duration(milliseconds: 400));
      await _endRound(_Result.bust);
    }
  }

  Future<void> _stand() async {
    if (_busy || _phase != _Phase.playerTurn) return;
    GameLogger.instance.bjAction(
      sessionKey: _bjSessionKey,
      action: 'STAND',
      hand: GameLogger.handLabel(_playerHand),
      value: _handValue(_playerHand),
    );
    await _runDealer();
  }

  Future<void> _doubleDown() async {
    if (_busy || _phase != _Phase.playerTurn || _bet * 2 > _chips) return;
    SoundService.instance.playCardSlap();
    setState(() {
      _bet *= 2;
      _busy = true;
      _phase = _Phase.dealerTurn; // collapse action buttons immediately
      _playerHand = [..._playerHand, _dealCard()];
    });
    GameLogger.instance.bjAction(
      sessionKey: _bjSessionKey,
      action: 'DOUBLE_DOWN',
      hand: GameLogger.handLabel(_playerHand),
      value: _handValue(_playerHand),
    );
    await Future.delayed(const Duration(milliseconds: 900));
    if (_handValue(_playerHand) > 21) {
      await _endRound(_Result.bust);
    } else {
      await _runDealer();
    }
  }

  Future<void> _runDealer() async {
    setState(() {
      _phase = _Phase.dealerTurn;
      _dealerHidden = false;
      _busy = true;
    });
    SoundService.instance.playCut();
    await Future.delayed(const Duration(milliseconds: 500));

    while (_handValue(_dealerHand) < 17) {
      setState(() => _dealerHand = [..._dealerHand, _dealCard()]);
      SoundService.instance.playCardSlap();
      await Future.delayed(const Duration(milliseconds: 600));
    }

    final p = _handValue(_playerHand);
    final d = _handValue(_dealerHand);
    await _endRound(
      d > 21 || p > d ? _Result.win : p == d ? _Result.push : _Result.loss,
    );
  }

  Future<void> _endRound(_Result res) async {
    final delta = switch (res) {
      _Result.blackjack => (_bet * 1.5).round(),
      _Result.win       => _bet,
      _Result.push      => 0,
      _Result.bust      => -_bet,
      _Result.loss      => -_bet,
      _Result.none      => 0,
    };

    setState(() {
      _phase = _Phase.result;
      _result = res;
      _dealerHidden = false;
      _busy = false;
      _chips = (_chips + delta).clamp(0, 999999);
    });

    switch (res) {
      case _Result.blackjack:
      case _Result.win:
        SoundService.instance.playEscape();
      case _Result.bust:
      case _Result.loss:
        SoundService.instance.playDonkey();
      default:
        SoundService.instance.playCardSlap();
    }

    if (!_statsRecorded && !widget.playerId.startsWith('bot_')) {
      _statsRecorded = true;
      await StatsService.instance.recordBlackjackRound(
        uid: widget.playerId,
        won: res == _Result.win || res == _Result.blackjack,
        isPush: res == _Result.push,
        isBlackjack: res == _Result.blackjack,
        chipsDelta: delta,
      );
    }
    GameLogger.instance.bjRoundEnd(
      sessionKey: _bjSessionKey,
      result: res.name.toUpperCase(),
      delta: delta,
      playerHand: GameLogger.handLabel(_playerHand),
      playerValue: _handValue(_playerHand),
      dealerHand: GameLogger.handLabel(_dealerHand),
      dealerValue: _handValue(_dealerHand),
      chipsAfter: _chips,
    );

    _handCount++;
    if (_handCount % 4 == 0) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) AdMobService.instance.showRewardedAsync(context: context, placement: 'blackjack');
      });
    }
  }

  void _newHand() {
    setState(() {
      _phase = _Phase.betting;
      _result = _Result.none;
      _playerHand = [];
      _dealerHand = [];
      _dealerHidden = true;
      _bet = _betSnapshot; // restore pre-double bet
    });
  }

  void _leaveGame() {
    AdMobService.instance.showInterstitialAsync(context).then((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _leaveGame(); },
      child: Scaffold(
        backgroundColor: const Color(0xFF060e06),
        body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    children: [
                      _buildDealerSection(),
                      const SizedBox(height: 8),
                      _buildBetStrip(),
                      const Spacer(),
                      _buildPlayerSection(),
                      const SizedBox(height: 12),
                      _buildActions(),
                      const SizedBox(height: 8),
                      const AdBannerWidget(),
                    ],
                  ),
                  if (_phase == _Phase.result) _buildResultOverlay(),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
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
          const Text('BLACKJACK',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Colors.white)),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _accent.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🪙', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
                Text('$_chips',
                    style: const TextStyle(
                        color: _accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              _isMuted
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded,
              color: Colors.white54,
              size: 22,
            ),
            onPressed: () => setState(() {
              _isMuted = !_isMuted;
              SoundService.instance.toggleMute();
            }),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded,
                color: Colors.white54, size: 22),
            onPressed: () => showHowToPlay(context, game: 'blackjack'),
          ),
        ],
      ),
    );
  }

  // ── Dealer section ────────────────────────────────────────────────────────

  Widget _buildDealerSection() {
    final visibleValue = _dealerHidden && _dealerHand.isNotEmpty
        ? _handValue([_dealerHand.first])
        : _handValue(_dealerHand);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text('DEALER',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.4),
                  letterSpacing: 2)),
          const SizedBox(height: 10),
          _dealerHand.isEmpty
              ? _EmptySlots(count: 2)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _dealerHand.asMap().entries.map((e) {
                    final hidden = e.key == 1 && _dealerHidden;
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5),
                      child: hidden
                          ? CardBackWidget(width: 64, height: 92)
                          : CardWidget(
                              card: e.value, width: 64, height: 92),
                    );
                  }).toList(),
                ),
          const SizedBox(height: 8),
          if (_dealerHand.isNotEmpty)
            Text(
              _dealerHidden ? '$visibleValue + ?' : '$visibleValue',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.65)),
            ),
        ],
      ),
    );
  }

  // ── Bet strip / betting panel ─────────────────────────────────────────────

  Widget _buildBetStrip() {
    if (_phase != _Phase.betting) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _InfoChip(label: 'BET', value: '$_bet'),
            Container(
                width: 1,
                height: 24,
                color: Colors.white12,
                margin: const EdgeInsets.symmetric(horizontal: 20)),
            _InfoChip(label: 'CHIPS', value: '$_chips'),
          ],
        ),
      );
    }

    // Out of chips (or below minimum bet — player would be stuck otherwise)
    if (_chips < _betOptions.first) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            Text(_chips <= 0 ? 'Out of chips!' : 'Not enough to bet!',
                style: TextStyle(
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
              ),
              onPressed: () async {
                await AdMobService.instance.showRewardedAsync(context: context, placement: 'blackjack');
                const bonus = 500;
                if (mounted) setState(() => _chips = bonus);
                await StatsService.instance.recordBlackjackRound(
                  uid: widget.playerId,
                  won: false,
                  isPush: true,
                  isBlackjack: false,
                  chipsDelta: bonus,
                );
              },
              child: const Text('🎁  GET FREE CHIPS'),
            ),
          ],
        ),
      );
    }

    // Betting panel
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Text('PLACE YOUR BET',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.4),
                  letterSpacing: 2)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _betOptions.map((amount) {
              final selected = _bet == amount;
              final canAfford = amount <= _chips;
              return GestureDetector(
                onTap: canAfford
                    ? () => setState(() => _bet = amount)
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected
                        ? _accent
                        : Colors.white.withValues(
                            alpha: canAfford ? 0.07 : 0.02),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? _accent
                          : Colors.white.withValues(
                              alpha: canAfford ? 0.2 : 0.06),
                    ),
                  ),
                  child: Text(
                    '$amount',
                    style: TextStyle(
                      color: selected
                          ? Colors.black
                          : Colors.white.withValues(
                              alpha: canAfford ? 0.8 : 0.3),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Player section ────────────────────────────────────────────────────────

  Widget _buildPlayerSection() {
    final value = _handValue(_playerHand);
    final bust = value > 21;
    return Column(
      children: [
        _playerHand.isEmpty
            ? _EmptySlots(count: 2)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _playerHand
                    .map((c) => Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          child: CardWidget(card: c, width: 64, height: 92),
                        ))
                    .toList(),
              ),
        const SizedBox(height: 8),
        if (_playerHand.isNotEmpty)
          Text(
            bust ? 'BUST — $value' : '$value',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: bust ? Colors.red.shade400 : Colors.white),
          ),
        const SizedBox(height: 4),
        Text(widget.playerName,
            style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.4),
                letterSpacing: 1)),
      ],
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Widget _buildActions() {
    if (_phase == _Phase.betting) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _chips > 0 ? _accent : Colors.white24,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: (_busy || _bet > _chips || _chips <= 0)
                ? null
                : _startRound,
            child: const Text('DEAL',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2)),
          ),
        ),
      );
    }

    if (_phase != _Phase.playerTurn) return const SizedBox(height: 58);

    final canDouble = _playerHand.length == 2 && _bet * 2 <= _chips;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Primary row: STAND (left, small) + HIT (right, large)
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _ActionBtn(
                    'STAND', Colors.teal.shade600, _busy ? null : _stand),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: _ActionBtn(
                    'HIT', Colors.red.shade700, _busy ? null : _hit),
              ),
            ],
          ),
          // Secondary row: DOUBLE DOWN full-width
          if (canDouble) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: _ActionBtn('DOUBLE DOWN', Colors.amber.shade700,
                  _busy ? null : _doubleDown),
            ),
          ],
        ],
      ),
    );
  }

  // ── Result overlay ────────────────────────────────────────────────────────

  Widget _buildResultOverlay() {
    final isWin =
        _result == _Result.win || _result == _Result.blackjack;
    final isPush = _result == _Result.push;
    final delta = switch (_result) {
      _Result.blackjack => (_bet * 1.5).round(),
      _Result.win       => _bet,
      _Result.push      => 0,
      _Result.bust      => -_bet,
      _Result.loss      => -_bet,
      _Result.none      => 0,
    };
    final title = switch (_result) {
      _Result.blackjack => '🃏 BLACKJACK!',
      _Result.win       => '🎉 YOU WIN!',
      _Result.push      => '🤝 PUSH',
      _Result.bust      => '💥 BUST!',
      _Result.loss      => '😔 DEALER WINS',
      _Result.none      => '',
    };
    final chipLabel = isPush
        ? 'Bet returned'
        : (delta > 0 ? '+$delta chips' : '$delta chips');

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.65),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF0A180A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isWin
                  ? _accent.withValues(alpha: 0.75)
                  : isPush
                      ? Colors.white24
                      : Colors.red.withValues(alpha: 0.45),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: isWin ? 24 : 18,
                      fontWeight: FontWeight.w900,
                      color: isWin
                          ? _accent
                          : isPush
                              ? Colors.white70
                              : Colors.red.shade400),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(chipLabel,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: delta > 0
                          ? Colors.greenAccent.shade400
                          : delta < 0
                              ? Colors.red.shade300
                              : Colors.white54)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _newHand,
                  child: const Text('NEXT HAND',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 1)),
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms)
        .scale(begin: const Offset(0.93, 0.93));
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _EmptySlots extends StatelessWidget {
  final int count;
  const _EmptySlots({required this.count});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          count,
          (_) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: 64,
            height: 92,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
              color: Colors.white.withValues(alpha: 0.02),
            ),
          ),
        ),
      );
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
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
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ],
      );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  const _ActionBtn(this.label, this.color, this.onPressed);

  @override
  Widget build(BuildContext context) => ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              color.withValues(alpha: onPressed != null ? 1 : 0.35),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        onPressed: onPressed,
        child: Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5)),
      );
}
