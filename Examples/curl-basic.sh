#!/usr/bin/env bash
# curl-basic.sh
#
# Minimal example demonstrating Board API usage with curl.
# Requires: curl, jq, bash, and a valid API token with boards:read + boards:write.
#
# Usage:
#   export JKB_TOKEN="jkb_your_token_here"
#   export BOARD_ID="your-board-id"
#   ./curl-basic.sh
#
# The script:
#   1. Fetches /me to verify the token
#   2. Lists your boards
#   3. Fetches the target board (to obtain current revision)
#   4. Creates a new list called "API Test Lane"
#   5. Creates a card in that list
#   6. Adds a comment to the card
#
set -euo pipefail

: "${JKB_TOKEN:?Set JKB_TOKEN environment variable to your jkb_... token}"
: "${BOARD_ID:?Set BOARD_ID to the board you want to modify}"

BASE="https://api.jokelboard.com/api/v1"
AUTH_HEADER="Authorization: Bearer ${JKB_TOKEN}"

# Helper: fetch the board's current revision. Sending it with each write
# lets the server reject the request (409) if someone else changed the
# board in between, instead of silently overwriting their change.
current_revision() {
  curl -sS -H "$AUTH_HEADER" "$BASE/boards/${BOARD_ID}/revision" | jq -r '.revision'
}

echo "== 1. Verify token and identity =="
curl -sS -H "$AUTH_HEADER" "$BASE/me" | jq .

echo
echo "== 2. List accessible boards =="
curl -sS -H "$AUTH_HEADER" "$BASE/boards" | jq .

echo
echo "== 3. Fetch target board (to get revision) =="
BOARD_JSON=$(curl -sS -H "$AUTH_HEADER" "$BASE/boards/${BOARD_ID}")
echo "$BOARD_JSON" | jq '.board | {id, name, revision, listCount: (.data.lists | length)}'

REVISION=$(echo "$BOARD_JSON" | jq -r '.board.revision')
echo "Current revision: $REVISION"

echo
echo "== 4. Create a new list =="
LIST_RESP=$(curl -sS -X POST -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d "{\"title\": \"API Test Lane\", \"revision\": ${REVISION}}" \
  "$BASE/boards/${BOARD_ID}/lists")
echo "$LIST_RESP" | jq '{ok, list: .list}'

LIST_ID=$(echo "$LIST_RESP" | jq -r '.list.id')
echo "Created list ID: $LIST_ID"

echo
echo "== 5. Create a card in the new list =="
REVISION=$(current_revision)  # the list creation bumped the revision
CARD_RESP=$(curl -sS -X POST -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d "{
    \"listId\": \"${LIST_ID}\",
    \"title\": \"Investigate API example script\",
    \"categoryId\": \"P2\",
    \"description\": \"This card was created by curl-basic.sh\",
    \"descriptionMode\": \"markdown\",
    \"labels\": [{\"name\": \"automation\", \"color\": \"#5e9cff\"}],
    \"dateType\": \"static\",
    \"due\": {\"iso\": \"2026-07-15T17:00:00Z\"},
    \"revision\": ${REVISION}
  }" \
  "$BASE/boards/${BOARD_ID}/cards")
echo "$CARD_RESP" | jq '{ok, card: .card}'

CARD_ID=$(echo "$CARD_RESP" | jq -r '.card.id')

echo
echo "== 6. Add a comment mentioning a teammate =="
REVISION=$(current_revision)
curl -sS -X POST -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d "{\"text\": \"Hey @alice, the curl example just created this card. Ready for review?\", \"revision\": ${REVISION}}" \
  "$BASE/boards/${BOARD_ID}/cards/${CARD_ID}/comments" | jq .

echo
echo "✅ Done. Open the board in the Jokelboard UI to see the new list + card + comment."
echo "   (Mentions only create in-app notifications on organisation boards.)"
