#!/usr/bin/env bash
# plugin-checklist.sh
#
# Board Plugin API example: read checklist structure and toggle an item.
# Requires: curl, jq, bash, and an API token with the plugin:checklist
# scope (a boards:write programmatic key also works).
#
# Note: organisation-owned keys cannot use the Plugin API — use a board
# or profile key.
#
# Usage:
#   export JKB_TOKEN="jkb_your_token_here"
#   export BOARD_ID="your-board-id"
#   ./plugin-checklist.sh
#
# The script:
#   1. Probes /plugin/access-level to confirm the token can use the Plugin API
#   2. Fetches the reduced plugin board shape (lists, cards, checklists only)
#   3. Prints every checklist as a tick-box summary
#   4. Toggles the first unchecked checklist item it finds
#
set -euo pipefail

: "${JKB_TOKEN:?Set JKB_TOKEN environment variable to your jkb_... token}"
: "${BOARD_ID:?Set BOARD_ID to the board you want to read}"

BASE="https://api.jokelboard.com/api/v1"
AUTH_HEADER="Authorization: Bearer ${JKB_TOKEN}"

echo "== 1. Probe plugin access level =="
curl -sS -H "$AUTH_HEADER" "$BASE/plugin/access-level" | jq .

echo
echo "== 2. Fetch plugin board shape =="
BOARD_JSON=$(curl -sS -H "$AUTH_HEADER" "$BASE/plugin/boards/${BOARD_ID}")
echo "$BOARD_JSON" | jq '{
  name: .board.name,
  lists: [.board.lists[] | {id, title, cards: (.cards | length)}]
}'

echo
echo "== 3. Checklist summary =="
echo "$BOARD_JSON" | jq -r '
  .board.lists[].cards[]
  | select((.checklist.items // []) | length > 0)
  | .title as $card
  | "\($card):",
    ((.checklist.items[]) | "  [\(if .done then "x" else " " end)] \(.text)")
'

echo
echo "== 4. Toggle the first unchecked item =="
NEXT=$(echo "$BOARD_JSON" | jq -r '
  [.board.lists[].cards[] as $c
   | ($c.checklist.items // [])[]
   | select((.done | not) and .id)
   | {card: $c.id, item: .id}]
  | first
  | if . then "\(.card) \(.item)" else empty end
')

if [ -z "$NEXT" ]; then
  echo "No unchecked checklist items found — nothing to toggle."
  exit 0
fi

CARD_ID=${NEXT% *}
ITEM_ID=${NEXT#* }
echo "Toggling item ${ITEM_ID} on card ${CARD_ID}..."

curl -sS -X POST -H "$AUTH_HEADER" \
  "$BASE/plugin/boards/${BOARD_ID}/cards/${CARD_ID}/checklist-items/${ITEM_ID}/toggle" | jq .

echo
echo "✅ Done. On organisation boards this toggle is recorded in the audit log."
