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

// ── Rank cycle A 2 3 … K ─────────────────────────────────────────────────────

const _rankCycle = [
  Rank.ace, Rank.two, Rank.three, Rank.four, Rank.five, Rank.six,
  Rank.seven, Rank.eight, Rank.nine, Rank.ten, Rank.jack, Rank.queen, Rank.king,
];

String _rl(Rank r) => const {
      Rank.ace: 'A', Rank.two: '2', Rank.three: '3', Rank.four: '4',
      Rank.five: '5', Rank.six: '6', Rank.seven: '7', Rank.eight: '8',
      Rank.nine: '9', Rank.ten: '10', Rank.jack: 'J', Rank.queen: 'Q',
      Rank.king: 'K',
    }[r]!;

int _cardSort(PlayingCard a, PlayingCard b) {
  final rc = a.rank.index.compareTo(b.rank.index);
  return rc != 0 ? rc : a.suit.index.compareTo(b.suit.index);
}

// ─────────────────────────────────────────────────────────────────────────────

enum _Phase { playerTurn, botCallWindow, humanCallWindow, botTurn, bluffResult, gameOver }

class _BP {
  final String name;
  final bool isHuman;
  List<PlayingCard> hand;
  _BP({required this.name, required this.isHuman, required this.hand});
}

// ─────────────────────────────────────────────────────────────────────────────

class BluffGameScreen extends StatefulWidget {
  final String playerId;
  final String playerName;
  const BluffGameScreen({super.key, required this.playerId, required this.playerName});

  @override
  State<BluffGameScreen> createState() => _BluffGameScreenState();
}

class _BluffGameScreenState extends State<BluffGameScreen> {
  static const _accent = Color(0xFFAB47BC);
  final _rng = Random();

  late List<_BP> _players;
  List<PlayingCard> _pile = [];
  List<PlayingCard> _lastPlayed = [];
  int _lastByIdx = -1;
  bool _lastWasBluff = false;
  Rank _lastClaimedRank = Rank.ace;
  int _rankIdx = 0;
  int _turnIdx = 0;
  final Set<PlayingCard> _selected = {};
  _Phase _phase = _Phase.playerTurn;
  String _status = '';
  String _overlayMsg = '';
  bool _isMuted = false;

  int _bluffsAttempted = 0;
  int _bluffsCaught = 0;
  int _bluffsSucceeded = 0;
  bool _statsRecorded = false;
  int _totalPoints = 0;
  late String _bluffSessionKey;

  @override
  void initState() {
    super.initState();
    AdMobService.instance.suppressAppOpenAd = true;
    _newGame();
    _logGameStart();
    StatsService.instance.getStats(widget.playerId).then((s) {
      if (mounted) setState(() => _totalPoints = s.totalPoints);
    });
  }

  @override
  void dispose() {
    AdMobService.instance.suppressAppOpenAd = false;
    super.dispose();
  }

  void _newGame() {
    _bluffSessionKey = '${widget.playerId}_bluff_${DateTime.now().millisecondsSinceEpoch}';
    final deck = [
      for (final s in Suit.values)
        for (final r in Rank.values) PlayingCard(suit: s, rank: r),
    ]..shuffle(_rng);
    _players = [
      _BP(name: widget.playerName, isHuman: true,  hand: deck.sublist( 0, 13)..sort(_cardSort)),
      _BP(name: 'Arjun',           isHuman: false, hand: deck.sublist(13, 26)),
      _BP(name: 'Meera',           isHuman: false, hand: deck.sublist(26, 39)),
      _BP(name: 'Ravi',            isHuman: false, hand: deck.sublist(39, 52)),
    ];
    _pile = [];
    _lastPlayed = [];
    _rankIdx = 0;
    _turnIdx = 0;
    _selected.clear();
    _bluffsAttempted = 0;
    _bluffsCaught = 0;
    _bluffsSucceeded = 0;
    _statsRecorded = false;
    _phase = _Phase.playerTurn;
    _status = 'Your turn — play Aces';
    _overlayMsg = '';
  }

  void _logGameStart() {
    GameLogger.instance.bluffGameStart(
      sessionKey: _bluffSessionKey,
      playerName: widget.playerName,
      botNames: _players.skip(1).map((p) => p.name).toList(),
    );
  }

  Rank get _currentRank => _rankCycle[_rankIdx % 13];

  // ── Human plays selected cards ─────────────────────────────────────────────

  Future<void> _humanPlay() async {
    if (_selected.isEmpty || _phase != _Phase.playerTurn) return;
    final human = _players[0];
    final played = _selected.toList();
    final rank = _currentRank;
    final isBluff = played.any((c) => c.rank != rank);
    if (isBluff) _bluffsAttempted++;

    setState(() {
      for (final c in played) { human.hand.remove(c); }
      human.hand.sort(_cardSort);
      _pile.addAll(played);
      _lastPlayed = played;
      _lastByIdx = 0;
      _lastWasBluff = isBluff;
      _lastClaimedRank = rank;
      _selected.clear();
      _status = 'You played ${played.length} ${played.length == 1 ? "card" : "cards"} claiming ${_rl(rank)}s';
      _phase = _Phase.botCallWindow;
    });
    SoundService.instance.playCardSlap();
    GameLogger.instance.bluffPlay(
      sessionKey: _bluffSessionKey,
      playerName: widget.playerName,
      cardCount: played.length,
      claimedRank: _rl(rank),
      isBluff: isBluff,
      pileAfter: _pile.length,
      handAfter: human.hand.length,
    );

    if (human.hand.isEmpty) { await _handleWin(0); return; }

    for (int i = 1; i < _players.length; i++) {
      await Future.delayed(const Duration(milliseconds: 550));
      if (!mounted) return;
      if (_botCalls(i)) { await _resolveBluff(i); return; }
    }
    if (_lastWasBluff) _bluffsSucceeded++;
    _advance();
  }

  // ── Human calls bluff / passes ─────────────────────────────────────────────

  Future<void> _callBluff() async {
    if (_phase != _Phase.humanCallWindow) return;
    await _resolveBluff(0);
  }

  void _pass() {
    if (_phase != _Phase.humanCallWindow) return;
    _advance();
  }

  // ── Bluff resolution ───────────────────────────────────────────────────────

  Future<void> _resolveBluff(int callerIdx) async {
    final honest = _lastPlayed.every((c) => c.rank == _lastClaimedRank);
    final loserIdx = honest ? callerIdx : _lastByIdx;
    if (!honest && _lastByIdx == 0) _bluffsCaught++;

    final loserName = _players[loserIdx].name;
    final isHumanLoser = loserIdx == 0;
    final msg = honest
        ? '✅ Honest play! ${isHumanLoser ? "You pick" : "$loserName picks"} up ${_pile.length} cards'
        : '🚨 Bluff caught! ${isHumanLoser ? "You pick" : "$loserName picks"} up ${_pile.length} cards';

    setState(() {
      _overlayMsg = msg;
      _phase = _Phase.bluffResult;
    });
    SoundService.instance.playDonkey();
    GameLogger.instance.bluffCall(
      sessionKey: _bluffSessionKey,
      callerName: _players[callerIdx].name,
      wasHonest: honest,
      loserName: loserName,
      pileSize: _pile.length,
    );
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    setState(() {
      final loser = _players[loserIdx];
      loser.hand.addAll(_pile);
      _selected.clear();
      if (loser.isHuman) { loser.hand.sort(_cardSort); }
      else { loser.hand.shuffle(_rng); }
      _pile.clear();
      _lastPlayed.clear();
      _turnIdx = loserIdx;
    });
    _advance(skipRotate: true);
  }

  // ── Advance to next turn ───────────────────────────────────────────────────

  void _advance({bool skipRotate = false}) {
    _rankIdx = (_rankIdx + 1) % 13;
    if (!skipRotate) _turnIdx = (_turnIdx + 1) % 4;
    final p = _players[_turnIdx];
    setState(() {
      _overlayMsg = '';
      if (p.isHuman) {
        _phase = _Phase.playerTurn;
        _status = 'Your turn — play ${_rl(_currentRank)}s';
      } else {
        _phase = _Phase.botTurn;
        _status = '${p.name} is thinking…';
      }
    });
    if (!p.isHuman) _runBot();
  }

  // ── Bot plays ──────────────────────────────────────────────────────────────

  Future<void> _runBot() async {
    await Future.delayed(const Duration(milliseconds: 950));
    if (!mounted) return;
    final bot = _players[_turnIdx];
    final rank = _currentRank;
    final rankCards = bot.hand.where((c) => c.rank == rank).toList();
    List<PlayingCard> toPlay;

    if (rankCards.isNotEmpty) {
      final n = _rng.nextInt(rankCards.length) + 1;
      toPlay = rankCards.take(n).toList();
      if (_rng.nextDouble() < 0.2 && bot.hand.length > n) {
        final fakes = bot.hand.where((c) => c.rank != rank).toList();
        if (fakes.isNotEmpty) toPlay.add(fakes[_rng.nextInt(fakes.length)]);
      }
    } else {
      bot.hand.shuffle(_rng);
      toPlay = bot.hand.take(_rng.nextInt(3) + 1).toList();
    }

    setState(() {
      for (final c in toPlay) { bot.hand.remove(c); }
      _pile.addAll(toPlay);
      _lastPlayed = toPlay;
      _lastByIdx = _turnIdx;
      _lastWasBluff = toPlay.any((c) => c.rank != rank);
      _lastClaimedRank = rank;
      _status = '${bot.name} played ${toPlay.length} ${toPlay.length == 1 ? "card" : "cards"} claiming ${_rl(rank)}s';
      _phase = _Phase.humanCallWindow;
    });
    SoundService.instance.playCardSlap();
    GameLogger.instance.bluffPlay(
      sessionKey: _bluffSessionKey,
      playerName: bot.name,
      cardCount: toPlay.length,
      claimedRank: _rl(rank),
      isBluff: _lastWasBluff,
      pileAfter: _pile.length,
      handAfter: bot.hand.length,
    );

    if (bot.hand.isEmpty) { await _handleWin(_turnIdx); return; }
  }

  // ── Win ────────────────────────────────────────────────────────────────────

  Future<void> _handleWin(int winnerIdx) async {
    final humanWon = winnerIdx == 0;
    if (!_statsRecorded && !widget.playerId.startsWith('bot_')) {
      _statsRecorded = true;
      await StatsService.instance.recordBluffGame(
        uid: widget.playerId,
        won: humanWon,
        bluffsAttempted: _bluffsAttempted,
        bluffsCaught: _bluffsCaught,
        bluffsSucceeded: _bluffsSucceeded,
      );
      StatsService.instance.getStats(widget.playerId).then((s) {
        if (mounted) setState(() => _totalPoints = s.totalPoints);
      });
    }
    setState(() {
      _phase = _Phase.gameOver;
      _overlayMsg = humanWon ? '🎉 You won!' : '${_players[winnerIdx].name} wins!';
    });
    GameLogger.instance.bluffGameEnd(
      sessionKey: _bluffSessionKey,
      winnerName: _players[winnerIdx].name,
      humanWon: humanWon,
      bluffsAttempted: _bluffsAttempted,
      bluffsCaught: _bluffsCaught,
      bluffsSucceeded: _bluffsSucceeded,
    );
    if (humanWon) {
      SoundService.instance.playEscape();
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _rng.nextBool()) AdMobService.instance.showRewardedAsync(context);
      });
    } else {
      SoundService.instance.playDonkey();
    }
  }

  bool _botCalls(int botIdx) {
    final mine = _players[botIdx].hand.where((c) => c.rank == _lastClaimedRank).length;
    final prob = 0.12 + mine * 0.07 + (_pile.length > 10 ? 0.18 : 0);
    return _rng.nextDouble() < prob;
  }

  void _leaveGame() {
    AdMobService.instance.showInterstitialAsync(context).then((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _leaveGame(); },
      child: Scaffold(
      backgroundColor: const Color(0xFF0d0008),
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
                      _buildPile(),
                      Container(height: 1, color: Colors.white10),
                      _buildOpponents(),
                      Container(height: 1, color: Colors.white10),
                      _buildStatus(),
                      Container(height: 1, color: Colors.white10),
                      Expanded(child: _buildHand()),
                      _buildActions(),
                      const AdBannerWidget(),
                    ],
                  ),
                  if (_phase == _Phase.bluffResult || _phase == _Phase.gameOver)
                    _buildOverlay(),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white54, size: 20),
            onPressed: _leaveGame,
          ),
          const Spacer(),
          const Text('BLUFF',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _accent.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⭐', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
                Text('$_totalPoints',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(_isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white54, size: 22),
            onPressed: () => setState(() { _isMuted = !_isMuted; SoundService.instance.toggleMute(); }),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Colors.white54, size: 22),
            onPressed: () => showHowToPlay(context, game: 'bluff'),
          ),
        ],
      ),
    );
  }

  Widget _buildPile() {
    return SizedBox(
      height: 96,
      child: Row(
        children: [
          // Pile visual
          Expanded(
            child: Center(
              child: _pile.isEmpty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 46, height: 62,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Center(child: Text('EMPTY', style: TextStyle(color: Colors.white.withValues(alpha: 0.15), fontSize: 7, letterSpacing: 1))),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 80, height: 66,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              for (int i = 0; i < min(3, _pile.length); i++)
                                Transform.rotate(
                                  angle: (i - 1) * 0.12,
                                  child: CardBackWidget(width: 46, height: 62),
                                ),
                            ],
                          ),
                        ),
                        Text('${_pile.length} cards',
                            style: TextStyle(color: _accent, fontSize: 9, fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
          ),
          Container(width: 1, color: Colors.white10),
          // Current rank
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('PLAY', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 8, letterSpacing: 2)),
                const SizedBox(height: 4),
                Container(
                  width: 54, height: 54,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: _accent.withValues(alpha: 0.5), width: 1.5),
                  ),
                  child: Center(
                    child: Text(_rl(_currentRank),
                        style: const TextStyle(color: _accent, fontSize: 22, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${_rl(_currentRank)}s',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpponents() {
    return SizedBox(
      height: 88,
      child: Row(
        children: [
          for (int i = 1; i <= 3; i++) Expanded(child: _buildOpponentSlot(i)),
        ],
      ),
    );
  }

  Widget _buildOpponentSlot(int idx) {
    final p = _players[idx];
    final isActive = _turnIdx == idx;
    return Container(
      decoration: BoxDecoration(
        color: isActive ? _accent.withValues(alpha: 0.08) : Colors.transparent,
        border: Border(right: idx < 3 ? const BorderSide(color: Colors.white10) : BorderSide.none),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: isActive ? _accent.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isActive ? _accent.withValues(alpha: 0.6) : Colors.white12,
                  ),
                ),
                child: Center(
                  child: p.hand.isEmpty
                      ? const Text('🎉', style: TextStyle(fontSize: 16))
                      : Text('${p.hand.length}',
                          style: TextStyle(
                            color: isActive ? _accent : Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          )),
                ),
              ),
              if (isActive)
                Positioned(
                  top: 0, right: 0,
                  child: Container(
                    width: 10, height: 10,
                    decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(p.name,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.45),
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis),
          Text('cards', style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 8)),
        ],
      ),
    );
  }

  Widget _buildStatus() {
    return SizedBox(
      height: 34,
      child: Center(
        child: Text(
          _status,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildHand() {
    final human = _players[0];
    if (human.hand.isEmpty) {
      return const Center(child: Text('🎉', style: TextStyle(fontSize: 40)));
    }
    final canSelect = _phase == _Phase.playerTurn;
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: human.hand.length,
      itemBuilder: (_, i) {
        final card = human.hand[i];
        final sel = _selected.contains(card);
        return GestureDetector(
          onTap: canSelect
              ? () => setState(() { if (sel) { _selected.remove(card); } else { _selected.add(card); } })
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.only(right: 6),
            transform: Matrix4.translationValues(0, sel ? -12 : 0, 0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CardWidget(card: card, width: 48, height: 68),
                if (sel)
                  Positioned(
                    top: -6, right: -4,
                    child: Container(
                      width: 16, height: 16,
                      decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                      child: const Icon(Icons.check, size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActions() {
    switch (_phase) {
      case _Phase.playerTurn:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _selected.isEmpty ? Colors.white12 : _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _selected.isEmpty ? null : _humanPlay,
              child: Text(
                _selected.isEmpty
                    ? 'SELECT CARDS TO PLAY'
                    : 'PLAY ${_selected.length} CARD${_selected.length > 1 ? "S" : ""} AS ${_rl(_currentRank)}s',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
            ),
          ),
        );

      case _Phase.humanCallWindow:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _callBluff,
                  child: const Text('🚨 CALL BLUFF',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white12,
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _pass,
                  child: const Text('PASS',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        );

      default:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                _phase == _Phase.botTurn
                    ? '${_players[_turnIdx].name} is thinking…'
                    : 'Waiting…',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
              ),
            ),
          ),
        );
    }
  }

  Widget _buildOverlay() {
    final isGameOver = _phase == _Phase.gameOver;
    final humanWon = isGameOver && _overlayMsg.startsWith('🎉');
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF0d0008),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: humanWon
                  ? _accent.withValues(alpha: 0.8)
                  : isGameOver
                      ? Colors.white24
                      : Colors.amber.withValues(alpha: 0.6),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_overlayMsg,
                  style: TextStyle(
                    fontSize: isGameOver ? 22 : 15,
                    fontWeight: FontWeight.w900,
                    color: humanWon ? _accent : Colors.white,
                  ),
                  textAlign: TextAlign.center),
              if (isGameOver) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      setState(_newGame);
                      _logGameStart();
                    },
                    child: const Text('PLAY AGAIN',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _leaveGame,
                  child: Text('Back to Home',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45))),
                ),
              ],
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).scale(begin: const Offset(0.95, 0.95));
  }
}
