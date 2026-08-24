#!/usr/bin/env bash
# vault-flow.sh
#
# Demonstrates the Board API vault endpoints: list soft-deleted cards,
# vault a live card, restore it, and permanently purge a vaulted card.
#
# Vault endpoints require boards:read / boards:write scopes AND vault access
# on top of normal board authorization. Without vault access you get 403
# vault_access_required even if the token can view or edit the board.
#
# Board and profile keys use the human holder's vault ACL. Organisation
# (global) keys, including official bot keys, need a vault.* endpoint
# permission — or an unrestricted key, which includes every catalog
# permission. Granting "every permission" on a global org key is enough.
#
# Requires: curl, bash, jq, and a valid API token with boards:read + boards:write.
#
# Usage:
#   export JKB_TOKEN="jkb_your_token_here"
#   export BOARD_ID="your-board-id"
#   export CARD_ID="live-card-id-to-vault"      # a card currently on a list
#   export PURGE_CARD_ID="vaulted-card-id"      # optional; defaults to CARD_ID after vault
#   ./vault-flow.sh
#
# The script:
#   1. GET /boards/:id/vault — list vaulted cards grouped by list
#   2. POST .../cards/:cardId/vault — soft-delete a live card
#   3. GET /boards/:id/vault again
#   4. POST .../cards/:cardId/restore — move the card back to a live list
#   5. DELETE .../vault/:cardId?revision= — permanently purge (irreversible)
#
set -euo pipefail

: "${JKB_TOKEN:?Set JKB_TOKEN environment variable to your jkb_... token}"
: "${BOARD_ID:?Set BOARD_ID to the board you want to modify}"
: "${CARD_ID:?Set CARD_ID to a live card id on that board}"

BASE="https://api.jokelboard.com/api/v1"
AUTH_HEADER="Authorization: Bearer ${JKB_TOKEN}"

fetch_revision() {
  curl -sS -H "$AUTH_HEADER" "$BASE/boards/${BOARD_ID}" | jq -r '.board.revision'
}

echo "== 1. List vault (before changes) =="
curl -sS -H "$AUTH_HEADER" "$BASE/boards/${BOARD_ID}/vault" | jq .

REVISION=$(fetch_revision)
echo "Current board revision: $REVISION"

echo
echo "== 2. Vault live card (soft-delete) =="
VAULT_RESP=$(curl -sS -X POST -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d "{\"revision\": ${REVISION}}" \
  "$BASE/boards/${BOARD_ID}/cards/${CARD_ID}/vault")
echo "$VAULT_RESP" | jq '{ok, listId, card: {id: .card.id, title: .card.title, vaultedAt: .card.vaultedAt, vaultedBy: .card.vaultedBy}}'

echo
echo "== 3. List vault (after vault) =="
curl -sS -H "$AUTH_HEADER" "$BASE/boards/${BOARD_ID}/vault" | jq .

REVISION=$(fetch_revision)

echo
echo "== 4. Restore vaulted card to its list =="
RESTORE_RESP=$(curl -sS -X POST -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d "{\"revision\": ${REVISION}}" \
  "$BASE/boards/${BOARD_ID}/cards/${CARD_ID}/restore")
echo "$RESTORE_RESP" | jq '{ok, listId, position, card: {id: .card.id, title: .card.title}}'

# Purge demo: vault again so we can permanently delete from the vault.
echo
echo "== 5. Vault again (setup for purge demo) =="
REVISION=$(fetch_revision)
curl -sS -X POST -H "$AUTH_HEADER" -H "Content-Type: application/json" \
  -d "{\"revision\": ${REVISION}}" \
  "$BASE/boards/${BOARD_ID}/cards/${CARD_ID}/vault" | jq '{ok, listId}'

PURGE_ID="${PURGE_CARD_ID:-$CARD_ID}"
REVISION=$(fetch_revision)
echo "Revision for purge (from GET /boards/:id → board.revision): $REVISION"

echo
echo "== 6. Purge vaulted card (permanent — cannot be undone) =="
curl -sS -X DELETE -H "$AUTH_HEADER" \
  "$BASE/boards/${BOARD_ID}/vault/${PURGE_ID}?revision=${REVISION}" | jq .

echo
echo "✅ Vault flow complete. Purge permanently removes the card from vaultedCards."