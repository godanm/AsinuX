import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/tambola_models.dart';
import '../services/stats_service.dart';
import '../services/tambola_service.dart';
import '../widgets/how_to_play_overlay.dart';

class TambolaGameScreen extends StatefulWidget {
  final String roomId;
  final String playerId;
  final String playerName;
  final bool isHost;

  const TambolaGameScreen({
    super.key,
    required this.roomId,
    required this.playerId,
    required this.playerName,
    required this.isHost,
  });

  @override
  State<TambolaGameScreen> createState() => _TambolaGameScreenState();
}

class _TambolaGameScreenState extends State<TambolaGameScreen> {
  StreamSubscription<TambolaGameState?>? _gameSub;
  StreamSubscription<TambolaTicket?>? _ticketSub;

  TambolaGameState? _game;
  TambolaTicket? _ticket;
  Map<String, TambolaTicket> _allTickets = {};
  Timer? _autoCallTimer;
  bool _statsRecorded = false;

  // Prize claim toasts
  final Set<TambolaPrize> _seenClaimed = {};
  String? _toastMessage;
  Timer? _toastTimer;

  // Bot auto-claiming (host only)
  final Set<TambolaPrize> _botClaimsSent = {};

  static const _accent = Color(0xFFF57C00);
  static const _marked = Color(0xFFF57C00);
  static const _callInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _gameSub = TambolaService.instance
        .gameStream(widget.roomId)
        .listen(_onGameUpdate, onError: (e) {
      if ('$e'.contains('permission-denied')) return;
      debugPrint('[Tambola] game stream error: $e');
    });
    _ticketSub = TambolaService.instance
        .ticketStream(widget.roomId, widget.playerId)
        .listen(_onTicketUpdate, onError: (e) {
      if ('$e'.contains('permission-denied')) return;
      debugPrint('[Tambola] ticket stream error: $e');
    });
    TambolaService.instance
        .readAllTickets(widget.roomId)
        .then((t) {
          if (!mounted) return;
          setState(() => _allTickets = t);
          if (_game != null) _autoBotClaim(_game!);
        });
  }

  @override
  void dispose() {
    _autoCallTimer?.cancel();
    _toastTimer?.cancel();
    _gameSub?.cancel();
    _ticketSub?.cancel();
    super.dispose();
  }

  void _onGameUpdate(TambolaGameState? state) {
    if (!mounted) return;

    // Detect newly claimed prizes before setState
    if (state != null) {
      for (final prize in TambolaPrize.values) {
        if (state.isPrizeClaimed(prize) && !_seenClaimed.contains(prize)) {
          _seenClaimed.add(prize);
          final winnerId = state.prizeWinners[prize];
          final winnerName = state.winnerNameFor(prize, '?') ?? '?';
          if (winnerId != widget.playerId) {
            _showToast('$winnerName claimed ${prize.label}!');
          } else {
            _showToast('You claimed ${prize.label}! 🎉');
          }
        }
      }
    }

    setState(() => _game = state);
    _syncTimer(state);
    if (state != null) _autoBotClaim(state);

    if (state?.phase == TambolaPhase.gameOver &&
        !_statsRecorded &&
        !widget.playerId.startsWith('bot_')) {
      _statsRecorded = true;
      final myWins = TambolaPrize.values
          .where((p) => state!.prizeWinners[p] == widget.playerId)
          .toList();
      StatsService.instance.recordTambolaGame(
        uid: widget.playerId,
        prizesWon: myWins.length,
        wonEarlyFive: myWins.contains(TambolaPrize.earlyFive),
        wonFullHouse: myWins.contains(TambolaPrize.fullHouse),
      );
    }
  }

  void _onTicketUpdate(TambolaTicket? ticket) {
    if (!mounted) return;
    setState(() => _ticket = ticket);
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  void _autoBotClaim(TambolaGameState state) {
    if (!widget.isHost || _allTickets.isEmpty) return;
    if (state.phase != TambolaPhase.playing) return;
    final called = state.calledNumbers;
    for (final prize in TambolaPrize.values) {
      if (state.isPrizeClaimed(prize)) continue;
      if (_botClaimsSent.contains(prize)) continue;
      for (final pid in state.players.keys) {
        if (!pid.startsWith('bot_')) continue;
        final ticket = _allTickets[pid];
        if (ticket == null) continue;
        final eligible = switch (prize) {
          TambolaPrize.earlyFive => ticket.isEarlyFive(called),
          TambolaPrize.topLine => ticket.isRowComplete(0, called),
          TambolaPrize.middleLine => ticket.isRowComplete(1, called),
          TambolaPrize.bottomLine => ticket.isRowComplete(2, called),
          TambolaPrize.fullHouse => ticket.isFullHouse(called),
        };
        if (eligible) {
          _botClaimsSent.add(prize);
          final capturedPid = pid;
          final capturedTicket = ticket;
          Future.delayed(const Duration(milliseconds: 600), () {
            TambolaService.instance.claimPrize(
              roomId: widget.roomId,
              playerId: capturedPid,
              prize: prize,
              ticket: capturedTicket,
            );
          });
          break;
        }
      }
    }
  }

  void _syncTimer(TambolaGameState? state) {
    if (!widget.isHost) return;
    if (state?.phase == TambolaPhase.playing) {
      if (_autoCallTimer == null || !_autoCallTimer!.isActive) {
        _autoCallTimer = Timer.periodic(_callInterval, (_) => _callNext());
      }
    } else {
      _autoCallTimer?.cancel();
      _autoCallTimer = null;
    }
  }

  Future<void> _callNext() async {
    final game = _game;
    if (game == null || game.phase != TambolaPhase.playing) return;
    await TambolaService.instance.callNextNumber(widget.roomId);
  }

  Future<void> _togglePause() async {
    final game = _game;
    if (game == null) return;
    if (game.phase == TambolaPhase.playing) {
      await TambolaService.instance.pauseGame(widget.roomId);
    } else if (game.phase == TambolaPhase.paused) {
      await TambolaService.instance.resumeGame(widget.roomId);
    }
  }

  Future<void> _claimPrize(TambolaPrize prize) async {
    final ticket = _ticket;
    if (ticket == null) return;
    final error = await TambolaService.instance.claimPrize(
      roomId: widget.roomId,
      playerId: widget.playerId,
      prize: prize,
      ticket: ticket,
    );
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  bool _canClaim(TambolaPrize prize) {
    final game = _game;
    final ticket = _ticket;
    if (game == null || ticket == null) return false;
    if (game.isPrizeClaimed(prize)) return false;
    if (game.phase != TambolaPhase.playing) return false;
    final called = game.calledNumbers;
    return switch (prize) {
      TambolaPrize.earlyFive => ticket.isEarlyFive(called),
      TambolaPrize.topLine => ticket.isRowComplete(0, called),
      TambolaPrize.middleLine => ticket.isRowComplete(1, called),
      TambolaPrize.bottomLine => ticket.isRowComplete(2, called),
      TambolaPrize.fullHouse => ticket.isFullHouse(called),
    };
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final ticket = _ticket;
    final called = game?.calledNumbers ?? [];
    final currentNum = game?.currentNumber;
    final recentNums = called.reversed.skip(1).take(5).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (game?.phase == TambolaPhase.gameOver) {
          nav.popUntil((r) => r.isFirst);
          return;
        }
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0a0820),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Leave game?', style: TextStyle(color: Colors.white)),
            content: const Text(
              'Your ticket will be forfeited.',
              style: TextStyle(color: Colors.white54),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('STAY', style: TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: const Text('LEAVE'),
              ),
            ],
          ),
        );
        if (leave == true) nav.popUntil((r) => r.isFirst);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF04061a),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(game),
                  _buildNumberDisplay(currentNum, recentNums),
                  const SizedBox(height: 10),
                  if (game != null) _buildPlayerProgress(game),
                  const SizedBox(height: 10),
                  if (ticket != null) _buildTicket(ticket, called),
                  if (ticket == null)
                    const Expanded(
                      child: Center(
                        child: CircularProgressIndicator(color: _accent),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (game != null) _buildPrizePanel(game),
                  const SizedBox(height: 16),
                ],
              ),

              // ── Prize claim toast ─────────────────────────────────────
              if (_toastMessage != null)
                Positioned(
                  top: 8,
                  left: 16,
                  right: 16,
                  child: _PrizeToast(message: _toastMessage!),
                ),

              // ── Game over overlay ─────────────────────────────────────
              if (game?.phase == TambolaPhase.gameOver)
                _GameOverOverlay(
                  game: game!,
                  myPlayerId: widget.playerId,
                  onDone: () => Navigator.of(context).popUntil((r) => r.isFirst),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(TambolaGameState? game) {
    final isPaused = game?.phase == TambolaPhase.paused;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [Color(0xFFF57C00), Color(0xFFFFCC02)],
            ).createShader(b),
            child: const Text(
              'TAMBOLA',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Colors.white38),
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => showHowToPlay(context, game: 'tambola'),
          ),
          const SizedBox(width: 8),
          if (game != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Text(
                '${90 - game.calledNumbers.length} left',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (widget.isHost && game != null && game.phase != TambolaPhase.gameOver) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _togglePause,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isPaused
                      ? _accent.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isPaused
                        ? _accent.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Icon(
                  isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: isPaused ? _accent : Colors.white70,
                  size: 18,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNumberDisplay(int? currentNum, List<int> recentNums) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: currentNum != null
                ? Text(
                    '$currentNum',
                    key: ValueKey(currentNum),
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  )
                : Text(
                    '—',
                    key: const ValueKey('waiting'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.2),
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
          ),
          if (recentNums.isNotEmpty) ...[
            const SizedBox(width: 16),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'RECENT',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: recentNums.map((n) => Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.07),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$n',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )).toList(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayerProgress(TambolaGameState game) {
    final called = game.calledNumbers;
    final players = game.players.entries.toList()
      ..sort((a, b) {
        final aMarked = _allTickets[a.key]?.allNumbers.where(called.contains).length ?? 0;
        final bMarked = _allTickets[b.key]?.allNumbers.where(called.contains).length ?? 0;
        return bMarked.compareTo(aMarked);
      });

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: players.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final pid = players[i].key;
          final name = players[i].value.name;
          final ticket = _allTickets[pid];
          final marked = ticket?.allNumbers.where(called.contains).length ?? 0;
          final isMe = pid == widget.playerId;
          return _PlayerProgressCard(
            name: name,
            marked: marked,
            isMe: isMe,
          );
        },
      ),
    );
  }

  Widget _buildTicket(TambolaTicket ticket, List<int> called) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                children: List.generate(3, (row) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: List.generate(9, (col) {
                        final num = ticket.grid[row][col];
                        final isBlank = num == 0;
                        final isMarked = !isBlank && called.contains(num);
                        return Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            height: 40,
                            decoration: BoxDecoration(
                              color: isBlank
                                  ? Colors.transparent
                                  : isMarked
                                      ? _marked.withValues(alpha: 0.9)
                                      : Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(6),
                              border: isBlank
                                  ? null
                                  : Border.all(
                                      color: isMarked
                                          ? _marked
                                          : Colors.white.withValues(alpha: 0.12),
                                      width: isMarked ? 1.5 : 1,
                                    ),
                            ),
                            alignment: Alignment.center,
                            child: isBlank
                                ? null
                                : Text(
                                    '$num',
                                    style: TextStyle(
                                      color: isMarked
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.65),
                                      fontSize: 13,
                                      fontWeight: isMarked
                                          ? FontWeight.w900
                                          : FontWeight.normal,
                                    ),
                                  ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrizePanel(TambolaGameState game) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: TambolaPrize.values.map((prize) {
          final claimed = game.isPrizeClaimed(prize);
          final winnerName = game.winnerNameFor(prize, '?');
          final canClaim = _canClaim(prize);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: claimed
                        ? Colors.greenAccent.shade400
                        : Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    prize.label,
                    style: TextStyle(
                      color: claimed
                          ? Colors.white.withValues(alpha: 0.9)
                          : Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                      fontWeight: claimed ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (claimed && winnerName != null)
                  Text(
                    winnerName,
                    style: TextStyle(
                      color: Colors.greenAccent.shade400,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else if (canClaim)
                  GestureDetector(
                    onTap: () => _claimPrize(prize),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF57C00), Color(0xFF7f3c00)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'CLAIM',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ).animate().scale(duration: 200.ms)
                else
                  Text(
                    '—',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.2),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Player progress card ──────────────────────────────────────────────────────

class _PlayerProgressCard extends StatelessWidget {
  final String name;
  final int marked;
  final bool isMe;

  const _PlayerProgressCard({
    required this.name,
    required this.marked,
    required this.isMe,
  });

  static const _accent = Color(0xFFF57C00);

  @override
  Widget build(BuildContext context) {
    const total = 15;
    final progress = marked / total;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMe
            ? _accent.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMe
              ? _accent.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name.length > 8 ? '${name.substring(0, 7)}…' : name,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.white.withValues(alpha: 0.65),
                  fontSize: 11,
                  fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$marked/$total',
                style: TextStyle(
                  color: isMe ? _accent : Colors.white.withValues(alpha: 0.35),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 90,
            height: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(
                  isMe ? _accent : Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Prize claim toast ─────────────────────────────────────────────────────────

class _PrizeToast extends StatelessWidget {
  final String message;
  const _PrizeToast({required this.message});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1a0d00),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF57C00).withValues(alpha: 0.5)),
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
            const Text('🏆', style: TextStyle(fontSize: 14)),
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
  final TambolaGameState game;
  final String myPlayerId;
  final VoidCallback onDone;

  const _GameOverOverlay({
    required this.game,
    required this.myPlayerId,
    required this.onDone,
  });

  static const _accent = Color(0xFFF57C00);

  @override
  Widget build(BuildContext context) {
    final myWins = TambolaPrize.values
        .where((p) => game.prizeWinners[p] == myPlayerId)
        .toList();
    final didWin = myWins.isNotEmpty;

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
                didWin ? '🎉' : '🎟',
                style: const TextStyle(fontSize: 48),
              ),
              const SizedBox(height: 12),
              Text(
                didWin ? 'You won!' : 'Game over',
                style: TextStyle(
                  color: didWin ? _accent : Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (didWin) ...[
                const SizedBox(height: 6),
                Text(
                  myWins.map((p) => p.label).join(' · '),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              ...TambolaPrize.values.map((prize) {
                final winnerId = game.prizeWinners[prize];
                final winnerName = game.winnerNameFor(prize, '?');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Text(
                        prize.label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        winnerName ?? '—',
                        style: TextStyle(
                          color: winnerId == myPlayerId
                              ? _accent
                              : Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                          fontWeight: winnerId == myPlayerId
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }),
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
