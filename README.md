# Jokelboard API

Official documentation and examples for the Jokelboard Programmatic Board API and Board Plugin API.

- Preferred API base URL: `https://api.jokelboard.com/api/v1`
- Compatibility base URL: `https://jokelboard.com/api/v1`
- Status: Stable
- Last updated: May 2026

The Programmatic Board API lets external applications, scripts, CI jobs, and automation agents read and update Jokelboard boards over HTTPS. Requests use bearer API keys and JSON payloads.

---

## Table of Contents

- [Overview](#overview)
- [Access Requirements](#access-requirements)
- [Authentication](#authentication)
- [API Key Reach](#api-key-reach)
- [Managing API Keys](#managing-api-keys)
- [Programmatic Board API](#programmatic-board-api)
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

1. Session-authenticated key management endpoints for creating, listing, and revoking API keys.
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

The API is intentionally small and JSON-first so it can be used from curl, any language HTTP client, CI jobs, or low-level integration tooling without an SDK.

---

## Access Requirements

### Programmatic Access

Programmatic board access requires the `boards:read` and/or `boards:write` scope and the governing tier must include `apiAccess`.

Personal boards:

- The user's personal plan must be `ULTRA`.
- Profile API keys only work on the user's own personal boards.

Organisation boards:

- The organisation tier must be one of `FL_PRO`, `BUSINESS`, `SME_BUSINESS`, or `ENTERPRISE`.
- Human users minting or using board-scoped keys on org boards must have the `USE_BOARD_API` organisation permission.
- Organisation-owned keys require the `CREATE_ORG_API_KEYS` permission to list, mint, or revoke. Once minted, an organisation-owned key is the credential and can operate across that organisation's boards until revoked.

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
| `boards:write` | Board reads plus writes: replace board, create list/card, patch card, comment, move |
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

Reach is enforced before board access checks, so a key cannot probe unrelated boards.

| Violation | HTTP | Error code |
|-----------|------|------------|
| Board key used on a different board | 403 | `board_scope_violation` |
| Profile key used on an org board | 403 | `profile_scope_violation` |
| Organisation key used outside its org | 403 | `org_scope_violation` |
| Organisation key used on the plugin API | 403 | `plugin_not_supported_for_org_tokens` |

Legacy, pre-v2 API keys were not reach-bound. They were migrated to the v2 schema and must be replaced with the appropriate key kind.

---

## Managing API Keys

Key management endpoints use the logged-in web session, not bearer token auth. Creation endpoints also require fresh authentication.

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
```

Create request:

```json
{
  "name": "Org-wide automation"
}
```

Organisation keys are always Programmatic Board API keys. They cannot be plugin-only keys.

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
    "last_used_at": null
  }
}
```

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
    "last_used_at": 1715012345678
  }
}
```

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

Fetches the complete board payload, including `data`.

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

Response status: `201 Created`.

### POST /api/v1/boards/:id/cards

Creates a card in an existing list.

```json
{
  "listId": "list-abc",
  "title": "Fix login redirect",
  "categoryId": "P1",
  "description": "Users on mobile get sent to the wrong domain.",
  "descriptionMode": "markdown",
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
- `fieldValues` are applied through `PATCH /boards/:id/cards/:cardId`, not during card creation.
- `kind: "filler"` creates a minimal filler card with `id`, `kind`, `title`, and `comments`.

Response status: `201 Created`.

### PATCH /api/v1/boards/:id/cards/:cardId

Partially updates a card.

Patchable fields:

- `title`
- `description`
- `descriptionMode`
- `fieldValues`
- `categoryId`
- `severity` as a legacy alias for `categoryId`
- `labels`
- `assignees`
- `due`
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
  "due": null,
  "revision": 1714990000000
}
```

`fieldValues` are capped to 64 keys. Keys longer than 64 characters are ignored, and values are stored as strings capped to 64 characters. Send `"fieldValues": null` to clear the field values.

### POST /api/v1/boards/:id/cards/:cardId/comments

Adds a comment to a card. The author is the API key owner.

```json
{
  "text": "@alice can you take a look at this?",
  "revision": 1714990000000
}
```

Regular comments are capped at 3,000 characters. A request with `"kind": "docucomment"` creates a longer document-style comment capped at 15,000 characters.

On organisation boards, `@username` mentions create in-app mention notifications for matching org members who can view the board.

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

---

## Board Plugin API

The Board Plugin API uses bearer auth and either `plugin:checklist` or `boards:write` scope.

### GET /api/v1/plugin/access-level

Capability probe used by plugin and in-product UI. With bearer auth, the response reflects the token scopes. With a logged-in web session, the response reflects the user's tier and organisations.

### GET /api/v1/plugin/boards/:id

Returns only the board/list/card/checklist shape needed by plugin clients.

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

Toggles one checklist item.

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
}
```

### BoardCard

```ts
interface BoardCard {
  id: string;
  kind?: 'filler' | string;
  ticket?: string;
  title: string;
  categoryId?: string;
  severity?: string; // legacy fallback only
  description?: string;
  descriptionMode?: 'plain' | 'markdown' | 'fields';
  fieldValues?: Record<string, string>;
  labels?: Array<{ id?: string; name: string; color?: string; twoTone?: boolean; borderColor?: string }>;
  assignees?: string[];
  comments?: Array<{
    id: string;
    author: string;
    authorSub: string;
    text: string;
    ts: number;
    kind?: 'docucomment' | 'comment';
  }>;
  checklist?: {
    items: Array<{ id?: string; text: string; done: boolean }>;
  };
  attachments?: Array<{ id?: string; name: string; url: string }>;
  due?: { iso?: string; in?: string; overdue?: boolean } | null;
  image?: { data: string; w: number; h: number; bytes: number } | null;
  components?: Record<string, boolean>;
}
```

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

If supplied, `revision` must equal the board's current `updated_at` value. A mismatch returns:

```json
{
  "error": "revision_conflict",
  "message": "Board was updated after the revision supplied with this request.",
  "currentRevision": 1715012345678
}
```

Recommended flow:

1. `GET /api/v1/boards/:id`
2. Store `board.revision`
3. Send the write with that `revision`
4. On `409`, refetch and retry after merging your intended change

---

## Rate Limits and Quotas

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
| `board_scope_violation` | 403 | Board key used on a different board |
| `profile_scope_violation` | 403 | Profile key used on an org board |
| `org_scope_violation` | 403 | Org key used outside its organisation |
| `plugin_not_supported_for_org_tokens` | 403 | Org key used on plugin endpoint |
| `forbidden` | 403 | User cannot access the board |
| `not_found` | 404 | Board or token not found |
| `list_not_found` | 404 | List not found |
| `card_not_found` | 404 | Card not found |
| `item_not_found` | 404 | Checklist item not found |
| `no_checklist` | 404 | Plugin toggle target card has no checklist |
| `revision_conflict` | 409 | Stale write revision |
| `list_exists` | 409 | Client-supplied list id already exists |
| `card_exists` | 409 | Client-supplied card id already exists |
| `card_rate_limited` | 429 | Too many cards created in the burst window |
| `invalid_data` | 400 | Whole-board replacement payload is invalid |
| `invalid_card_patch` | 400 | Card patch payload failed validation |
| `invalid_type` | 400 | Token creation type was not `programmatic` or `plugin` |
| `name_required` | 400 | Token/list/card name or title was empty after sanitisation |
| `text_required` | 400 | Comment text was empty or rejected |
| `gone` | 410 | Legacy `POST /api/tokens` or `DELETE /api/tokens/:id` was called |

---

## Audit Logging and Mentions

On organisation and sub-organisation boards:

- Programmatic mutations are recorded in the board audit log.
- The actor is the API key owner for profile and board keys.
- Organisation key creation and revocation are recorded in the organisation audit log.
- Comment mentions (`@username`) create notification rows for matching org members who can view the board.
- Plugin checklist toggles on org boards are also audit logged.

Personal boards do not write organisation audit entries.

---

## Examples

See the [`Examples/`](./Examples) directory:

- [`curl-basic.sh`](./Examples/curl-basic.sh) - minimal auth, board fetch, list/card/comment flow
- [`node-full-flow.js`](./Examples/node-full-flow.js) - Node.js 18+ flow with conflict retry, card patching, and move
- [`python-client.py`](./Examples/python-client.py) - Python `requests` client with field value patching and retries
- [`github-action-sync.yml`](./Examples/github-action-sync.yml) - GitHub Actions issue-to-card workflow

---

## Security Best Practices

1. Treat API keys like passwords. A Programmatic Board API key with write scope can mutate every board in its reach.
2. Prefer the narrowest reach that works: board key before profile or organisation key.
3. Never commit keys to git. Use environment variables, GitHub Actions secrets, or a secrets manager.
4. Rotate and revoke unused keys.
5. Watch `last_used_at` in token lists.
6. Use HTTPS only.
7. Scan logs and `.env` files for the `jkb_` prefix before sharing them.

---

## License

Jokelboard is proprietary commercial software. All rights reserved.

Documentation, examples, and API access are provided solely to customers with valid paid subscriptions in accordance with Jokelboard's terms of service. Unauthorized reproduction, modification, or distribution is prohibited.
