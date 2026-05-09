#!/bin/bash
# Full wipe of all transactional RTDB data.
# Leaves: stats (player scores/rankings), schema, Firebase Auth.
# Usage: ./purge.sh [--yes]

PROJECT="asinux-89da0"

if [[ "$1" != "--yes" ]]; then
  echo ""
  echo "  This will DELETE ALL transactional data:"
  echo "    error_logs · feedback · gamelogs"
  echo "    rummy / tambola / wildcard / teen_patti / game28 / kazhutha rooms+games+hands"
  echo "    matchmaking queue"
  echo ""
  echo "  Stats (player scores) are NOT touched."
  echo ""
  read -p "  Type YES to continue: " confirm
  [[ "$confirm" == "YES" ]] || { echo "Aborted."; exit 1; }
fi

remove() {
  local data
  data=$(firebase database:get "/$1" --project "$PROJECT" --shallow 2>/dev/null)
  if [[ "$data" == "null" || -z "$data" ]]; then
    echo "  /$1 — empty, skipped"
  else
    firebase database:remove "/$1" --project "$PROJECT" -f >/dev/null 2>&1
    echo "  /$1 — removed"
  fi
}

echo ""
remove error_logs
remove feedback
remove gamelogs

remove rummy_rooms
remove rummy_games
remove rummy_hands

remove tambola_rooms
remove tambola_games
remove tambola_tickets

remove wildcard_rooms
remove wildcard_games
remove wildcard_hands

remove teen_patti_rooms
remove teen_patti_secrets
remove teen_patti_codes

remove game28_rooms
remove game28_secrets
remove game28_codes

remove rooms
remove roomCodes
remove matchmaking

echo ""
echo "Done. All transactional data cleared."
