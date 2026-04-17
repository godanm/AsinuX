import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";

admin.initializeApp();

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
