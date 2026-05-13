#!/bin/bash
# Purge RTDB entries older than HOURS_OLD hours.
# Leaves: stats (player scores/rankings), Firebase Auth, anything still active.
# Usage: ./purge.sh [--yes]

PROJECT="asinux-89da0"
HOURS_OLD=24

if [[ "$1" != "--yes" ]]; then
  echo ""
  echo "  This will DELETE transactional entries older than ${HOURS_OLD}h:"
  echo "    error_logs · feedback · gamelogs"
  echo "    rummy / tambola / wildcard / teen_patti / game28 / kazhutha rooms+games+hands"
  echo "    matchmaking queue · room code lookups"
  echo ""
  echo "  Stats (player scores) are NOT touched."
  echo "  Active rooms (created within ${HOURS_OLD}h) are NOT touched."
  echo ""
  read -p "  Type YES to continue: " confirm
  [[ "$confirm" == "YES" ]] || { echo "Aborted."; exit 1; }
fi

echo ""
echo "  Purging entries older than ${HOURS_OLD}h..."
echo ""

python3 << PYEOF
import json, re, subprocess, sys
from datetime import datetime, timezone

HOURS_OLD = $HOURS_OLD
PROJECT = "$PROJECT"

# Firebase push key character set (64 chars, index = value)
PUSH_CHARS = '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz'

now_ms = datetime.now(timezone.utc).timestamp() * 1000
cutoff_ms = now_ms - HOURS_OLD * 3600 * 1000

def push_key_to_ms(key):
    try:
        ms = 0
        for ch in key[:8]:
            ms = ms * 64 + PUSH_CHARS.index(ch)
        return ms
    except (ValueError, IndexError):
        return None

def is_old_push_key(key):
    ms = push_key_to_ms(key)
    return ms is not None and ms < cutoff_ms

def get_shallow(path):
    result = subprocess.run(
        ['firebase', 'database:get', f'/{path}', '--project', PROJECT, '--shallow'],
        capture_output=True, text=True
    )
    raw = result.stdout.strip()
    if not raw or raw == 'null':
        return {}
    try:
        data = json.loads(raw)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}

def get_full(path):
    result = subprocess.run(
        ['firebase', 'database:get', f'/{path}', '--project', PROJECT],
        capture_output=True, text=True
    )
    raw = result.stdout.strip()
    if not raw or raw == 'null':
        return None
    try:
        return json.loads(raw)
    except Exception:
        return None

def delete(path):
    subprocess.run(
        ['firebase', 'database:remove', f'/{path}', '--project', PROJECT, '-f'],
        capture_output=True
    )
    print(f'    deleted /{path}')

total_deleted = 0

def purge_by_push_key(node):
    global total_deleted
    keys = list(get_shallow(node).keys())
    old = [k for k in keys if is_old_push_key(k)]
    if not old:
        print(f'  /{node} — nothing old ({len(keys)} entries)')
        return
    print(f'  /{node} — deleting {len(old)} of {len(keys)}')
    for k in old:
        delete(f'{node}/{k}')
    total_deleted += len(old)

def purge_code_lookup(node):
    global total_deleted
    # Values are push-key room IDs; delete entries whose room is old enough
    data = get_full(node)
    if not data or not isinstance(data, dict):
        print(f'  /{node} — empty')
        return
    old = [code for code, room_id in data.items()
           if isinstance(room_id, str) and is_old_push_key(room_id)]
    if not old:
        print(f'  /{node} — nothing old ({len(data)} entries)')
        return
    print(f'  /{node} — deleting {len(old)} of {len(data)}')
    for code in old:
        delete(f'{node}/{code}')
    total_deleted += len(old)

def purge_gamelogs():
    global total_deleted
    keys = list(get_shallow('gamelogs').keys())
    old = []
    for key in keys:
        m = re.search(r'started-(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})Z', key)
        if not m:
            continue
        try:
            dt = datetime.strptime(m.group(1), '%Y-%m-%dT%H:%M:%S').replace(tzinfo=timezone.utc)
            if dt.timestamp() * 1000 < cutoff_ms:
                old.append(key)
        except Exception:
            pass
    if not old:
        print(f'  /gamelogs — nothing old ({len(keys)} entries)')
        return
    print(f'  /gamelogs — deleting {len(old)} of {len(keys)}')
    for k in old:
        delete(f'gamelogs/{k}')
    total_deleted += len(old)

def purge_error_logs():
    global total_deleted
    uids = list(get_shallow('error_logs').keys())
    if not uids:
        print('  /error_logs — empty')
        return
    n_deleted = 0
    n_total = 0
    for uid in uids:
        entries = list(get_shallow(f'error_logs/{uid}').keys())
        n_total += len(entries)
        old = [e for e in entries if is_old_push_key(e)]
        for e in old:
            delete(f'error_logs/{uid}/{e}')
            n_deleted += 1
    print(f'  /error_logs — deleted {n_deleted} of {n_total} entries across {len(uids)} users')
    total_deleted += n_deleted

def purge_matchmaking():
    global total_deleted
    # Queue keys are UIDs (not push keys), but matchmaking entries are seconds-lived.
    # Anything still here after 8h is abandoned.
    queue = get_shallow('matchmaking/queue')
    if not queue:
        print('  /matchmaking/queue — empty')
        return
    print(f'  /matchmaking/queue — wiping {len(queue)} stale entries')
    delete('matchmaking/queue')
    total_deleted += len(queue)

# ── Push-key keyed game nodes ──────────────────────────────────────────────
for node in [
    'rummy_rooms', 'rummy_games', 'rummy_hands',
    'tambola_rooms', 'tambola_games', 'tambola_tickets',
    'wildcard_rooms', 'wildcard_games', 'wildcard_hands',
    'teen_patti_rooms', 'teen_patti_secrets',
    'game28_rooms', 'game28_secrets',
    'rooms',
    'feedback',
]:
    purge_by_push_key(node)

# ── Code lookups (value = push-key room ID) ────────────────────────────────
for node in ['roomCodes', 'teen_patti_codes', 'game28_codes']:
    purge_code_lookup(node)

# ── Gamelogs (datetime embedded in session key name) ──────────────────────
purge_gamelogs()

# ── Error logs (UID → push-key entries) ───────────────────────────────────
purge_error_logs()

# ── Matchmaking queue (UID-keyed, always ephemeral) ───────────────────────
purge_matchmaking()

print()
print(f'  Total deleted: {total_deleted} entries.')
PYEOF

echo ""
echo "Done."
