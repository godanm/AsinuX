#!/bin/bash
# Count games played per game type per day from gamelogs session keys.
# Usage: ./game_stats.sh [YYYY-MM-DD]
#   No date arg → shows all days
#   With date   → shows only that day (e.g. ./game_stats.sh 2026-05-11)

PROJECT="asinux-89da0"
FILTER_DATE="${1:-}"

echo ""
echo "  Fetching gamelogs from RTDB..."
RAW=$(firebase database:get /gamelogs --project "$PROJECT" --shallow 2>/dev/null)

if [[ "$RAW" == "null" || -z "$RAW" ]]; then
  echo "  No gamelogs found."
  echo ""
  exit 0
fi

python3 << EOF
import json, re
from collections import defaultdict

filter_date = "$FILTER_DATE"
raw = '''$RAW'''

try:
    data = json.loads(raw)
except Exception as e:
    print(f"  Failed to parse response: {e}")
    exit(1)

keys = data.keys() if isinstance(data, dict) else []
counts = defaultdict(int)

for key in keys:
    date_match = re.search(r'started-(\d{4}-\d{2}-\d{2})', key)
    game_match = re.search(r'-game-([a-z0-9_]+)$', key)
    if not date_match or not game_match:
        continue
    date = date_match.group(1)
    game = game_match.group(1)
    if filter_date and date != filter_date:
        continue
    counts[(date, game)] += 1

if not counts:
    msg = f" for {filter_date}" if filter_date else ""
    print(f"  No sessions found{msg}.")
    print()
    exit(0)

print()
print(f"  {'Date':<12}  {'Game':<20}  {'Sessions':>8}")
print(f"  {'-'*12}  {'-'*20}  {'-'*8}")
for (date, game) in sorted(counts.keys()):
    print(f"  {date:<12}  {game:<20}  {counts[(date, game)]:>8}")
print()
EOF
