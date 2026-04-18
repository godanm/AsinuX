import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

admin.initializeApp();

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
  const ranks = naturals.map((c) => c.rank).sort((a, b) => a - b);

  for (let i = 1; i < ranks.length; i++) {
    if (ranks[i] === ranks[i - 1]) return false;
  }

  let gapsNeeded = 0;
  for (let i = 1; i < ranks.length; i++) {
    gapsNeeded += ranks[i] - ranks[i - 1] - 1;
  }
  return gapsNeeded <= jokerCount;
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

export const dealRummyGame = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const { roomId } = request.data as { roomId?: string };
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
  if (room.status !== "ready") {
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
      // No 'hands' key — each hand lives at rummy_hands/{roomId}/{playerId}
    },
    [`rummy_rooms/${roomId}/status`]: "started",
  };
  for (const id of turnOrder) {
    updates[`rummy_hands/${roomId}/${id}`] = hands[id];
  }

  await db.ref().update(updates);
  logger.info(`[Rummy] dealRummyGame: room=${roomId} players=${turnOrder.length} wild=${wildJoker.rank}`);
  return { success: true };
});

// ── Cloud Function: declareRummyGame ──────────────────────────────────────────
//
// Validates the declaring player's submitted melds against their actual
// server-held hand (preventing fabricated cards) and computes authoritative
// deadwood scores for all other players.

export const declareRummyGame = onCall(async (request) => {
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
    await db.ref(`rummy_games/${roomId}/scores/${uid}`).set(80);
    return { error: validationError };
  }

  // Read all other players' hands and compute deadwood
  const turnOrder = (game.turnOrder as string[]) ?? [];
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

  await db.ref(`rummy_games/${roomId}`).update({
    phase: "gameOver",
    winnerId: uid,
    scores,
  });

  logger.info(`[Rummy] declareRummyGame: ${uid} won in ${roomId} — scores: ${JSON.stringify(scores)}`);
  return { error: null };
});

const RETENTION_DAYS = 7;

/**
 * Runs daily at 02:00 UTC and deletes any gamelogs room whose most recent
 * event is older than RETENTION_DAYS days.
 *
 * Structure: gamelogs/{roomId}/events/{pushId} → { ts: <epoch ms>, ... }
 */
export const cleanOldGameLogs = onSchedule("every day 02:00", async () => {
  const db = admin.database();
  const cutoff = Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000;

  const snapshot = await db.ref("gamelogs").get();
  if (!snapshot.exists()) {
    logger.info("cleanOldGameLogs: no gamelogs found, nothing to do");
    return;
  }

  const rooms = snapshot.val() as Record<string, unknown>;
  const roomIds = Object.keys(rooms);
  logger.info(`cleanOldGameLogs: checking ${roomIds.length} rooms`);

  let deleted = 0;
  let kept = 0;

  await Promise.all(
    roomIds.map(async (roomId) => {
      // Find the most recent event timestamp for this room
      const latestSnap = await db
        .ref(`gamelogs/${roomId}/events`)
        .orderByChild("ts")
        .limitToLast(1)
        .get();

      if (!latestSnap.exists()) {
        // No events at all — delete the empty room entry
        await db.ref(`gamelogs/${roomId}`).remove();
        deleted++;
        return;
      }

      let latestTs = 0;
      latestSnap.forEach((child) => {
        const ts = child.val()?.ts as number | undefined;
        if (ts && ts > latestTs) latestTs = ts;
      });

      if (latestTs < cutoff) {
        await db.ref(`gamelogs/${roomId}`).remove();
        logger.info(`cleanOldGameLogs: deleted room ${roomId} (last event ${new Date(latestTs).toISOString()})`);
        deleted++;
      } else {
        kept++;
      }
    })
  );

  logger.info(`cleanOldGameLogs: done — deleted ${deleted}, kept ${kept}`);
});
