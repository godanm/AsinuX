import 'dart:math';
import 'package:flutter/material.dart';

// ── Enums ──────────────────────────────────────────────────────────────────────

enum WildCardColor { red, blue, green, yellow, wild }

enum WildCardType { number, skip, reverse, draw2, wild, wildDraw4 }

// ── Card ───────────────────────────────────────────────────────────────────────

class WildPlayCard {
  final WildCardColor color;
  final WildCardType type;
  final int? value;

  const WildPlayCard({required this.color, required this.type, this.value});

  String get label {
    switch (type) {
      case WildCardType.number:
        return '${value ?? 0}';
      case WildCardType.skip:
        return '⊘';
      case WildCardType.reverse:
        return '⇄';
      case WildCardType.draw2:
        return '+2';
      case WildCardType.wild:
        return 'W';
      case WildCardType.wildDraw4:
        return '+4';
    }
  }

  Color get colorValue {
    switch (color) {
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

  bool canPlayOn(WildPlayCard discard, WildCardColor currentColor) {
    if (type == WildCardType.wild || type == WildCardType.wildDraw4) return true;
    if (color == currentColor) return true;
    if (color == discard.color && discard.color != WildCardColor.wild) {
      return true;
    }
    if (type == discard.type && type != WildCardType.number) {
      return true;
    }
    if (type == WildCardType.number &&
        discard.type == WildCardType.number &&
        value == discard.value) {
      return true;
    }
    return false;
  }

  Map<String, dynamic> toMap() => {
        'c': colorKey(color),
        't': _typeKey(type),
        if (value != null) 'v': value,
      };

  factory WildPlayCard.fromMap(Map<dynamic, dynamic> m) {
    return WildPlayCard(
      color: colorFromKey(m['c'] as String? ?? 'wild'),
      type: _typeFromKey(m['t'] as String? ?? 'w'),
      value: m['v'] != null ? (m['v'] as num).toInt() : null,
    );
  }

  static String colorKey(WildCardColor c) => switch (c) {
        WildCardColor.red => 'red',
        WildCardColor.blue => 'blue',
        WildCardColor.green => 'green',
        WildCardColor.yellow => 'yellow',
        WildCardColor.wild => 'wild',
      };

  static String _typeKey(WildCardType t) => switch (t) {
        WildCardType.number => 'n',
        WildCardType.skip => 's',
        WildCardType.reverse => 'r',
        WildCardType.draw2 => 'd2',
        WildCardType.wild => 'w',
        WildCardType.wildDraw4 => 'wd4',
      };

  static WildCardColor colorFromKey(String s) => switch (s) {
        'red' => WildCardColor.red,
        'blue' => WildCardColor.blue,
        'green' => WildCardColor.green,
        'yellow' => WildCardColor.yellow,
        _ => WildCardColor.wild,
      };

  static WildCardType _typeFromKey(String s) => switch (s) {
        'n' => WildCardType.number,
        's' => WildCardType.skip,
        'r' => WildCardType.reverse,
        'd2' => WildCardType.draw2,
        'wd4' => WildCardType.wildDraw4,
        _ => WildCardType.wild,
      };
}

// ── Deck generator ─────────────────────────────────────────────────────────────

List<WildPlayCard> generateDeck(Random rng) {
  final deck = <WildPlayCard>[];
  const colors = [
    WildCardColor.red,
    WildCardColor.blue,
    WildCardColor.green,
    WildCardColor.yellow,
  ];
  for (final color in colors) {
    deck.add(WildPlayCard(color: color, type: WildCardType.number, value: 0));
    for (int n = 1; n <= 9; n++) {
      deck.add(WildPlayCard(color: color, type: WildCardType.number, value: n));
      deck.add(WildPlayCard(color: color, type: WildCardType.number, value: n));
    }
    for (int i = 0; i < 2; i++) {
      deck.add(WildPlayCard(color: color, type: WildCardType.skip));
      deck.add(WildPlayCard(color: color, type: WildCardType.reverse));
      deck.add(WildPlayCard(color: color, type: WildCardType.draw2));
    }
  }
  for (int i = 0; i < 4; i++) {
    deck.add(const WildPlayCard(color: WildCardColor.wild, type: WildCardType.wild));
    deck.add(const WildPlayCard(color: WildCardColor.wild, type: WildCardType.wildDraw4));
  }
  deck.shuffle(rng);
  return deck;
}

// ── Game state ─────────────────────────────────────────────────────────────────

class WildCardGameState {
  final String roomId;
  final String phase;
  final List<String> playerOrder;
  final int currentPlayerIdx;
  final int direction;
  final WildCardColor currentColor;
  final WildPlayCard discardTop;
  final Map<String, int> cardCounts;
  final Map<String, String> playerNames;
  final String? winner;
  final int? pendingDraw;

  const WildCardGameState({
    required this.roomId,
    required this.phase,
    required this.playerOrder,
    required this.currentPlayerIdx,
    required this.direction,
    required this.currentColor,
    required this.discardTop,
    required this.cardCounts,
    required this.playerNames,
    this.winner,
    this.pendingDraw,
  });

  String get currentPlayerId => playerOrder[currentPlayerIdx];

  bool isMyTurn(String pid) => currentPlayerId == pid && phase == 'playing';

  int nextPlayerIdx({int skip = 0}) {
    final n = playerOrder.length;
    return (currentPlayerIdx + direction * (1 + skip) % n + n * 2) % n;
  }

  factory WildCardGameState.fromMap(String roomId, Map<dynamic, dynamic> m) {
    final orderRaw = m['playerOrder'];
    final playerOrder = (orderRaw is List
            ? orderRaw
            : orderRaw is Map
                ? orderRaw.values.toList()
                : <dynamic>[])
        .map((e) => e as String)
        .toList();

    final countsRaw = m['cardCounts'] != null
        ? Map<String, dynamic>.from(m['cardCounts'] as Map)
        : <String, dynamic>{};
    final cardCounts = {
      for (final e in countsRaw.entries) e.key: (e.value as num).toInt(),
    };

    final namesRaw = m['playerNames'] != null
        ? Map<String, dynamic>.from(m['playerNames'] as Map)
        : <String, dynamic>{};
    final playerNames = {
      for (final e in namesRaw.entries) e.key: e.value as String,
    };

    final discardRaw = m['discardTop'] != null
        ? Map<dynamic, dynamic>.from(m['discardTop'] as Map)
        : <dynamic, dynamic>{'c': 'wild', 't': 'w'};
    final discardTop = WildPlayCard.fromMap(discardRaw);

    final colorStr = m['currentColor'] as String? ?? 'wild';
    final currentColor = WildPlayCard.colorFromKey(colorStr);

    return WildCardGameState(
      roomId: roomId,
      phase: m['phase'] as String? ?? 'waiting',
      playerOrder: playerOrder,
      currentPlayerIdx: (m['currentPlayerIdx'] as num?)?.toInt() ?? 0,
      direction: (m['direction'] as num?)?.toInt() ?? 1,
      currentColor: currentColor,
      discardTop: discardTop,
      cardCounts: cardCounts,
      playerNames: playerNames,
      winner: m['winner'] as String?,
      pendingDraw: m['pendingDraw'] != null ? (m['pendingDraw'] as num).toInt() : null,
    );
  }
}
