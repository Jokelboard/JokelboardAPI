# Jokelboard API

Official documentation and examples for the Jokelboard Programmatic Board API and Board Plugin API.

- Preferred API base URL: `https://api.jokelboard.com/api/v1`
- Compatibility base URL: `https://jokelboard.com/api/v1`
- Status: Stable
- Last updated: 31 August 2026

The Programmatic Board API lets external applications, scripts, CI jobs, and automation agents read and update Jokelboard boards over HTTPS. Requests use bearer API keys and JSON payloads.

---

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Access Requirements](#access-requirements)
- [Authentication](#authentication)
- [API Key Reach](#api-key-reach)
- [Managing API Keys](#managing-api-keys)
- [Official Bot Accounts](#official-bot-accounts)
- [Organisation key endpoint permissions](#organisation-key-endpoint-permissions)
- [Programmatic Board API](#programmatic-board-api)
- [Vault](#vault)
- [Board Plugin API](#board-plugin-api)
- [Data Model](#data-model)
- [Optimistic Concurrency and Revisions](#optimistic-concurrency-and-revisions)
- [Rate Limits and Quotas](#rate-limits-and-quotas)
- [Error Handling](#error-handling)
- [Audit Logging and Mentions](#audit-logging-and-mentions)
- [Examples](#examples)
- [Security Best Practices](#security-best-practices)
- [License](#license)

---

## Overview

The current API has three related surfaces:

1. Session-authenticated key management endpoints for creating, listing, revoking, and configuring API keys.
2. Bearer-authenticated `/api/v1/*` Programmatic Board API endpoints for board, list, card, comment, and move operations.
3. Bearer-authenticated `/api/v1/plugin/*` endpoints for the smaller Board Plugin API checklist surface.

Programmatic Board API operations include:

- Inspect the token owner and token metadata.
- List boards reachable by the key.
- Fetch full board state.
- Replace entire board data.
- Create lists and cards.
- Patch card fields.
- Add card comments.
- Move cards between lists.
- Resolve a card's shareable web URL.
- List, vault, restore, and purge soft-deleted cards.

Organisation-owned keys can optionally carry an [official bot identity](#official-bot-accounts). This changes how the key is presented in comments and audit logs without changing its bearer token, scopes, reach, or underlying human accountability.

The API is intentionally small and JSON-first so it can be used from curl, any language HTTP client, CI jobs, or low-level integration tooling without an SDK.

---

## Quick Start

1. Mint an API key (see [Managing API Keys](#managing-api-keys)). For a single-board automation, create a **board key** from the board's Automations menu and copy the `jkb_...` secret — it is shown only once.
2. Verify the key and find your board:

   ```bash
   export JKB_TOKEN="jkb_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

   curl -sS -H "Authorization: Bearer $JKB_TOKEN" \
     https://api.jokelboard.com/api/v1/me

   curl -sS -H "Authorization: Bearer $JKB_TOKEN" \
     https://api.jokelboard.com/api/v1/boards
   ```

3. Read the board and make your first write, sending the board's current `revision` to guard against concurrent edits:

   ```bash
   export BOARD_ID="board-abc123"

   REVISION=$(curl -sS -H "Authorization: Bearer $JKB_TOKEN" \
     "https://api.jokelboard.com/api/v1/boards/$BOARD_ID" | jq -r '.board.revision')

   curl -sS -X POST \
     -H "Authorization: Bearer $JKB_TOKEN" \
     -H "Content-Type: application/json" \
     -d "{\"title\": \"My first API list\", \"revision\": $REVISION}" \
     "https://api.jokelboard.com/api/v1/boards/$BOARD_ID/lists"
   ```

Complete runnable scripts live in the [`Examples/`](#examples) directory.

---

## Access Requirements

### Programmatic Access

Programmatic board access requires the `boards:read` and/or `boards:write` scope and the governing tier must include `apiAccess`. The [Vault](#vault) endpoints additionally require vault access as described in that section.

Personal boards:

- The user's personal plan must be `ULTRA`.
- Profile API keys only work on the user's own personal boards.

Organisation boards:

- The organisation tier must be one of `FL_PRO`, `BUSINESS`, `SME_BUSINESS`, or `ENTERPRISE`.
- Human users minting or using board-scoped keys on org boards must have the `USE_BOARD_API` organisation permission.
- Organisation-owned keys require the `CREATE_ORG_API_KEYS` permission to list, mint, revoke, or configure as an official bot. Once minted, an organisation-owned key is the credential and can operate across that organisation's boards until revoked.

### Plugin Access

The Board Plugin API is a reduced API for reading board checklist structure and toggling checklist items.

- Personal boards: `PLUS`, `PRO`, or `ULTRA`.
- Organisation boards: any organisation tier with `pluginChecklistApi`.
- Organisation-owned keys do not work with the Board Plugin API.

The tier check runs at request time, not only when the key is minted. If a personal or organisation plan later loses the required feature, existing keys return `403` until access is restored or the key is revoked.

---

## Authentication

All bearer-authenticated v1 requests must include:

```http
Authorization: Bearer jkb_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Token facts:

- Prefix: `jkb_`
- Secret: 32 random bytes encoded URL-safely after the prefix
- Maximum accepted bearer token length: 256 characters
- Storage: server-side SHA-256 hash plus a short prefix preview
- Visibility: the raw secret is returned exactly once at creation time

Scopes:

| Scope | Purpose |
|-------|---------|
| `boards:read` | `GET /me`, board listing, and full board reads |
| `boards:write` | Board reads plus writes: replace board, create list/card, patch card, comment, move, vault/restore/purge |
| `plugin:checklist` | Board Plugin API checklist read/toggle surface |

Programmatic keys use both `boards:read` and `boards:write`. Plugin keys use `plugin:checklist`. A `boards:write` key can also call the plugin checklist endpoints for the same reachable board.

---

## API Key Reach

Every key has a `kind` that limits where it can be used.

| Kind | Reach | Typical mint location |
|------|-------|-----------------------|
| `board` | Exactly one board | Board Automations menu |
| `profile` | Personal boards owned by the user | User Settings -> Security -> API Keys |
| `org` | All boards in one organisation or sub-organisation | Organisation admin -> API Keys |

Reach is enforced before board access checks, so a key cannot probe unrelated boards. Reach misses return the same `404 not_found` as a missing board (no distinct error code that would let a key enumerate boards outside its reach). Organisation keys used on the Plugin API are the exception: they return `403 plugin_not_supported_for_org_tokens`.

Legacy, pre-v2 API keys were not reach-bound. They were migrated to the v2 schema and must be replaced with the appropriate key kind.

---

## Managing API Keys

Key management endpoints use the logged-in web session, not bearer token auth. Creation and bot-configuration endpoints also require fresh authentication and the normal session CSRF protection.

### Board Keys

Board keys are bound to one board.

```http
GET    /api/v1/boards/:id/tokens
POST   /api/v1/boards/:id/tokens
DELETE /api/v1/boards/:id/tokens/:tokenId
```

Create request:

```json
{
  "name": "CI deploy key",
  "type": "programmatic"
}
```

`type` can be:

- `programmatic` -> `boards:read`, `boards:write`
- `plugin` -> `plugin:checklist`

### Profile Keys

Profile keys are bound to the user's personal boards.

```http
GET    /api/me/tokens
POST   /api/me/tokens
DELETE /api/me/tokens/:tokenId
```

Create request:

```json
{
  "name": "Personal automation",
  "type": "programmatic"
}
```

### Organisation Keys

Organisation keys are owned by the organisation and require `CREATE_ORG_API_KEYS`.

```http
GET    /api/organisations/:id/tokens
POST   /api/organisations/:id/tokens
DELETE /api/organisations/:id/tokens/:tokenId
PATCH  /api/organisations/:id/tokens/:tokenId/bot
GET    /api/organisations/:id/tokens/:tokenId/bot-avatar
```

Create request:

```json
{
  "name": "GitHub issue sync"
}
```

The key name is required. After trimming, `default key` and `organisation api key` are reserved case-insensitively; rejected names return `400 name_required` or `400 name_reserved`. Existing keys with legacy names remain valid.

Organisation keys are always Programmatic Board API keys. They cannot be plugin-only keys.

### Official Bot Accounts

An organisation key may be configured with an official bot identity from the organisation's **API Keys** tab or through the session-authenticated bot endpoint. This is optional metadata on a `kind: "org"` key, not a separate key kind or authentication scheme. Bot identity does not grant additional scopes, board reach, or Plugin API access. Endpoint permissions on the same key are configured separately.

Configuring or renaming a bot requires `CREATE_ORG_API_KEYS`, fresh web authentication, session CSRF protection, and an organisation tier with `apiAccess`. Revoked keys return `404 not_found`.

```http
PATCH /api/organisations/:id/tokens/:tokenId/bot
Content-Type: application/json
```

```json
{
  "name": "GitHub Sync",
  "avatar": "data:image/webp;base64,UklGR..."
}
```

Configuration rules:

- `name` is sanitised plain text and must contain at least one character. It is truncated to 32 characters.
- `avatar` is optional. When present it must be a non-empty `data:image/webp;base64,...` value whose decoded payload is at most 16 KiB.
- Omitting `avatar` preserves the current image. Sending `"avatar": null` removes only the image.
- Sending `"name": null` removes the entire bot identity. Clearing remains available after an organisation loses API access so administrators can clean up a downgraded account.

Successful configuration returns:

```json
{
  "ok": true,
  "bot": {
    "name": "GitHub Sync",
    "avatarUrl": "/api/organisations/org-abc/tokens/tok-abc/bot-avatar"
  }
}
```

Removing the bot returns `{ "ok": true, "bot": null }`. Token inventory responses and `GET /api/v1/me` expose the same `bot` object, or `null` when the key has no bot identity. The `user` object returned by `GET /api/v1/me` deliberately remains the human key creator for authorization and accountability.

The avatar URL uses the logged-in web session rather than bearer-token auth. It is visible to members of the organisation or its parent enterprise, returns `image/webp`, supports `ETag`/`If-None-Match`, and is cached privately for up to 300 seconds. A missing avatar returns `404`; an unrelated user receives `403`.

When a configured bot uses the Programmatic Board API:

- New comments are stamped with the bot name and server-owned bot identifiers and render with a `BOT` badge.
- Audit entries render the bot as `actor_bot` while retaining the human key creator underneath for accountability.
- New cards default to no assignees when `assignees` is omitted; explicit assignees are still honoured.
- Organisation-key restrictions are unchanged, including no access to the Board Plugin API.

### Organisation key endpoint permissions

Organisation-owned Programmatic Board API keys can be limited to specific endpoints from the organisation **API Keys** tab (Permissions) or:

```http
PATCH /api/organisations/:id/tokens/:tokenId/permissions
Content-Type: application/json
```

```json
{
  "permissions": [
    "me.read",
    "boards.list",
    "boards.read",
    "cards.create",
    "cards.comment"
  ]
}
```

Rules:

- Requires `CREATE_ORG_API_KEYS`, fresh web authentication, and an organisation tier with `apiAccess`.
- `permissions` must be an array of catalog keys. Unknown keys are dropped. An empty array denies every catalogued endpoint.
- A key with `endpointPermissions: null` (the default for existing keys) is unrestricted and may call every Programmatic Board API endpoint it already could.
- Board and profile keys are not limited by this catalog.
- Vault endpoints still require vault access in addition to the matching catalog key.
- The Board Plugin API remains unavailable to organisation keys.

`GET /api/organisations/:id/tokens` returns `endpointPermissionCatalog` plus `endpointPermissions` on each organisation key. `GET /api/v1/me` exposes the same `token.endpointPermissions` field. A denied call returns `403` with `api_endpoint_permission_denied`.

Catalog keys:

| Key | Endpoint |
| --- | --- |
| `me.read` | `GET /api/v1/me` |
| `boards.list` | `GET /api/v1/boards` |
| `boards.read` | `GET /api/v1/boards/:id` and `GET /api/v1/boards/:id/revision` |
| `boards.replace` | `PUT /api/v1/boards/:id` |
| `lists.create` | `POST /api/v1/boards/:id/lists` |
| `cards.create` | `POST /api/v1/boards/:id/cards` |
| `cards.update` | `PATCH /api/v1/boards/:id/cards/:cardId` |
| `cards.comment` | `POST /api/v1/boards/:id/cards/:cardId/comments` |
| `cards.move` | `POST /api/v1/boards/:id/cards/:cardId/move` |
| `cards.link` | `GET /api/v1/boards/:id/cards/:cardId/link` |
| `vault.read` | `GET /api/v1/boards/:id/vault` |
| `vault.vault` | `POST /api/v1/boards/:id/cards/:cardId/vault` |
| `vault.restore` | `POST /api/v1/boards/:id/cards/:cardId/restore` |
| `vault.purge` | `DELETE /api/v1/boards/:id/vault/:cardId` |

### Create Response

All create endpoints return the raw token once:

```json
{
  "token": "jkb_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "tokenPreview": "jkb_xxxxxxxx",
  "apiToken": {
    "id": "tok_abc123",
    "kind": "board",
    "name": "CI deploy key",
    "tokenPrefix": "jkb_xxxxxxxx",
    "scopes": ["boards:read", "boards:write"],
    "boardId": "board-abc123",
    "orgId": null,
    "createdBySub": null,
    "created_at": 1715000000000,
    "last_used_at": null,
    "endpointPermissions": null,
    "bot": null
  }
}
```

Every public token row includes `bot` and `endpointPermissions`. `bot` is `{ "name": string, "avatarUrl": string | null }` only for a configured organisation key and `null` for every other key. `endpointPermissions` is a catalog-key array on restricted organisation keys and `null` when the key is unrestricted (or is not an organisation key).

### Legacy `/api/tokens`

The old generic token creation surface has been removed.

| Endpoint | Current behavior |
|----------|------------------|
| `GET /api/tokens` | Still works as a unified read aggregator for keys the logged-in user can see |
| `POST /api/tokens` | `410 Gone`; use the kind-specific create endpoints above |
| `DELETE /api/tokens/:id` | `410 Gone`; revoke through the matching kind-specific endpoint |

---

## Programmatic Board API

All endpoints below are relative to `https://api.jokelboard.com/api/v1`.

### GET /api/v1/me

Returns the token owner and token metadata.

```json
{
  "user": {
    "sub": "roblox-123",
    "username": "dylanjkl",
    "displayName": "Dylan",
    "picture": "https://example.com/avatar.png",
    "tier": "ULTRA"
  },
  "token": {
    "id": "tok_abc123",
    "kind": "board",
    "name": "CI deploy key",
    "tokenPrefix": "jkb_xxxxxxxx",
    "scopes": ["boards:read", "boards:write"],
    "boardId": "board-abc123",
    "orgId": null,
    "createdBySub": null,
    "created_at": 1715000000000,
    "last_used_at": 1715012345678,
    "bot": null
  }
}
```

For a configured organisation key, `token.bot` contains its official `{ name, avatarUrl }` identity. `user` still describes the human key creator.

### GET /api/v1/boards

Lists boards reachable by the key.

- `kind: "board"` returns at most the bound board.
- `kind: "profile"` returns personal boards owned by the user.
- `kind: "org"` returns boards in the bound organisation.

```json
{
  "boards": [
    {
      "id": "board-abc123",
      "workspace": "personal",
      "name": "Sprint 42",
      "title": "Sprint 42",
      "created_at": 1714000000000,
      "updated_at": 1714990000000,
      "revision": 1714990000000,
      "url": "/api/v1/boards/board-abc123"
    }
  ]
}
```

### GET /api/v1/boards/:id

Fetches the board payload, including `data`. The default shape is the complete document (lists, cards, comments, attachments, inlined cover images, presets).

Query parameters (all optional, additive — omit them and the response is unchanged):

| Parameter | Values | Effect |
|-----------|--------|--------|
| `projection` | `full` (default), `cards` | `cards` keeps list/card identity, titles, labels, assignees, due dates, field values, descriptions, and checklists. It drops comments, attachments, cover images, vaulted cards, and board presets. |
| `listId` | a list id | Return only that list. Unknown ids return `404 list_not_found`. |
| `lists` | comma-separated list ids | Return those lists in **board order**. Any unknown id returns `404 list_not_found`. Do not send `listId` and `lists` together (`400 invalid_list_filter`). |

`projection=cards` is the right default for game servers, CI, and other clients that only need the kanban structure. List filters and projections shrink the **response**, not the server-side read: the stored document is still loaded, then filtered in memory. Cover images are not hydrated for `projection=cards`. List filters are a payload convenience, not an access-control boundary: a key that can read the board can still request any list.

Successful responses send `ETag` and `Cache-Control: private, no-cache`. Repeat the request with `If-None-Match` set to the previous `ETag` value **verbatim** to get `304 Not Modified` and an empty body when the board (and the same projection, list filter, and vault-visibility of the caller) has not changed. The ETag is derived from `updated_at` plus those inputs, so a matching 304 does not serialize the document. Replay the header as returned; commas inside `?lists=` tags are part of the quoted ETag, not list separators.

```http
GET /api/v1/boards/board-abc123?projection=cards&listId=admin
Authorization: Bearer jkb_…
If-None-Match: W/"v1-board-board-abc123-1714990000000-cards-admin-nv"
```

```json
{
  "board": {
    "id": "board-abc123",
    "workspace": "org:org-xyz",
    "name": "Production Incidents",
    "title": "Production Incidents",
    "created_at": 1714000000000,
    "updated_at": 1714990000000,
    "revision": 1714990000000,
    "url": "/api/v1/boards/board-abc123",
    "data": {
      "title": "Production Incidents",
      "lists": []
    }
  }
}
```

On `https://api.jokelboard.com` (Cloudflare tunnel, no Caddy), JSON bodies of **4 KiB or larger** may be gzip-compressed when the client sends `Accept-Encoding: gzip` (not `gzip;q=0`). Compression is asynchronous, capped to one in-flight gzip on the origin, and skipped when it would not shrink the body. Apex `https://jokelboard.com/api/v1` is compressed by Caddy instead. Clients that auto-decode Content-Encoding, including Roblox `HttpService`, can send `Accept-Encoding: gzip`.

### GET /api/v1/boards/:id/revision

Cheap probe for polling. Returns only identity and the current `revision` (`updated_at`). Same auth, reach, and `boards.read` endpoint permission as the full GET. Also supports `ETag` / `If-None-Match`.

```json
{
  "id": "board-abc123",
  "revision": 1714990000000,
  "updated_at": 1714990000000
}
```

Recommended poll loop: store `revision`, call this endpoint (or send `If-None-Match` on the full GET), and only refetch `GET /api/v1/boards/:id` when the revision changes.

### PUT /api/v1/boards/:id

Replaces the whole board `data` object.

```json
{
  "revision": 1714990000000,
  "data": {
    "title": "New Board Title",
    "lists": []
  }
}
```

Rules:

- `data` must be an object.
- `data.lists` must be an array.
- Unknown board data keys are preserved by clients that include them in the replacement payload.
- Server-side validation and quota checks are the same checks used by the web UI.

### POST /api/v1/boards/:id/lists

Creates a list at the end of the board.

```json
{
  "title": "Backlog",
  "id": "list-optional-custom-id",
  "revision": 1714990000000
}
```

Response status: `201 Created`. The response echoes the created list:

```json
{
  "ok": true,
  "list": {
    "id": "list-abc",
    "title": "Backlog",
    "cards": []
  }
}
```

### POST /api/v1/boards/:id/cards

Creates a card in an existing list.

```json
{
  "listId": "list-abc",
  "title": "Fix login redirect",
  "categoryId": "P1",
  "description": "Users on mobile get sent to the wrong domain.",
  "descriptionMode": "markdown",
  "descriptionSize": "large",
  "dateType": "due",
  "labels": [
    { "name": "bug", "color": "#ff5e5e" }
  ],
  "assignees": ["roblox-123"],
  "due": { "iso": "2026-06-01T09:00:00Z" },
  "checklist": {
    "items": [
      { "text": "Reproduce on staging", "done": true },
      { "text": "Deploy fix", "done": false }
    ]
  },
  "attachments": [
    { "name": "Screenshot", "url": "https://example.com/screenshot.png" }
  ],
  "revision": 1714990000000
}
```

Notes:

- `categoryId` is the canonical category field.
- `severity` is still accepted as a legacy alias and is normalized into `categoryId`.
- `ticket` is generated server-side if omitted.
- `id` may be supplied; otherwise the server generates a card id.
- `createdAt` is server-stamped at creation (Unix epoch milliseconds) and cannot be supplied by the client — implausible values are replaced or dropped at save time.
- `fieldValues` are applied through `PATCH /boards/:id/cards/:cardId`, not during card creation.
- If `assignees` is omitted or normalises to an empty list, a human-owned key defaults to the key owner's user id. A bot-configured organisation key instead defaults to `[]`; send explicit assignees when the bot should assign the card.
- `kind: "filler"` creates a minimal filler card with `id`, `kind`, `title`, and `comments`.

Card configuration can be set at creation with `descriptionSize`, `dateType`, `due`, `dueJoin`, and `dueDepart`. The date modes are:

- `due` (default) — `due` is a deadline and receives the normal due-soon/overdue treatment.
- `static` — `due` is displayed as a neutral calendar date without overdue semantics.
- `employee` — `dueJoin` and `dueDepart` are displayed as neutral join/depart dates. Either date may be omitted.

All date fields use `{ "iso": "<ISO-8601 timestamp>" }` or `null`. The three stored dates are independent: changing `dateType` does not discard dates from the other modes, so an integration can switch modes without losing them. Employee cards do not use a preserved `due` value for due-date search or overdue matching.

Response status: `201 Created`. The response echoes the created card, including the server-assigned `id` and `ticket`:

```json
{
  "ok": true,
  "card": {
    "id": "card-9f2c1a",
    "ticket": "PROD-1842",
    "createdAt": 1784620424303,
    "title": "Fix login redirect",
    "categoryId": "P1"
  }
}
```

After any successful write, refetch `GET /api/v1/boards/:id` (or track the response) to obtain the board's new `revision` before the next mutation.

### PATCH /api/v1/boards/:id/cards/:cardId

Partially updates a card.

Patchable fields:

- `title`
- `description`
- `descriptionMode`
- `descriptionSize`
- `fieldValues`
- `categoryId`
- `severity` as a legacy alias for `categoryId`
- `labels`
- `assignees`
- `dateType`
- `due`
- `dueJoin`
- `dueDepart`
- `checklist`
- `attachments`

Example:

```json
{
  "title": "Fix login redirect (hotfix)",
  "categoryId": "P0",
  "labels": ["bug", "hotfix", "mobile"],
  "fieldValues": {
    "owner-team": "platform",
    "ready-for-review": "true"
  },
  "dateType": "employee",
  "dueJoin": { "iso": "2026-08-03T09:00:00Z" },
  "dueDepart": { "iso": "2027-08-03T17:00:00Z" },
  "revision": 1714990000000
}
```

`fieldValues` are capped to 64 keys. Keys longer than 64 characters are ignored, and values are stored as strings capped to 64 characters. Send `"fieldValues": null` to clear the field values.

`descriptionSize` accepts `small`, `normal`, or `large`; `normal` is the default. `dateType` accepts `due`, `static`, or `employee`; `due` is the default. The API represents both defaults by omitting the corresponding property from stored card responses. Send the default value (or `null`) to reset a custom configuration. Send `null` for `due`, `dueJoin`, or `dueDepart` to clear that date.

The response echoes the updated card under `card`.

### POST /api/v1/boards/:id/cards/:cardId/comments

Adds a comment to a card. Board and profile keys use the API key owner as the author. A bot-configured organisation key uses its official bot name and receives server-owned bot identity fields.

```json
{
  "text": "@alice can you take a look at this?",
  "revision": 1714990000000
}
```

Regular comments are capped at 3,000 characters. A request with `"kind": "docucomment"` creates a longer document-style comment capped at 15,000 characters. Bot identity is assigned by the server; client-supplied `botTokenId` and `botOrgId` values cannot forge or replace a bot stamp.

On organisation boards, `@username` mentions create in-app mention notifications for matching org members who can view the board. For a configured bot key, the notification names the bot while retaining the human key creator's user id for accountability.

### POST /api/v1/boards/:id/cards/:cardId/move

Moves a card to another list, or reorders it within a list.

```json
{
  "toListId": "list-done",
  "position": 0,
  "revision": 1714990000000
}
```

`position: 0` means top of the target list. Omit `position`, or send a value larger than the target list length, to place the card at the bottom.

### GET /api/v1/boards/:id/cards/:cardId/link

Returns the card's shareable web URL — the same link the board UI's **Share** button copies. Opening it in a browser loads the board and opens that card's detail modal.

Requires scope: `boards:read`.

```bash
curl -H "Authorization: Bearer $JKB_TOKEN" \
  https://api.jokelboard.com/api/v1/boards/$BOARD_ID/cards/taiga-us-213/link
```

Response:

```json
{
  "cardId": "taiga-us-213",
  "listId": "list-todo",
  "boardId": "board-a1b2c3",
  "canonical": true,
  "path": "/aegis/aia/management-board?card=taiga-us-213",
  "url": "https://jokelboard.com/aegis/aia/management-board?card=taiga-us-213"
}
```

| Field | Meaning |
| --- | --- |
| `url` | Absolute browser URL on the Jokelboard web app. This is the value to hand to end users. |
| `path` | The same link as an origin-relative path. |
| `canonical` | `true` when the board lives in an enterprise sub-organisation and the link uses its canonical `/<enterprise>/<sub-org>/<board-slug>` form; `false` when the link uses the `/board/<id>` fallback (personal and legacy organisation boards). |
| `cardId` / `listId` / `boardId` | The card, the list it currently sits in, and the board the link resolves through. |

Notes:

- `url` always points at the Jokelboard **web app** origin, never `api.jokelboard.com`.
- Only **live** cards resolve. A vaulted (soft-deleted) card returns `404` with `card_not_found`, exactly like an unknown card id — restore it first if you need a link.
- Whether the visitor can actually open the link is decided by the board's own access rules at click time; the endpoint does not mint any extra access.
- Canonical enterprise links can change when the board's slug is edited, the board is transferred, or its sub-organisation is renamed. Re-fetch the link when you need it instead of caching it long-term.

---

## Vault

Each board list may hold a per-list **vault**: the `vaultedCards` array stores soft-deleted cards that remain recoverable until purged. The four vault endpoints below require normal board authorization **and** separate **vault access** on top of view/edit rights. A principal who can read or write the board but lacks vault access receives `403` with `vault_access_required`.

On personal boards, vault access is the board owner. On organisation boards, vault access is granted by the `VAULT_ACCESS` organisation permission, a matching per-board vault ACL entry, or owner/admin/`MANAGE_BOARDS` roles. For `kind: "org"` API keys, vault access is granted by the key's vault endpoint permissions (`vault.read`, `vault.vault`, `vault.restore`, `vault.purge`). An unrestricted organisation key (`endpointPermissions: null`) includes those permissions and can use the vault. Organisation keys do not inherit the key creator's vault ACL. Official bot identity does not change this. Board and profile keys still use the human holder's vault access as described above.

Whole-board `PUT` can still persist `vaultedCards` for clients that manage the full board payload, but these granular endpoints are the recommended programmatic path.

### GET /api/v1/boards/:id/vault

Lists vaulted cards grouped by the list they were deleted from. Only lists with at least one vaulted card appear.

Requires scope: `boards:read` and vault access.

```json
{
  "vault": [
    {
      "listId": "todo",
      "listTitle": "Todo",
      "cards": [
        {
          "id": "v1",
          "title": "Old task",
          "vaultedAt": 1715000000000,
          "vaultedBy": "roblox-123"
        }
      ]
    }
  ]
}
```

Errors:

- `403` `vault_access_required` — board/profile token can view the board but lacks vault access
- `403` `api_endpoint_permission_denied` — organisation key is locked without `vault.read`

### POST /api/v1/boards/:id/cards/:cardId/vault

Soft-deletes a **live** card into its list's vault. The server stamps `vaultedAt` (milliseconds since epoch) and `vaultedBy` (actor sub) on the card and **prepends** it to that list's `vaultedCards` (newest first).

Requires scope: `boards:write` and vault access.

Optional body:

```json
{
  "revision": 1714990000000
}
```

Response:

```json
{
  "ok": true,
  "board": { "id": "board-abc123", "revision": 1715012345678, "data": { "lists": [] } },
  "card": {
    "id": "v1",
    "title": "Old task",
    "vaultedAt": 1715000000000,
    "vaultedBy": "roblox-123"
  },
  "listId": "todo"
}
```

Notes:

- Vaulting removes the card from the live list, so it does not trip the card-creation burst guard.
- `404` `card_not_found` — `:cardId` is not a live card on the board
- `403` `vault_access_required`
- `409` `revision_conflict`

### POST /api/v1/boards/:id/cards/:cardId/restore

Restores a **vaulted** card to a live list. `vaultedAt` and `vaultedBy` are stripped. By default the card returns to the list it was vaulted in, appended at the end.

Requires scope: `boards:write` and vault access.

Optional body:

```json
{
  "toListId": "in-progress",
  "position": 3,
  "revision": 1714990000000
}
```

- `toListId` — restore into another list (`404` `list_not_found` if missing)
- `position` — integer index, clamped to `0..list.length`

Response:

```json
{
  "ok": true,
  "board": { "id": "board-abc123", "revision": 1715012345678, "data": { "lists": [] } },
  "card": { "id": "v1", "title": "Old task" },
  "listId": "todo",
  "position": 3
}
```

Notes:

- Restoring adds one live card and counts toward the card-creation burst guard (10 cards / 5 seconds per user and board).
- Moving between live and vaulted arrays does not change total card count on the board, so restore alone does not exceed the plan card cap.
- `404` `card_not_found` — `:cardId` is not in the vault
- `404` `list_not_found`
- `403` `vault_access_required`
- `409` `revision_conflict`

### DELETE /api/v1/boards/:id/vault/:cardId

Permanently deletes (purges) a vaulted card. **Irreversible.**

Requires scope: `boards:write` and vault access.

Accepts optional `revision` in the JSON body **or** as a `?revision=` query parameter (for clients that cannot send a `DELETE` body):

```http
DELETE /api/v1/boards/:id/vault/:cardId?revision=1714990000000
```

Response:

```json
{
  "ok": true,
  "board": { "id": "board-abc123", "revision": 1715012345678, "data": { "lists": [] } },
  "cardId": "v1",
  "purged": true
}
```

Errors:

- `404` `card_not_found` — card is not in the vault
- `403` `vault_access_required`
- `409` `revision_conflict`


---

## Board Plugin API

The Board Plugin API uses bearer auth and either `plugin:checklist` or `boards:write` scope.

### GET /api/v1/plugin/access-level

Capability probe used by plugin and in-product UI. With bearer auth, the response reflects the token scopes. With a logged-in web session, the response reflects the user's tier and organisations.

### GET /api/v1/plugin/boards/:id

Returns only the board/list/card/checklist shape needed by plugin clients. Cover images are not hydrated. Successful responses send `ETag` / `Cache-Control: private, no-cache` and honour `If-None-Match` with `304`. A matching 304 is answered from board metadata and does not parse the stored document.

```json
{
  "board": {
    "id": "board-abc123",
    "name": "Sprint 42",
    "lists": [
      {
        "id": "list-abc",
        "title": "Backlog",
        "cards": [
          {
            "id": "card-abc",
            "title": "Fix login redirect",
            "checklist": { "items": [] }
          }
        ]
      }
    ]
  }
}
```

### POST /api/v1/plugin/boards/:id/cards/:cardId/checklist-items/:itemId/toggle

Toggles one checklist item. The request needs no body:

```bash
curl -sS -X POST -H "Authorization: Bearer $JKB_TOKEN" \
  "https://api.jokelboard.com/api/v1/plugin/boards/$BOARD_ID/cards/$CARD_ID/checklist-items/$ITEM_ID/toggle"
```

Response:

```json
{
  "ok": true,
  "item": {
    "id": "cli_abc123",
    "text": "Deploy fix",
    "done": true
  }
}
```

---

## Data Model

### BoardData

```ts
interface BoardData {
  title?: string;
  lists: BoardList[];
  presets?: {
    labels?: Array<{
      id: string;
      name: string;
      color: string;
      twoTone?: boolean;
      borderColor?: string;
    }>;
    checklists?: Array<{ id: string; name: string; items: string[] }>;
    fields?: Array<{ id: string; name: string; type: 'checkbox' | 'text' }>;
    cardCategory?: {
      name: string;
      defaultOptionId: string;
      options: Array<{ id: string; label: string; color: string }>;
    };
    cards?: {
      default?: Record<string, unknown>;
      templates?: Array<Record<string, unknown>>;
    };
  };
  [key: string]: unknown;
}
```

### BoardList

```ts
interface BoardList {
  id: string;
  title: string;
  cards: BoardCard[];
  vaultedCards?: BoardCard[]; // soft-deleted cards, see Vault
}
```

Soft-deleted cards live in each list's `vaultedCards` array rather than a single board-wide trash. Deleting a list removes that list and its vault together.

### BoardCard

```ts
interface BoardCard {
  id: string;
  kind?: 'filler' | string;
  ticket?: string;
  createdAt?: number; // Unix epoch ms, server-stamped at creation (see below)
  title: string;
  categoryId?: string;
  severity?: string; // legacy fallback only
  description?: string;
  descriptionMode?: 'plain' | 'markdown' | 'fields';
  descriptionSize?: 'small' | 'large'; // omitted means normal
  fieldValues?: Record<string, string>;
  labels?: Array<{ id?: string; name: string; color?: string; twoTone?: boolean; borderColor?: string }>;
  assignees?: string[];
  comments?: Array<{
    id: string;
    author: string;
    authorSub?: string; // human-authored comment
    botTokenId?: string; // server-stamped official bot key
    botOrgId?: string; // organisation that owns the bot key
    text: string;
    ts: number;
    kind?: 'docucomment' | 'comment';
  }>;
  checklist?: {
    items: Array<{ id?: string; text: string; done: boolean }>;
  };
  attachments?: Array<{ id?: string; name: string; url: string }>;
  due?: { iso?: string; in?: string; overdue?: boolean } | null;
  dateType?: 'static' | 'employee'; // omitted means due
  dueJoin?: { iso: string } | null;
  dueDepart?: { iso: string } | null;
  image?: { data: string; w: number; h: number; bytes: number } | null;
  components?: Record<string, boolean>;
  vaultedAt?: number; // set only while the card is in vaultedCards
  vaultedBy?: string | null; // set only while the card is in vaultedCards
}
```

`botTokenId` and `botOrgId` are read-only provenance fields. The server stamps them only on new comments written by a configured organisation bot key, strips forged stamps, and prevents later writes from changing an existing bot-stamped comment's identity.

`createdAt` is the card's creation time in Unix epoch milliseconds. It is server-owned: stamped when the card is created (board UI or `POST /boards/:id/cards`), and implausible client-supplied values are replaced or dropped at save time. Cards created before the field existed have their timestamp recovered from the card id encoding where possible — both on API reads and via a persistent backfill on the board's next save. A card whose creation time is genuinely unknown omits the field; the API never fabricates a date.

Validation highlights:

- Card titles are capped at 200 characters.
- List titles are capped at 80 characters.
- Labels are capped at 50 per card.
- `description` is capped at 8,000 characters through card create/patch.
- `descriptionMode` must be `plain`, `markdown`, or `fields`.
- Checklist items are capped at 200 per patch.
- Attachment arrays are capped at 100 per patch.
- Plain-text title and label inputs reject control characters and angle brackets.
- Plan quotas still apply to total cards, lists, labels, image cards, and storage bytes.

---

## Optimistic Concurrency and Revisions

All mutating Programmatic Board API endpoints accept an optional `revision` field:

- `PUT /boards/:id`
- `POST /boards/:id/lists`
- `POST /boards/:id/cards`
- `PATCH /boards/:id/cards/:cardId`
- `POST /boards/:id/cards/:cardId/comments`
- `POST /boards/:id/cards/:cardId/move`
- `POST /boards/:id/cards/:cardId/vault`
- `POST /boards/:id/cards/:cardId/restore`
- `DELETE /boards/:id/vault/:cardId`

If supplied, `revision` must equal the board's current `updated_at` value. `DELETE /boards/:id/vault/:cardId` also accepts `revision` as a `?revision=` query parameter when a request body is impractical. A mismatch returns:

```json
{
  "error": "revision_conflict",
  "message": "Board was updated after the revision supplied with this request.",
  "currentRevision": 1715012345678
}
```

Recommended flow:

1. `GET /api/v1/boards/:id` (or `GET /api/v1/boards/:id/revision` when you only need the stamp)
2. Store `board.revision`
3. Send the write with that `revision`
4. On `409`, refetch and retry after merging your intended change

---

## Rate Limits and Quotas

`/api/v1` is **not** on the website session limiter. Bearer traffic uses three stacked budgets so shared egress IPs (Roblox game servers, CI) do not starve each other, while a leaked key still cannot flood the origin:

| Budget | Key | Window | Limit | Applies to |
|--------|-----|--------|-------|------------|
| Per token | SHA-256 of the presented `jkb_…` secret | 15 minutes | 3600 | Any well-formed `jkb_` bearer (including the first request of a new key) |
| Unauthenticated IP | Client IP | 15 minutes | 120 | Missing bearer, junk `jkb_…` values, and the first request of a key that has not yet authenticated on this process |
| Authenticated IP ceiling | Client IP | 15 minutes | 15000 | Keys that recently passed authentication, as a many-keys-from-one-IP backstop |

A bearer that only *looks* like `jkb_…` does **not** skip the 120 probe cap. After a key authenticates successfully it is remembered for the window, then uses the per-token 3600 budget plus the 15000 IP ceiling. Many real keys from one IP still share that 15000 ceiling; they do not stack 3600 each.

Exceeded budgets return HTTP `429` with `{ "error": "rate_limited" }` and standard `RateLimit-*` headers. Prefer `GET /boards/:id/revision` and `If-None-Match` so unchanged boards do not consume the token budget on a full document.

Website session routes remain at 3000 requests / 15 minutes per IP.

### Card Creation Burst Guard

The v1 write surface limits new card creation to 10 cards per 5 seconds per user and board. This protects boards from runaway scripts and accidental import loops.

When exceeded:

```json
{
  "error": "card_rate_limited",
  "message": "Create at most 10 cards every 5 seconds.",
  "limit": 10,
  "windowMs": 5000,
  "retryAfter": 3,
  "attempted": 11,
  "current": 9
}
```

HTTP status: `429 Too Many Requests`.

### Plan Quotas

Every write is also checked against the governing tier's limits, including:

- Cards per board
- Lists per board
- Labels per card
- Image cards per board
- Organisation storage bytes

Quota failures return a typed error such as `card_limit` or `list_limit` with upgrade metadata when available.

---

## Error Handling

Errors are JSON objects with a machine-readable `error` code. Many errors also include `message` and additional metadata.

Common codes:

| Code | HTTP | Meaning |
|------|------|---------|
| `api_token_required` | 401 | Missing bearer token |
| `invalid_api_token` | 401 | Bad format, unknown token, revoked token, or unusable token owner |
| `api_scope_required` | 403 | Token lacks the route's required scope |
| `insufficient_scope` | 403 | Plugin route requires `plugin:checklist` or `boards:write` |
| `api_access_blocked` | 403 | Personal or org tier does not currently include Programmatic Board API access |
| `plugin_api_access_blocked` | 403 | Tier does not currently include Board Plugin API access |
| `plugin_not_supported_for_org_tokens` | 403 | Org key used on plugin endpoint |
| `forbidden` | 403 | User cannot access the board |
| `vault_access_required` | 403 | Board/profile token can view or edit the board but lacks vault access |
| `api_endpoint_permission_denied` | 403 | Organisation key is locked without the matching catalog key |
| `not_found` | 404 | Board or token not found, or the key's reach does not include that board |
| `list_not_found` | 404 | List not found |
| `card_not_found` | 404 | Card not found |
| `item_not_found` | 404 | Checklist item not found |
| `no_checklist` | 404 | Plugin toggle target card has no checklist |
| `revision_conflict` | 409 | Stale write revision |
| `list_exists` | 409 | Client-supplied list id already exists |
| `card_exists` | 409 | Client-supplied card id already exists |
| `invalid_projection` | 400 | `?projection=` was not `full` or `cards` |
| `invalid_list_filter` | 400 | `listId` and `lists` were both sent, or `lists` was empty |
| `card_rate_limited` | 429 | Too many cards created in the burst window |
| `rate_limited` | 429 | Token or IP HTTP budget exceeded |
| `invalid_data` | 400 | Whole-board replacement payload is invalid |
| `invalid_card_patch` | 400 | Card patch payload failed validation |
| `invalid_type` | 400 | Token creation type was not `programmatic` or `plugin` |
| `name_required` | 400 | Token/list/card name or title was empty after sanitisation |
| `name_reserved` | 400 | Organisation key name matched a reserved default name |
| `bot_name_invalid` | 400 | Bot name was missing or empty after sanitisation |
| `avatar_invalid` | 400 | Bot avatar was not a valid non-empty WebP data URL within the 16 KiB limit |
| `text_required` | 400 | Comment text was empty or rejected |
| `gone` | 410 | Legacy `POST /api/tokens` or `DELETE /api/tokens/:id` was called |

---

## Audit Logging and Mentions

On organisation and sub-organisation boards:

- Programmatic mutations are recorded in the board audit log.
- Vault, restore, and purge are audit-logged as `card.vaulted`, `card.restored`, and `card.purged`.
- Profile and board keys render the human API key owner as the actor.
- A configured organisation bot key renders an `actor_bot` object with `{ name, avatarUrl }` in board, organisation, and enterprise audit reads. The underlying `actor_sub`/`actor_username` remains present for human accountability.
- Audit bot identity is resolved at read time: configuring or renaming a bot changes how that key's older entries render. Revoking a configured key does not erase its historical bot attribution.
- Organisation key creation, revocation, bot update, and bot removal are recorded in the organisation audit log.
- New comments written by a configured bot key are stamped with the bot name and show a `BOT` badge. Bot stamps are server-owned and cannot be forged through whole-board writes.
- Comment mentions (`@username`) create notification rows for matching org members who can view the board. Bot-authored notifications show the bot name while retaining the human creator's user id.
- Plugin checklist toggles on org boards are also audit logged.

Personal boards do not write organisation audit entries.

---

## Examples

See the [`Examples/`](./Examples) directory:

- [`curl-basic.sh`](./Examples/curl-basic.sh) - minimal auth, board fetch, list/card/comment flow
- [`vault-flow.sh`](./Examples/vault-flow.sh) - list, vault, restore, and purge soft-deleted cards
- [`node-full-flow.js`](./Examples/node-full-flow.js) - Node.js 18+ flow with conflict retry, card patching, and move
- [`python-client.py`](./Examples/python-client.py) - Python `requests` client with field value patching and retries
- [`github-action-sync.yml`](./Examples/github-action-sync.yml) - GitHub Actions issue-to-card workflow
- [`plugin-checklist.sh`](./Examples/plugin-checklist.sh) - Board Plugin API: access probe, checklist listing, item toggle

---

## Security Best Practices

1. Treat API keys like passwords. A Programmatic Board API key with write scope can mutate every board in its reach.
2. Prefer the narrowest reach that works: board key before profile or organisation key.
3. Never commit keys to git. Use environment variables, GitHub Actions secrets, or a secrets manager.
4. Rotate and revoke unused keys.
5. Watch `last_used_at` in token lists.
6. Use HTTPS only.
7. Scan logs and `.env` files for the `jkb_` prefix before sharing them.
8. Give each organisation automation a descriptive key name and, when it acts publicly, a distinct bot identity so audit attribution stays legible.

---

## License

Jokelboard is proprietary commercial software. All rights reserved.

Documentation, examples, and API access are provided solely to customers with valid paid subscriptions in accordance with Jokelboard's terms of service. Unauthorized reproduction, modification, or distribution is prohibited.
