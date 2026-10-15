#!/usr/bin/env bash
# sandbox-smoke.sh
#
# A keyless tour of the Sandbox API: the same routes as /api/v1, on fake data.
# Requires: curl, jq, bash. No account, paid plan, or API key needed.
#
# Usage:
#   ./sandbox-smoke.sh
#   JKB_BASE_URL=http://localhost:3000/api/sandbox/v1 ./sandbox-smoke.sh   # a local server
#
# The script:
#   1. Reads the sandbox manifest (personas and scenarios)
#   2. Verifies the sandbox token and reads the board
#   3. Creates a list, a card, a comment and a move, chaining the revision each reply returns
#   4. Shows that nothing was stored (the next read is the untouched fixture)
#   5. Shows a title the real API also rejects (a Discord-style mention)
#   6. Forces a 409, a 429, a plain-text 500 and an HTML 502 with X-Sandbox-Scenario
#
set -euo pipefail

BASE="${JKB_BASE_URL:-https://api.jokelboard.com/api/sandbox/v1}"
BOARD="sbx-personal"
AUTH=(-H "Authorization: Bearer jkb_sandbox_full")   # a public sandbox token, not a secret
JSON=(-H "Content-Type: application/json")

BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT

section() { printf '\n== %s ==\n' "$1"; }

section "1. The manifest (no token needed)"
curl -sS "$BASE" | jq '{sandbox, tokens: [.tokens[].token], scenarios: [.scenarios[].name]}'

section "2. Verify the token, then read the board"
curl -sS "${AUTH[@]}" "$BASE/me" | jq '{user: .user.username, tier: .user.tier, scopes: .token.scopes}'
BOARD_JSON=$(curl -sS "${AUTH[@]}" "$BASE/boards/$BOARD")
REVISION=$(jq -r '.board.revision' <<<"$BOARD_JSON")
jq '.board | {id, revision, lists: [.data.lists[] | {id, cards: (.cards | length)}]}' <<<"$BOARD_JSON"

section "3. Write, chaining the revision each reply returns"
# A real board's revision changes on every write; the sandbox answers with the one you sent plus one.
LIST_JSON=$(curl -sS -X POST "${AUTH[@]}" "${JSON[@]}" \
  -d "{\"title\": \"Sandbox lane\", \"revision\": $REVISION}" "$BASE/boards/$BOARD/lists")
LIST_ID=$(jq -r '.list.id' <<<"$LIST_JSON")
REVISION=$(jq -r '.board.revision' <<<"$LIST_JSON")
echo "list $LIST_ID, revision now $REVISION"

CARD_JSON=$(curl -sS -X POST "${AUTH[@]}" "${JSON[@]}" \
  -d "{\"listId\": \"$LIST_ID\", \"title\": \"Hello from my bot\", \"revision\": $REVISION}" \
  "$BASE/boards/$BOARD/cards")
CARD_ID=$(jq -r '.card.id' <<<"$CARD_JSON")
REVISION=$(jq -r '.board.revision' <<<"$CARD_JSON")
echo "card $CARD_ID, revision now $REVISION"

# Ids the sandbox issued resolve in later calls, so create -> comment -> move works.
COMMENT_JSON=$(curl -sS -X POST "${AUTH[@]}" "${JSON[@]}" \
  -d "{\"text\": \"Created by sandbox-smoke.sh\", \"revision\": $REVISION}" \
  "$BASE/boards/$BOARD/cards/$CARD_ID/comments")
REVISION=$(jq -r '.board.revision' <<<"$COMMENT_JSON")
jq '{author: .comment.author}' <<<"$COMMENT_JSON"

curl -sS -X POST "${AUTH[@]}" "${JSON[@]}" \
  -d "{\"toListId\": \"sbx-list-done\", \"revision\": $REVISION}" \
  "$BASE/boards/$BOARD/cards/$CARD_ID/move" | jq '{listId, position}'

section "4. Nothing was stored"
curl -sS "${AUTH[@]}" "$BASE/boards/$BOARD" \
  | jq '.board | {revision, lists: (.data.lists | length)}'

section "5. A title the real API rejects too (angle brackets)"
curl -sS -X POST "${AUTH[@]}" "${JSON[@]}" \
  -d '{"listId": "sbx-list-done", "title": "Ping <@123456>"}' \
  "$BASE/boards/$BOARD/cards" | jq .

section "6. Forced failures (X-Sandbox-Scenario)"
force() { curl -sS -o "$BODY_FILE" -D - "${AUTH[@]}" -H "X-Sandbox-Scenario: $1" "$BASE/me"; }

echo "-- revision_conflict"
curl -sS "${AUTH[@]}" -H "X-Sandbox-Scenario: revision_conflict" "$BASE/me" | jq '{error, currentRevision}'

echo "-- rate_limited"
force rate_limited | tr -d '\r' | grep -i -E '^(HTTP/|retry-after|ratelimit-remaining)'

echo "-- server_error (plain text, not JSON)"
force server_error | tr -d '\r' | grep -i -E '^(HTTP/|content-type)'
cat "$BODY_FILE"; echo

echo "-- bad_gateway (HTML, not JSON)"
force bad_gateway | tr -d '\r' | grep -i -E '^(HTTP/|content-type)'

echo
echo "Done. Swap BASE for https://api.jokelboard.com/api/v1 and the token for a real key to go live."
