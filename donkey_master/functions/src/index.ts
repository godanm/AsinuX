import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

admin.initializeApp({
  databaseURL: "https://asinux-89da0-default-rtdb.firebaseio.com",
});

// ── Types ─────────────────────────────────────────────────────────────────────

interface RummyCard {
  rank: number;          // 1–13; 0 for printed joker
  suit: number;          // 0–3;  -1 for printed joker
  isPrintedJoker: boolean;
}

// ── Deck helpers ──────────────────────────────────────────────────────────────

function buildRummyDeck(): RummyCard[] {
  const cards: RummyCard[] = [];
  for (let d = 0; d < 2; d++) {
    for (let s = 0; s < 4; s++) {
      for (let r = 1; r <= 13; r++) {
        cards.push({ rank: r, suit: s, isPrintedJoker: false });
      }
    }
  }
  cards.push({ rank: 0, suit: -1, isPrintedJoker: true });
  cards.push({ rank: 0, suit: -1, isPrintedJoker: true });
  return cards; // 106 cards total
}

function shuffle<T>(arr: T[]): void {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
}

// ── Meld validation helpers ───────────────────────────────────────────────────

function isJoker(card: RummyCard, wildRank: number): boolean {
  return card.isPrintedJoker || card.rank === wildRank;
}

function cardPoints(card: RummyCard): number {
  if (card.isPrintedJoker || card.rank === 0) return 0;
  return card.rank >= 10 ? 10 : card.rank;
}

function isValidSequence(cards: RummyCard[], wildRank: number): boolean {
  if (cards.length < 3) return false;
  const naturals = cards.filter((c) => !isJoker(c, wildRank));
  if (naturals.length === 0) return false;

  const suit = naturals[0].suit;
  if (!naturals.every((c) => c.suit === suit)) return false;

  const jokerCount = cards.length - naturals.length;

  function checkRanks(ranks: number[]): boolean {
    const sorted = [...ranks].sort((a, b) => a - b);
    for (let i = 1; i < sorted.length; i++) {
      if (sorted[i] === sorted[i - 1]) return false;
    }
    let gapsNeeded = 0;
    for (let i = 1; i < sorted.length; i++) {
      gapsNeeded += sorted[i] - sorted[i - 1] - 1;
    }
    return gapsNeeded <= jokerCount;
  }

  const baseRanks = naturals.map((c) => c.rank);
  if (checkRanks(baseRanks)) return true;

  // Try Ace as high (14) for Q-K-A sequences
  if (baseRanks.includes(1)) {
    const highAceRanks = baseRanks.map((r) => r === 1 ? 14 : r);
    if (checkRanks(highAceRanks)) return true;
  }

  return false;
}

function isPureSequence(cards: RummyCard[], wildRank: number): boolean {
  return cards.every((c) => !isJoker(c, wildRank)) &&
    isValidSequence(cards, wildRank);
}

function isValidSet(cards: RummyCard[], wildRank: number): boolean {
  if (cards.length < 3 || cards.length > 4) return false;
  const naturals = cards.filter((c) => !isJoker(c, wildRank));
  if (naturals.length === 0) return false;

  const rank = naturals[0].rank;
  if (!naturals.every((c) => c.rank === rank)) return false;

  const suits = naturals.map((c) => c.suit);
  return new Set(suits).size === suits.length;
}

function validateDeclaration(melds: RummyCard[][], wildRank: number): string | null {
  if (melds.length === 0) return "No melds provided";
  if (melds.filter((m) => isValidSequence(m, wildRank)).length < 2) {
    return "Need at least 2 sequences";
  }
  if (!melds.some((m) => isPureSequence(m, wildRank))) {
    return "Need at least 1 pure sequence (no jokers)";
  }
  if (!melds.every((m) => isValidSequence(m, wildRank) || isValidSet(m, wildRank))) {
    return "All groups must be valid sequences or sets";
  }
  return null;
}

// ── Cloud Function: dealRummyGame ─────────────────────────────────────────────
//
// Called by the host instead of dealing cards locally. The full deck and all
// hands are computed server-side and written directly to
// rummy_hands/{roomId}/{playerId} via the Admin SDK (bypasses client rules).
// No client ever receives the complete deck or any other player's hand.

export const dealRummyGame = onCall({ invoker: "public" }, async (request) => {
  try {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const { roomId, sessionScores, targetScore, round, nextRound } = request.data as {
    roomId?: string;
    sessionScores?: Record<string, number>;
    targetScore?: number;
    round?: number;
    nextRound?: boolean;
  };
  if (!roomId || typeof roomId !== "string") {
    throw new HttpsError("invalid-argument", "roomId is required");
  }

  const db = admin.database();
  const roomSnap = await db.ref(`rummy_rooms/${roomId}`).get();
  if (!roomSnap.exists()) throw new HttpsError("not-found", "Room not found");

  const room = roomSnap.val() as Record<string, unknown>;
  if (room.hostId !== uid) {
    throw new HttpsError("permission-denied", "Only the host can start the game");
  }
  const allowedStatuses = nextRound ? ["ready", "started"] : ["ready"];
  if (!allowedStatuses.includes(room.status as string)) {
    throw new HttpsError(
      "failed-precondition",
      `Room is '${room.status as string}', expected 'ready'`
    );
  }

  const playersMap = (room.players ?? {}) as Record<
    string, { name: string; joinedAt: number }
  >;
  const turnOrder = Object.entries(playersMap)
    .sort(([, a], [, b]) => (a.joinedAt ?? 0) - (b.joinedAt ?? 0))
    .map(([id]) => id);

  if (turnOrder.length < 2) {
    throw new HttpsError("failed-precondition", "Need at least 2 players");
  }

  const deck = buildRummyDeck();
  shuffle(deck);

  const wildIdx = deck.findIndex((c) => !c.isPrintedJoker);
  const [wildJoker] = deck.splice(wildIdx, 1);

  const hands: Record<string, RummyCard[]> = {};
  for (const id of turnOrder) {
    hands[id] = deck.splice(0, 13);
  }
  const [firstOpen] = deck.splice(0, 1);

  const playersMeta: Record<string, unknown> = {};
  for (const id of turnOrder) {
    playersMeta[id] = {
      id,
      name: playersMap[id]?.name ?? id,
      handSize: 13,
      hasDropped: false,
    };
  }

  // Single atomic multi-path write via Admin SDK
  const updates: Record<string, unknown> = {
    [`rummy_games/${roomId}`]: {
      roomId,
      phase: "draw",
      currentTurn: turnOrder[0],
      turnOrder,
      wildJoker,
      openDeck: [firstOpen],
      closedDeck: deck,
      closedDeckCount: deck.length,
      players: playersMeta,
      scores: {},
      sessionScores: sessionScores ?? {},
      targetScore: targetScore ?? 0,
      round: round ?? 1,
      sessionOver: false,
      sessionWinnerId: null,
    },
    [`rummy_rooms/${roomId}/status`]: "started",
  };
  for (const id of turnOrder) {
    updates[`rummy_hands/${roomId}/${id}`] = hands[id];
  }

  await db.ref().update(updates);
  logger.info(`[Rummy] dealRummyGame: room=${roomId} players=${turnOrder.length} wild=${wildJoker.rank}`);
  return { success: true };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    const msg = e instanceof Error ? `${e.name}: ${e.message}` : String(e);
    logger.error("[Rummy] dealRummyGame unhandled:", msg);
    throw new HttpsError("internal", msg);
  }
});

// ── Cloud Function: declareRummyGame ──────────────────────────────────────────
//
// Validates the declaring player's submitted melds against their actual
// server-held hand (preventing fabricated cards) and computes authoritative
// deadwood scores for all other players.

export const declareRummyGame = onCall({ invoker: "public" }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const { roomId, melds } = request.data as {
    roomId?: string;
    melds?: RummyCard[][];
  };
  if (!roomId || !Array.isArray(melds)) {
    throw new HttpsError("invalid-argument", "roomId and melds are required");
  }

  const db = admin.database();
  const gameSnap = await db.ref(`rummy_games/${roomId}`).get();
  if (!gameSnap.exists()) throw new HttpsError("not-found", "Game not found");

  const game = gameSnap.val() as Record<string, unknown>;

  if (game.currentTurn !== uid) {
    throw new HttpsError("failed-precondition", "Not your turn");
  }
  if (game.phase !== "discard") {
    throw new HttpsError("failed-precondition", "Draw a card before declaring");
  }

  const wildRank = ((game.wildJoker as Record<string, unknown>).rank as number);
  const turnOrder = (game.turnOrder as string[]) ?? [];

  const handSnap = await db.ref(`rummy_hands/${roomId}/${uid}`).get();
  if (!handSnap.exists()) throw new HttpsError("not-found", "Hand not found");
  const actualHand = handSnap.val() as RummyCard[];

  // Verify declared cards exactly match actual hand
  const declared = melds.flat();
  if (declared.length !== actualHand.length) {
    await db.ref(`rummy_games/${roomId}/scores/${uid}`).set(80);
    return { error: "Declared card count does not match your hand" };
  }

  const cardKey = (c: RummyCard) =>
    `${c.isPrintedJoker ? 1 : 0}:${c.suit}:${c.rank}`;
  const sortedActual = [...actualHand].sort((a, b) =>
    cardKey(a).localeCompare(cardKey(b))
  );
  const sortedDeclared = [...declared].sort((a, b) =>
    cardKey(a).localeCompare(cardKey(b))
  );
  const cardsMatch = sortedActual.every(
    (c, i) =>
      c.rank === sortedDeclared[i]?.rank &&
      c.suit === sortedDeclared[i]?.suit &&
      c.isPrintedJoker === sortedDeclared[i]?.isPrintedJoker
  );
  if (!cardsMatch) {
    await db.ref(`rummy_games/${roomId}/scores/${uid}`).set(80);
    return { error: "Declared cards do not match your actual hand" };
  }

  const validationError = validateDeclaration(melds, wildRank);
  if (validationError) {
    // Wrong show: 80-point penalty. Eliminate player and continue the round.
    const wrongShowPenalty = 80;
    const existingSession = (game.sessionScores ?? {}) as Record<string, number>;
    const newSessionScores: Record<string, number> = { ...existingSession };
    newSessionScores[uid] = (newSessionScores[uid] ?? 0) + wrongShowPenalty;

    const turnOrderAfter = turnOrder.filter((id) => id !== uid);
    const wrongShowUpdates: Record<string, unknown> = {
      [`scores/${uid}`]: wrongShowPenalty,
      [`players/${uid}/hasDropped`]: true,
      turnOrder: turnOrderAfter,
      sessionScores: newSessionScores,
    };

    if (turnOrderAfter.length <= 1) {
      const winnerId = turnOrderAfter[0] ?? "";
      wrongShowUpdates.phase = "gameOver";
      wrongShowUpdates.winnerId = winnerId;
      wrongShowUpdates[`scores/${winnerId}`] = 0;
      // Check session completion
      const tgt = (game.targetScore as number | undefined) ?? 0;
      if (tgt > 0) {
        const allOver = Object.entries(newSessionScores)
          .filter(([id]) => id !== winnerId)
          .every(([, s]) => s >= tgt);
        if ((newSessionScores[winnerId] ?? 0) < tgt || allOver) {
          wrongShowUpdates.sessionOver = true;
          wrongShowUpdates.sessionWinnerId = winnerId;
        }
      }
    } else {
      const currentIdx = turnOrder.indexOf(uid);
      wrongShowUpdates.currentTurn = turnOrderAfter[currentIdx % turnOrderAfter.length];
      wrongShowUpdates.phase = "draw";
    }

    await db.ref(`rummy_games/${roomId}`).update(wrongShowUpdates);
    return { error: validationError, wrongShow: true };
  }

  // Read all other players' hands and compute deadwood
  const otherIds = turnOrder.filter((id) => id !== uid);

  const otherHandSnaps = await Promise.all(
    otherIds.map((id) => db.ref(`rummy_hands/${roomId}/${id}`).get())
  );

  const scores: Record<string, number> = { [uid]: 0 };
  for (let i = 0; i < otherIds.length; i++) {
    const snap = otherHandSnaps[i];
    if (!snap.exists()) continue;
    const hand = snap.val() as RummyCard[];
    scores[otherIds[i]] = Math.min(
      hand.reduce((sum, c) => sum + cardPoints(c), 0),
      80
    );
  }

  // Accumulate session scores
  const tgt = (game.targetScore as number | undefined) ?? 0;
  const existingSession = (game.sessionScores ?? {}) as Record<string, number>;
  const sessionScores: Record<string, number> = { ...existingSession };
  for (const [pid, pts] of Object.entries(scores)) {
    sessionScores[pid] = (sessionScores[pid] ?? 0) + pts;
  }

  let sessionOver = false;
  let sessionWinnerId: string | null = null;
  if (tgt > 0) {
    const remaining = turnOrder.filter((id) => (sessionScores[id] ?? 0) < tgt);
    if (remaining.length <= 1) {
      sessionOver = true;
      sessionWinnerId = remaining.length === 1
        ? remaining[0]
        : turnOrder.reduce((best, id) =>
            (sessionScores[id] ?? 0) < (sessionScores[best] ?? 0) ? id : best
          );
    }
  }

  await db.ref(`rummy_games/${roomId}`).update({
    phase: "gameOver",
    winnerId: uid,
    scores,
    sessionScores,
    sessionOver: sessionOver || null,
    sessionWinnerId: sessionWinnerId || null,
  });

  logger.info(`[Rummy] declareRummyGame: ${uid} won round ${game.round ?? 1} in ${roomId} — scores: ${JSON.stringify(scores)} session: ${JSON.stringify(sessionScores)}`);
  return { error: null };
});

const RETENTION_DAYS = 7;
const QUEUE_STALE_HOURS = 24;

// Firebase push key character set — first 8 chars encode creation timestamp (big-endian base-64).
const PUSH_CHARS = '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';

function pushKeyToMs(key: string): number {
  let ts = 0;
  for (let i = 0; i < 8; i++) {
    const idx = PUSH_CHARS.indexOf(key[i] ?? '');
    if (idx === -1) return 0;
    ts = ts * 64 + idx;
  }
  return ts;
}

// Deletes all top-level entries in `path` whose key is a push ID older than cutoff.
async function purgeByPushKey(
  db: admin.database.Database,
  path: string,
  cutoff: number
): Promise<number> {
  const snap = await db.ref(path).get();
  if (!snap.exists()) return 0;
  const keys = Object.keys(snap.val() as Record<string, unknown>);
  let n = 0;
  await Promise.all(keys.map(async (key) => {
    const ts = pushKeyToMs(key);
    if (ts > 0 && ts < cutoff) {
      await db.ref(`${path}/${key}`).remove();
      n++;
    }
  }));
  return n;
}

/**
 * Runs daily at 02:00 UTC and purges all transactional data older than
 * RETENTION_DAYS (7 days). Covers: gamelogs, game28_rooms, game28_secrets,
 * game28_codes, kazhutha rooms, roomCodes, rummy_rooms/games/hands,
 * and stale matchmaking queue entries.
 */
export const cleanOldGameLogs = onSchedule("every day 02:00", async () => {
  const db = admin.database();
  const cutoff = Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000;
  const s: Record<string, number> = {};

  // ── 1. gamelogs (session-keyed paths; use last event ts) ─────────────────
  const logsSnap = await db.ref("gamelogs").get();
  if (logsSnap.exists()) {
    const logEntries = logsSnap.val() as Record<string, unknown>;
    await Promise.all(Object.keys(logEntries).map(async (key) => {
      const latestSnap = await db
        .ref(`gamelogs/${key}/events`)
        .orderByChild("ts")
        .limitToLast(1)
        .get();
      if (!latestSnap.exists()) {
        await db.ref(`gamelogs/${key}`).remove();
        s.gamelogs = (s.gamelogs ?? 0) + 1;
        return;
      }
      let latestTs = 0;
      latestSnap.forEach((c) => {
        const ts = c.val()?.ts as number | undefined;
        if (ts && ts > latestTs) latestTs = ts;
      });
      if (latestTs < cutoff) {
        await db.ref(`gamelogs/${key}`).remove();
        s.gamelogs = (s.gamelogs ?? 0) + 1;
      }
    }));
  }

  // ── 2. game28_rooms (push key timestamp) ─────────────────────────────────
  s.game28_rooms = await purgeByPushKey(db, "game28_rooms", cutoff);

  // ── 3. game28_secrets orphan cleanup ─────────────────────────────────────
  const secretsSnap = await db.ref("game28_secrets").get();
  if (secretsSnap.exists()) {
    const secretRooms = secretsSnap.val() as Record<string, unknown>;
    await Promise.all(Object.keys(secretRooms).map(async (roomId) => {
      const exists = (await db.ref(`game28_rooms/${roomId}`).get()).exists();
      if (!exists) {
        await db.ref(`game28_secrets/${roomId}`).remove();
        s.game28_secrets = (s.game28_secrets ?? 0) + 1;
      }
    }));
  }

  // ── 4. game28_codes orphan cleanup ───────────────────────────────────────
  const g28CodesSnap = await db.ref("game28_codes").get();
  if (g28CodesSnap.exists()) {
    const codes = g28CodesSnap.val() as Record<string, string>;
    await Promise.all(Object.entries(codes).map(async ([code, roomId]) => {
      const exists = (await db.ref(`game28_rooms/${roomId}`).get()).exists();
      if (!exists) {
        await db.ref(`game28_codes/${code}`).remove();
        s.game28_codes = (s.game28_codes ?? 0) + 1;
      }
    }));
  }

  // ── 5. kazhutha rooms (push key timestamp) ───────────────────────────────
  s.kazhutha_rooms = await purgeByPushKey(db, "rooms", cutoff);

  // ── 6. roomCodes orphan cleanup ──────────────────────────────────────────
  const roomCodesSnap = await db.ref("roomCodes").get();
  if (roomCodesSnap.exists()) {
    const roomCodes = roomCodesSnap.val() as Record<string, string>;
    await Promise.all(Object.entries(roomCodes).map(async ([code, roomId]) => {
      const exists = (await db.ref(`rooms/${roomId}`).get()).exists();
      if (!exists) {
        await db.ref(`roomCodes/${code}`).remove();
        s.roomcodes = (s.roomcodes ?? 0) + 1;
      }
    }));
  }

  // ── 7. rummy_rooms / rummy_games / rummy_hands (push key timestamp) ──────
  s.rummy_rooms = await purgeByPushKey(db, "rummy_rooms", cutoff);
  s.rummy_games = await purgeByPushKey(db, "rummy_games", cutoff);
  s.rummy_hands = await purgeByPushKey(db, "rummy_hands", cutoff);

  // ── 8. matchmaking queue — stale entries older than QUEUE_STALE_HOURS ────
  const queueCutoff = Date.now() - QUEUE_STALE_HOURS * 60 * 60 * 1000;
  const queueSnap = await db.ref("matchmaking/queue").get();
  if (queueSnap.exists()) {
    const queue = queueSnap.val() as Record<string, { joinedAt?: number }>;
    await Promise.all(Object.entries(queue).map(async ([uid, entry]) => {
      if ((entry.joinedAt ?? 0) < queueCutoff) {
        await db.ref(`matchmaking/queue/${uid}`).remove();
        s.matchmaking_queue = (s.matchmaking_queue ?? 0) + 1;
      }
    }));
  }

  logger.info(`cleanOldGameLogs: ${JSON.stringify(s)}`);
});
