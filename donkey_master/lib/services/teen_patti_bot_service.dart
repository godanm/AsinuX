import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/card_model.dart';
import '../models/teen_patti_state.dart';
import 'teen_patti_service.dart';
import 'teen_patti_bot_logic.dart';

class TeenPattiBotService {
  static final TeenPattiBotService instance = TeenPattiBotService._();
  TeenPattiBotService._();

  StreamSubscription<TeenPattiState?>? _sub;
  Timer? _timeoutTimer;
  String? _roomId;
  bool _processing = false;
  TeenPattiState? _missedState; // state received while _processing was true
  final _rng = Random();

  static const _turnTimeoutMs = 20000; // 20 s auto-fold per spec
  static const _botThinkMinMs = 800;
  static const _botThinkRangeMs = 1400;

  bool get isRunning => _sub != null;

  void start(String roomId) {
    if (_sub != null && _roomId == roomId) return;
    stop();
    _roomId = roomId;
    _sub = TeenPattiService.instance
        .roomStream(roomId)
        .listen(_onStateChange);
    debugPrint('[TeenPattiBotService] started for $roomId');
  }

  void stop() {
    _sub?.cancel();
    _timeoutTimer?.cancel();
    _sub = null;
    _timeoutTimer = null;
    _roomId = null;
    _processing = false;
  }

  void _onStateChange(TeenPattiState? state) {
    if (state == null) return;
    _resetTimeoutTimer(state);

    if (state.phase == TeenPattiPhase.sideshowPending) {
      _handleSideshowPending(state);
      return;
    }

    if (state.phase != TeenPattiPhase.betting) return;

    final currentId = state.currentTurn;
    if (currentId == null) return;
    final player = state.players[currentId];
    if (player == null || !player.isBot) return;
    if (_processing) {
      _missedState = state; // will be replayed once the current action finishes
      return;
    }

    final thinkMs = _botThinkMinMs + _rng.nextInt(_botThinkRangeMs);
    Future.delayed(
      Duration(milliseconds: thinkMs),
      () => _takeTurn(state, currentId),
    );
  }

  // ── Turn timeout ─────────────────────────────────────────────────────────────

  void _resetTimeoutTimer(TeenPattiState state) {
    _timeoutTimer?.cancel();
    if (state.phase != TeenPattiPhase.betting) return;
    if (state.currentTurn == null) return;
    if (state.players[state.currentTurn!]?.isBot ?? false) return;

    _timeoutTimer = Timer(
      const Duration(milliseconds: _turnTimeoutMs),
      () => _triggerTimeout(state.roomId, state.currentTurn!),
    );
  }

  Future<void> _triggerTimeout(String roomId, String playerId) async {
    final fresh = await TeenPattiService.instance.getFreshState(roomId);
    if (fresh == null) return;
    if (fresh.currentTurn != playerId) return; // turn has already moved on
    debugPrint('[TeenPattiBotService] timeout: auto-folding $playerId');
    await TeenPattiService.instance.timeoutFold(fresh);
  }

  // ── Bot turn ──────────────────────────────────────────────────────────────────

  Future<void> _takeTurn(TeenPattiState state, String botId) async {
    if (_processing) return;
    _processing = true;
    try {
      final fresh =
          await TeenPattiService.instance.getFreshState(state.roomId);
      if (fresh == null || fresh.currentTurn != botId) return;
      if (fresh.phase != TeenPattiPhase.betting) return;

      final bot = fresh.players[botId]!;

      // Decide whether to peek at cards first
      if (bot.isBlind &&
          TeenPattiBotLogic.shouldSeeCards(
              bot: bot, state: fresh, rng: _rng)) {
        await TeenPattiService.instance.seeCards(fresh, botId);
        final updated =
            await TeenPattiService.instance.getFreshState(state.roomId);
        if (updated == null || updated.currentTurn != botId) return;
        await _executeAction(updated, botId);
        return;
      }

      await _executeAction(fresh, botId);
    } finally {
      _processing = false;
      final missed = _missedState;
      _missedState = null;
      if (missed != null) _onStateChange(missed);
    }
  }

  Future<void> _executeAction(TeenPattiState state, String botId) async {
    final bot = state.players[botId]!;
    final cards = bot.isSeen
        ? await TeenPattiService.instance.getCards(state.roomId, botId)
        : <PlayingCard>[];

    final canSideshow = bot.isSeen &&
        state.lastActorId != null &&
        (state.players[state.lastActorId!]?.isSeen ?? false) &&
        state.activePlayers.length > 2; // sideshow not available when only 2 remain

    BotAction action = TeenPattiBotLogic.decide(
      bot: bot,
      hand: cards,
      state: state,
      rng: _rng,
    );

    // Downgrade sideshow request if not eligible
    if (action == BotAction.requestSideshow && !canSideshow) {
      action = BotAction.chaal;
    }

    switch (action) {
      case BotAction.fold:
        await TeenPattiService.instance.fold(state, botId);
      case BotAction.chaal:
        await TeenPattiService.instance.chaal(state, botId);
      case BotAction.raise:
        await TeenPattiService.instance.raise(state, botId);
      case BotAction.requestSideshow:
        await TeenPattiService.instance.requestSideshow(state, botId);
    }
  }

  // ── Sideshow pending ──────────────────────────────────────────────────────────

  void _handleSideshowPending(TeenPattiState state) {
    final targetId = state.sideshowTargetId;
    if (targetId == null) return;
    final target = state.players[targetId];
    if (target == null || !target.isBot) return;
    if (_processing) return;

    final delayMs = 600 + _rng.nextInt(800);
    Future.delayed(Duration(milliseconds: delayMs),
        () => _respondSideshow(state, targetId));
  }

  Future<void> _respondSideshow(TeenPattiState state, String botId) async {
    if (_processing) return;
    _processing = true;
    try {
      final fresh =
          await TeenPattiService.instance.getFreshState(state.roomId);
      if (fresh == null || fresh.sideshowTargetId != botId) return;
      // Bots accept sideshows 70 % of the time
      final accepted = _rng.nextDouble() < 0.70;
      await TeenPattiService.instance.respondSideshow(fresh, botId, accepted);
    } finally {
      _processing = false;
      final missed = _missedState;
      _missedState = null;
      if (missed != null) _onStateChange(missed);
    }
  }
}
