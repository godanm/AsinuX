"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.cleanOldGameLogs = void 0;
const admin = require("firebase-admin");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const firebase_functions_1 = require("firebase-functions");
admin.initializeApp();
const RETENTION_DAYS = 7;
/**
 * Runs daily at 02:00 UTC and deletes any gamelogs room whose most recent
 * event is older than RETENTION_DAYS days.
 *
 * Structure: gamelogs/{roomId}/events/{pushId} → { ts: <epoch ms>, ... }
 */
exports.cleanOldGameLogs = (0, scheduler_1.onSchedule)("every day 02:00", async () => {
    const db = admin.database();
    const cutoff = Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000;
    const snapshot = await db.ref("gamelogs").get();
    if (!snapshot.exists()) {
        firebase_functions_1.logger.info("cleanOldGameLogs: no gamelogs found, nothing to do");
        return;
    }
    const rooms = snapshot.val();
    const roomIds = Object.keys(rooms);
    firebase_functions_1.logger.info(`cleanOldGameLogs: checking ${roomIds.length} rooms`);
    let deleted = 0;
    let kept = 0;
    await Promise.all(roomIds.map(async (roomId) => {
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
            var _a;
            const ts = (_a = child.val()) === null || _a === void 0 ? void 0 : _a.ts;
            if (ts && ts > latestTs)
                latestTs = ts;
        });
        if (latestTs < cutoff) {
            await db.ref(`gamelogs/${roomId}`).remove();
            firebase_functions_1.logger.info(`cleanOldGameLogs: deleted room ${roomId} (last event ${new Date(latestTs).toISOString()})`);
            deleted++;
        }
        else {
            kept++;
        }
    }));
    firebase_functions_1.logger.info(`cleanOldGameLogs: done — deleted ${deleted}, kept ${kept}`);
});
//# sourceMappingURL=index.js.map