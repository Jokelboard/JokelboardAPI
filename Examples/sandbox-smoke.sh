#!/usr/bin/env bash
# sandbox-smoke.sh
#
# A tour of the Sandbox API: the same routes as /api/v1, on fake data.
# Requires: curl, jq, bash, and a free sandbox key (any plan): User Settings ->
# Security -> API Keys, type "Sandbox API".
#
# Usage:
#   JKB_SANDBOX_KEY=jkb_sbx_... ./sandbox-smoke.sh
#   JKB_SANDBOX_KEY=jkb_sbx_... JKB_BASE_URL=http://localhost:3000/api/sandbox/v1 ./sandbox-smoke.sh   # a local server
#
# The script:
#   1. Reads the sandbox manifest (personas and scenarios)
#   2. Verifies the sandbox key and reads the board
#   3. Creates a list, a card, a comment and a move, chaining the revision each reply returns
#   4. Shows that nothing was stored (the next read is the untouched fixture)
#   5. Shows a title the real API also rejects (a Discord-style mention)
#   6. Acts as a read-only key with X-Sandbox-Persona (writes get 403)
#   7. Forces a 409, a 429, a plain-text 500 and an HTML 502 with X-Sandbox-Scenario
#
# It stops with a non-zero exit at the first call that does not behave as described,
# so a green run really did all of the above.
set -euo pipefail

BASE="${JKB_BASE_URL:-https://api.jokelboard.com/api/sandbox/v1}"
# A fixed sandbox board. Production board and list ids are different, see the last line.
BOARD="sbx-personal"
: "${JKB_SANDBOX_KEY:?Set JKB_SANDBOX_KEY to a sandbox key (User Settings -> Security -> API Keys, type Sandbox API)}"
AUTH=(-H "Authorization: Bearer $JKB_SANDBOX_KEY")   # your sandbox key: keep it out of git
JSON=(-H "Content-Type: application/json")

BODY_FILE=$(mktemp)
HEAD_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE" "$HEAD_FILE"' EXIT

section() { printf '\n== %s ==\n' "$1"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

# A call that must succeed. `curl -f` turns an HTTP error into a failure, so a
# rejected key never reaches jq as a harmless-looking error body.
ok() { curl -fsS "$@"; }

# expect STATUS curl-args...: a call that must come back with exactly STATUS.
# The body is left in $BODY_FILE and the response headers in $HEAD_FILE.
expect() {
  local want="$1" got
  shift
  got=$(curl -sS -o "$BODY_FILE" -D "$HEAD_FILE" -w '%{http_code}' "$@")
  [ "$got" = "$want" ] || fail "expected HTTP $want, got $got for: $*"
}

section "1. The manifest (no key needed)"
ok "$BASE" | jq '{sandbox, personas: [.personas[].name], scenarios: [.scenarios[].name], perAccount: .keys.perAccount}'

section "2. Verify the key, then read the board"
ok "${AUTH[@]}" "$BASE/me" | jq '{user: .user.username, tier: .user.tier, scopes: .token.scopes}'
BOARD_JSON=$(ok "${AUTH[@]}" "$BASE/boards/$BOARD")
REVISION=$(jq -er '.board.revision' <<<"$BOARD_JSON")
jq '.board | {id, revision, lists: [.data.lists[] | {id, cards: (.cards | length)}]}' <<<"$BOARD_JSON"

section "3. Write, chaining the revision each reply returns"
# A real board's revision changes on every write; the sandbox answers with the one you sent plus one.
LIST_JSON=$(ok -X POST "${AUTH[@]}" "${JSON[@]}" \
  -d "{\"title\": \"Sandbox lane\", \"revision\": $REVISION}" "$BASE/boards/$BOARD/lists")
LIST_ID=$(jq -er '.list.id' <<<"$LIST_JSON")
REVISION=$(jq -er '.board.revision' <<<"$LIST_JSON")
echo "list $LIST_ID, revision now $REVISION"

CARD_JSON=$(ok -X POST "${AUTH[@]}" "${JSON[@]}" \
  -d "{\"listId\": \"$LIST_ID\", \"title\": \"Hello from my bot\", \"revision\": $REVISION}" \
  "$BASE/boards/$BOARD/cards")
CARD_ID=$(jq -er '.card.id' <<<"$CARD_JSON")
REVISION=$(jq -er '.board.revision' <<<"$CARD_JSON")
echo "card $CARD_ID, revision now $REVISION"

# Ids the sandbox issued resolve in later calls, so create -> comment -> move works.
COMMENT_JSON=$(ok -X POST "${AUTH[@]}" "${JSON[@]}" \
  -d "{\"text\": \"Created by sandbox-smoke.sh\", \"revision\": $REVISION}" \
  "$BASE/boards/$BOARD/cards/$CARD_ID/comments")
REVISION=$(jq -er '.board.revision' <<<"$COMMENT_JSON")
jq -e '{author: .comment.author}' <<<"$COMMENT_JSON"

ok -X POST "${AUTH[@]}" "${JSON[@]}" \
  -d "{\"toListId\": \"sbx-list-done\", \"revision\": $REVISION}" \
  "$BASE/boards/$BOARD/cards/$CARD_ID/move" | jq -e '{listId, position}'

section "4. Nothing was stored"
ok "${AUTH[@]}" "$BASE/boards/$BOARD" \
  | jq -e '.board | select(.revision == 1760000000000) | {revision, lists: (.data.lists | length)}' \
  || fail "the sandbox board changed between reads"

section "5. A title the real API rejects too (angle brackets)"
expect 400 -X POST "${AUTH[@]}" "${JSON[@]}" \
  -d '{"listId": "sbx-list-done", "title": "Ping <@123456>"}' \
  "$BASE/boards/$BOARD/cards"
jq -e '.error == "title_required"' "$BODY_FILE" >/dev/null || fail "expected error title_required"
jq . "$BODY_FILE"

section "6. The same key as a read-only key (X-Sandbox-Persona)"
expect 403 -X POST "${AUTH[@]}" "${JSON[@]}" -H "X-Sandbox-Persona: readonly" \
  -d '{"title": "Not allowed"}' "$BASE/boards/$BOARD/lists"
jq -e '.error == "api_scope_required"' "$BODY_FILE" >/dev/null || fail "expected error api_scope_required"
jq '{error, scope}' "$BODY_FILE"

section "7. Forced failures (X-Sandbox-Scenario)"
force() { expect "$1" "${AUTH[@]}" -H "X-Sandbox-Scenario: $2" "$BASE/me"; }
show_headers() { tr -d '\r' < "$HEAD_FILE" | grep -i -E "$1"; }

echo "-- revision_conflict"
force 409 revision_conflict
jq -e '.error == "revision_conflict"' "$BODY_FILE" >/dev/null || fail "expected error revision_conflict"
jq '{error, currentRevision}' "$BODY_FILE"

echo "-- rate_limited"
force 429 rate_limited
show_headers '^(HTTP/|retry-after|ratelimit-remaining)'

echo "-- server_error (plain text, not JSON)"
force 500 server_error
show_headers '^(HTTP/|content-type)'
cat "$BODY_FILE"; echo

echo "-- bad_gateway (HTML, not JSON)"
force 502 bad_gateway
show_headers '^(HTTP/|content-type)'

echo
echo "Done. To go live: set BASE to https://api.jokelboard.com/api/v1, use a real API key, and replace"
echo "BOARD ('$BOARD') and the list ids with ones that key can reach. Sandbox ids exist only in the sandbox."
