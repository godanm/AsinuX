import 'dart:math';

List<dynamic> _fbList(dynamic v) {
  if (v is List) return v;
  if (v is Map) return v.values.toList();
  return [];
}

// ── Ticket ─────────────────────────────────────────────────────────────────────
// 3 rows × 9 columns. grid[row][col] == 0 means blank.
// Col 0: 1–9 | Col 1: 10–19 | … | Col 8: 80–90
// Each row has exactly 5 numbers and 4 blanks.

class TambolaTicket {
  final List<List<int>> grid;

  const TambolaTicket({required this.grid});

  static TambolaTicket generate(Random rng) =>
      TambolaTicket(grid: _generateGrid(rng));

  // ── Ticket generation ───────────────────────────────────────────────────────
  // 6 columns get 2 numbers, 3 get 1 → total = 15 (5 per row).
  // Backtracking assigns rows to each column, then fills in actual values.
  static List<List<int>> _generateGrid(Random rng) {
    final colCounts = [...List.filled(6, 2), ...List.filled(3, 1)];
    final grid = List.generate(3, (_) => List.filled(9, 0));
    final rowRem = [5, 5, 5];
    final colRows = <List<int>>[];

    bool assign(int col) {
      if (col == 9) return rowRem.every((r) => r == 0);
      final count = colCounts[col];
      final avail = [for (int r = 0; r < 3; r++) if (rowRem[r] > 0) r];
      if (avail.length < count) return false;
      for (final combo in _rowCombos(avail, count)) {
        for (final r in combo) {
          rowRem[r]--;
        }
        colRows.add(combo);
        if (assign(col + 1)) return true;
        colRows.removeLast();
        for (final r in combo) {
          rowRem[r]++;
        }
      }
      return false;
    }

    for (int attempt = 0; attempt < 50; attempt++) {
      colCounts.shuffle(rng);
      rowRem.setAll(0, [5, 5, 5]);
      colRows.clear();
      if (assign(0)) break;
    }

    for (int col = 0; col < 9 && col < colRows.length; col++) {
      final lo = col == 0 ? 1 : col * 10;
      final hi = col == 8 ? 90 : col * 10 + 9;
      final pool = List.generate(hi - lo + 1, (i) => lo + i)..shuffle(rng);
      final nums = pool.sublist(0, colRows[col].length)..sort();
      for (int i = 0; i < nums.length; i++) {
        grid[colRows[col][i]][col] = nums[i];
      }
    }
    return grid;
  }

  static List<List<int>> _rowCombos(List<int> pool, int k) {
    if (k == 0) return [[]];
    if (pool.length < k) return [];
    final result = <List<int>>[];
    for (int i = 0; i <= pool.length - k; i++) {
      for (final rest in _rowCombos(pool.sublist(i + 1), k - 1)) {
        result.add([pool[i], ...rest]);
      }
    }
    return result;
  }

  // ── Prize checks ────────────────────────────────────────────────────────────

  List<int> get allNumbers =>
      [for (final row in grid) for (final n in row) if (n > 0) n];

  bool isEarlyFive(List<int> called) {
    int count = 0;
    for (final row in grid) {
      for (final n in row) {
        if (n > 0 && called.contains(n)) {
          count++;
          if (count >= 5) return true;
        }
      }
    }
    return false;
  }

  bool isRowComplete(int row, List<int> called) =>
      grid[row].where((n) => n > 0).every(called.contains);

  bool isFullHouse(List<int> called) =>
      allNumbers.every(called.contains);

  // ── Serialisation ───────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'grid': grid.map((row) => row.toList()).toList(),
      };

  factory TambolaTicket.fromMap(Map<dynamic, dynamic> map) {
    final gridRaw = _fbList(map['grid']);
    return TambolaTicket(
      grid: gridRaw.map((row) {
        final rowList = row is List ? row : (row is Map ? row.values.toList() : <dynamic>[]);
        return rowList.map((n) => (n as num).toInt()).toList();
      }).toList(),
    );
  }
}

// ── Phase ──────────────────────────────────────────────────────────────────────

enum TambolaPhase { waiting, playing, paused, gameOver }

TambolaPhase tambolaPhaseFromString(String s) => switch (s) {
      'playing' => TambolaPhase.playing,
      'paused' => TambolaPhase.paused,
      'gameOver' => TambolaPhase.gameOver,
      _ => TambolaPhase.waiting,
    };

// ── Prize ──────────────────────────────────────────────────────────────────────

enum TambolaPrize { earlyFive, topLine, middleLine, bottomLine, fullHouse }

extension TambolaPrizeExt on TambolaPrize {
  String get label => switch (this) {
        TambolaPrize.earlyFive => 'Early Five',
        TambolaPrize.topLine => 'Top Line',
        TambolaPrize.middleLine => 'Middle Line',
        TambolaPrize.bottomLine => 'Bottom Line',
        TambolaPrize.fullHouse => 'Full House',
      };

  String get key => switch (this) {
        TambolaPrize.earlyFive => 'earlyFive',
        TambolaPrize.topLine => 'topLine',
        TambolaPrize.middleLine => 'middleLine',
        TambolaPrize.bottomLine => 'bottomLine',
        TambolaPrize.fullHouse => 'fullHouse',
      };
}

TambolaPrize? tambolaPrizeFromKey(String key) =>
    TambolaPrize.values.where((p) => p.key == key).firstOrNull;

// ── Player ─────────────────────────────────────────────────────────────────────

class TambolaPlayer {
  final String id;
  final String name;

  const TambolaPlayer({required this.id, required this.name});

  factory TambolaPlayer.fromMap(String id, Map<dynamic, dynamic> map) =>
      TambolaPlayer(id: id, name: (map['name'] as String?) ?? id);

  Map<String, dynamic> toMap() => {'name': name};
}

// ── Game State ─────────────────────────────────────────────────────────────────

class TambolaGameState {
  final String roomId;
  final TambolaPhase phase;
  final List<int> calledNumbers;
  final Map<String, TambolaPlayer> players;
  final Map<TambolaPrize, String> prizeWinners; // prize → winnerId
  final String hostId;
  final int remainingCount;

  const TambolaGameState({
    required this.roomId,
    required this.phase,
    required this.calledNumbers,
    required this.players,
    required this.prizeWinners,
    required this.hostId,
    required this.remainingCount,
  });

  int? get currentNumber =>
      calledNumbers.isNotEmpty ? calledNumbers.last : null;

  bool isPrizeClaimed(TambolaPrize prize) => prizeWinners.containsKey(prize);

  String? winnerNameFor(TambolaPrize prize, String fallback) {
    final id = prizeWinners[prize];
    if (id == null) return null;
    return players[id]?.name ?? fallback;
  }

  factory TambolaGameState.fromMap(
      String roomId, Map<dynamic, dynamic> map) {
    final playersRaw = map['players'] != null
        ? Map<String, dynamic>.from(map['players'] as Map)
        : <String, dynamic>{};
    final players = <String, TambolaPlayer>{
      for (final e in playersRaw.entries)
        e.key: TambolaPlayer.fromMap(e.key, Map<dynamic, dynamic>.from(e.value as Map)),
    };

    final calledRaw =
        (map['calledNumbers'] as List?)?.cast<dynamic>() ?? [];
    final calledNumbers =
        calledRaw.map((n) => (n as num).toInt()).toList();

    final prizesRaw = map['prizeWinners'] != null
        ? Map<String, dynamic>.from(map['prizeWinners'] as Map)
        : <String, dynamic>{};
    final prizeWinners = <TambolaPrize, String>{};
    for (final e in prizesRaw.entries) {
      final prize = tambolaPrizeFromKey(e.key);
      if (prize != null) prizeWinners[prize] = e.value as String;
    }

    final remainingRaw =
        (map['remainingNumbers'] as List?)?.cast<dynamic>() ?? [];

    return TambolaGameState(
      roomId: roomId,
      phase: tambolaPhaseFromString(map['phase'] as String? ?? 'waiting'),
      calledNumbers: calledNumbers,
      players: players,
      prizeWinners: prizeWinners,
      hostId: map['hostId'] as String? ?? '',
      remainingCount: remainingRaw.length,
    );
  }
}
