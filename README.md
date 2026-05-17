# JokelboardAPI

**Official documentation and examples for the Jokelboard Board API (v1).**

The Board API allows external applications, scripts, CI/CD pipelines, automation tools, and AI agents to programmatically read from and write to Jokelboard boards over HTTPS using simple REST endpoints secured by personal access tokens.

- **Live API Base URL**: `https://jokelboard.com/api/v1`
- **Status**: Stable (production-ready since 2026)

---

## Table of Contents

- [Overview](#overview)
- [Access Requirements](#access-requirements)
- [Authentication](#authentication)
  - [Creating Tokens](#creating-tokens)
  - [Using Tokens with the v1 API](#using-tokens-with-the-v1-api)
- [Endpoints Reference](#endpoints-reference)
- [Data Model](#data-model)
- [Optimistic Concurrency & Revisions](#optimistic-concurrency--revisions)
- [Rate Limits & Guards](#rate-limits--guards)
- [Error Handling](#error-handling)
- [Audit Logging & Mentions (Org Boards)](#audit-logging--mentions-org-boards)
- [Examples](#examples)
- [Security Best Practices](#security-best-practices)
- [License](#license)

---

## Overview

The Board API surface consists of two parts:

1. **Token Management** (`/api/tokens`) — requires an active web session (cookie auth). Used to create, list, and revoke API tokens.
2. **Board Operations** (`/api/v1/*`) — stateless Bearer token authentication. Provides read/write access to boards you have permission to access.

All v1 endpoints return JSON. Write operations are validated against your plan's quotas and the board's current state.

Supported operations:
- List your accessible boards
- Fetch full board state (lists + cards + metadata)
- Replace entire board data (PUT)
- Create lists and cards
- Patch individual cards (title, description, labels, checklist, due date, assignees, severity, attachments, custom fieldValues, descriptionMode)
- Post comments to cards
- Move cards between lists (with position control)

The API is intentionally minimal and JSON-first so it can be used from curl, any language's HTTP client, or low-level automation without SDKs.

---

## Access Requirements

### Personal Accounts
- **Ultra** tier (or higher) is required for `apiAccess`.
- Lower personal tiers (FREE, PREFERRED, PLUS, PRO) cannot create or use Board API tokens.

### Organisation Accounts
- The organisation must be on one of the following tiers (all include apiAccess):
  - **FL_PRO**
  - **BUSINESS**
  - **SME_BUSINESS**
  - **ENTERPRISE**
- Additionally, the user (or a role they belong to) must hold the **`USE_BOARD_API`** organisation permission.
- Organisation owners can grant this permission via custom roles in the Enterprise / Org admin panel.

If a user lacks access, the server returns `403` with `error: "api_access_blocked"` when attempting to create a token or call a v1 endpoint.

Tokens created while on a qualifying plan continue to work even if the account temporarily lapses (until the token is revoked), but new tokens cannot be minted until access is restored.

---

## Authentication

### Token Format
- Prefix: `jkb_` (e.g. `jkb_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`)
- 32 random bytes, base64url encoded after the prefix.
- Stored server-side only as a SHA-256 hash. The raw secret is shown **exactly once** at creation time.

### Scopes
Tokens can be created with one or both scopes:
- `boards:read` — list boards, fetch board data
- `boards:write` — all read operations + create/edit/move cards, lists, comments, full board replacement

Default when creating via UI: both scopes.

### Creating Tokens

#### Recommended: In-Product UI
1. Open any board you own or have write access to.
2. Click the lightning-bolt ⚡ (Automations) menu in the topbar.
3. Choose **"Board API…"**
4. (If your plan does not qualify you will see an upgrade card instead.)
5. Give the token a name, select scopes, and click **Create**.
6. **Immediately copy the secret** — it is never shown again.

The modal also shows existing tokens (with prefix preview) so you can revoke old ones.

#### Programmatic Token Creation (Web Session Required)
Use a logged-in browser session (or scrape the session cookie) to call:

```
POST /api/tokens
Content-Type: application/json
{
  "name": "CI Deploy Bot",
  "scopes": ["boards:read", "boards:write"]
}
```

Response (201):
```json
{
  "token": "jkb_...",
  "tokenPreview": "jkb_xxxxxxxx",
  "apiToken": {
    "id": "tok_...",
    "name": "CI Deploy Bot",
    "tokenPrefix": "jkb_xxxxxxxx",
    "scopes": ["boards:read", "boards:write"],
    "created_at": 1715...,
    "last_used_at": null
  }
}
```

The `token` value is the only time the secret is returned.

### Using Tokens with the v1 API

All `/api/v1/...` requests must include:

```
Authorization: Bearer jkb_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

No cookies or other auth are accepted for v1 routes. Example:

```bash
curl -H 'Authorization: Bearer jkb_...' \
     https://jokelboard.com/api/v1/me
```

---

## Endpoints Reference

### GET /api/v1/me
Returns the authenticated user and the token metadata.

**Response 200**
```json
{
  "user": {
    "sub": "roblox-...",
    "username": "dylanjkl",
    "displayName": "Dylan",
    "picture": "https://...",
    "tier": "ULTRA"
  },
  "token": {
    "id": "tok_...",
    "name": "My Script",
    "tokenPrefix": "jkb_abc123",
    "scopes": ["boards:read", "boards:write"],
    "created_at": 1715000000000,
    "last_used_at": 1715012345678
  }
}
```

### GET /api/v1/boards
Lists all boards the token's owner can access via the API (personal boards + org boards where the user has at least read access + the org has apiAccess + the USE_BOARD_API perm).

**Response 200**
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
Fetches the complete board, including the full `data` object (lists, cards, presets, etc.).

**Response 200**
```json
{
  "board": {
    "id": "board-abc123",
    "workspace": "org:org-xyz",
    "name": "Production Incidents",
    "title": "Production Incidents",
    "created_at": ...,
    "updated_at": ...,
    "revision": ...,
    "url": "/api/v1/boards/board-abc123",
    "data": {
      "title": "Production Incidents",
      "lists": [ /* ... */ ],
      "presets": { /* labels, checklists, fields, card templates */ }
    }
  }
}
```

### PUT /api/v1/boards/:id
**Replaces the entire board data.** This is the primary "save" mechanism for bulk edits.

**Request body**
```json
{
  "revision": 1714990000000,   // optional but strongly recommended
  "data": {
    "title": "New Board Title",
    "lists": [ /* full desired state */ ],
    "presets": { /* optional */ }
  }
}
```

**Important**:
- `data.lists` must be an array.
- The server runs the same validation and quota checks as the web UI.
- On success the response includes the updated board payload.
- See [Optimistic Concurrency](#optimistic-concurrency--revisions) below.

### POST /api/v1/boards/:id/lists
Creates a new list at the end of the board.

**Request**
```json
{
  "title": "Backlog",
  "id": "list-optional-custom-id"   // optional, server generates if omitted
}
```

**Response 201** includes the created list in the `list` field plus the updated board.

### POST /api/v1/boards/:id/cards
Creates a card inside an existing list.

**Request (minimal)**
```json
{
  "listId": "list-abc",
  "title": "Fix login redirect bug"
}
```

**Full example**
```json
{
  "listId": "list-abc",
  "id": "card-custom-id",
  "title": "Fix login redirect",
  "ticket": "INC-4821",
  "severity": "P1",
  "description": "Users on mobile get sent to the wrong domain...",
  "descriptionMode": "markdown",
  "labels": ["bug", "mobile"],
  "assignees": ["roblox-1234"],
  "due": { "iso": "2026-06-01T09:00:00Z" },
  "checklist": {
    "items": [
      { "text": "Reproduce on staging", "done": true },
      { "text": "Deploy fix", "done": false }
    ]
  },
  "attachments": [
    { "name": "screenshot.png", "url": "https://..." }
  ],
  "fieldValues": {
    "priority-score": 87,
    "component": "auth"
  }
}
```

The server auto-generates `ticket` if omitted and ensures the card ID is unique on the board.

### PATCH /api/v1/boards/:id/cards/:cardId
Partial update of a single card. Only fields present in the body are changed.

Supported patchable fields: `title`, `description`, `descriptionMode`, `fieldValues`, `severity`, `labels`, `assignees`, `due`, `checklist`, `attachments`.

Example:
```json
{
  "title": "Fix login redirect (hotfix)",
  "severity": "P0",
  "labels": ["bug", "hotfix", "mobile"],
  "due": null
}
```

### POST /api/v1/boards/:id/cards/:cardId/comments
Adds a comment to a card. The author is recorded as the API token owner.

**Request**
```json
{ "text": "@alice can you take a look at the mobile flow?" }
```

Mentions (`@username`) on org boards trigger notification rows and are visible in the in-app mention inbox.

### POST /api/v1/boards/:id/cards/:cardId/move
Moves a card to another list (or reorders within the same list).

**Request**
```json
{
  "toListId": "list-backlog",
  "position": 0   // 0 = top, omitted or large number = bottom
}
```

---

## Data Model

### Board Data (`data` object)

```ts
interface BoardData {
  title?: string;
  lists: BoardList[];
  presets?: {
    labels?: Array<{id: string, name: string, color: string, twoTone?: boolean, borderColor?: string}>;
    checklists?: Array<{id: string, name: string, items: string[]}>;
    fields?: Array<{id: string, name: string, type: 'checkbox' | 'text'}>;
    cards?: { default?: {...}, templates?: [...] };
  };
  // Additional keys (theme, custom CSS tweaks, settings) are preserved.
}
```

### List

```ts
interface BoardList {
  id: string;
  title: string;
  cards: BoardCard[];
}
```

### Card

```ts
interface BoardCard {
  id: string;
  ticket?: string;                 // e.g. "PROD-1842"
  title: string;
  severity: 'P0' | 'P1' | 'P2' | 'P3' | 'P4';
  description?: string;
  descriptionMode?: 'plain' | 'markdown' | 'fields';
  fieldValues?: Record<string, boolean | string | number>;
  labels: Array<{id: string, name: string, color: string, ...}>;
  assignees: string[];             // user subs or usernames
  comments: Array<{
    id: string;
    author: string;
    authorSub: string;
    text: string;
    ts: number;
  }>;
  checklist?: {
    items: Array<{id?: string, text: string, done: boolean}>;
  };
  attachments: Array<{id?: string, name: string, url: string}>;
  due?: { iso?: string; in?: string; overdue?: boolean };
  image?: { data: string; w: number; h: number; bytes: number } | null; // cover image (base64 data URL)
  components?: Record<string, boolean>;
}
```

**Validation rules enforced on write** (same as web UI):
- Titles limited to 200 chars (cards) / 80 chars (lists)
- No control characters or `<` `>` in plain-text titles/labels (prevents injection)
- Max 50 labels per card (enforced at save)
- Image and attachment URL validation
- `descriptionMode` must be one of the three allowed values when present
- Quota checks for total cards, lists, labels, image cards, and bytes

---

## Optimistic Concurrency & Revisions

All mutating v1 endpoints (`PUT /boards/:id`, `POST /lists`, `POST /cards`, `PATCH /cards`, `POST /comments`, `POST /move`) accept an optional `revision` field in the body.

- If supplied, the server compares it to `board.updated_at`.
- On mismatch → `409 Conflict` with `{ error: "revision_conflict", currentRevision: <latest> }`
- This prevents lost updates when multiple clients/scripts edit the same board.

**Recommended pattern**:
1. `GET /api/v1/boards/:id` → store `board.revision`
2. Perform your edits locally
3. Send the mutation with `revision: <your stored value>`
4. On 409, re-fetch and retry (or merge)

The `revision` field in summaries and payloads is an alias for `updated_at` (epoch ms).

---

## Rate Limits & Guards

### Card Creation Burst Limit
To protect against runaway scripts and card spam, the API enforces:

- **10 new cards per 5 seconds per (user, board)** via the v1 surface.

When exceeded, the request is rejected with:

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

HTTP status: **429 Too Many Requests**

The guard only counts cards added in the current request batch (e.g. a single PUT that adds 11 cards will be rejected before the DB write).

Other write operations are not burst-limited beyond normal plan quotas.

### Plan Quotas
Every write is subject to the tier limits of the board's owner (personal) or organisation (org boards). Common limits include:
- `cardsPerBoard`
- `listsPerBoard`
- `labelsPerCard`
- `imageCardsPerBoard`
- `bytesPerOrganisation` (or per-sub-org depending on enterprise quota mode)

When a limit would be exceeded the server throws a typed `QuotaExceeded` error with `error` code such as `card_limit`, `list_limit`, etc., and an `upgradeHint`.

---

## Error Handling

All errors are JSON objects with at minimum `{ "error": "code", "message": "..." }`.

Common error codes:

| Code                    | HTTP | Meaning                                      | Retry? |
|-------------------------|------|----------------------------------------------|--------|
| `api_token_required`    | 401  | Missing or malformed Authorization header    | No     |
| `invalid_api_token`     | 401  | Token not found or revoked                   | No     |
| `api_scope_required`    | 403  | Token lacks required scope (`boards:read` / `boards:write`) | No |
| `api_access_blocked`    | 403  | Account/Org lacks API access or USE_BOARD_API perm | No |
| `forbidden`             | 403  | User cannot view or edit this board          | No     |
| `not_found`             | 404  | Board / list / card does not exist           | No     |
| `list_not_found`        | 404  | Target list missing                          | No     |
| `card_not_found`        | 404  | Card missing                                 | No     |
| `revision_conflict`     | 409  | Board changed since your `revision`          | Yes (refetch) |
| `card_rate_limited`     | 429  | Too many cards created in short window       | Yes (after retryAfter) |
| `invalid_data`          | 400  | `data` missing or not an object with lists array | No |
| `title_required`        | 400  | List or card title empty after sanitisation  | No     |
| `text_required`         | 400  | Comment text empty                           | No     |
| `invalid_card_patch`    | 400  | Patch contained bad values (e.g. empty title, bad descriptionMode) | No |
| `list_exists` / `card_exists` | 409 | ID collision on create (client-supplied ID) | Rare   |

When using the `revision` mechanism, always handle 409 by refetching the board.

---

## Audit Logging & Mentions (Org Boards)

- All mutations performed via the Board API on **organisation or sub-organisation boards** are recorded in the board's audit log (visible to users with `VIEW_AUDIT_LOG` permission).
- The actor is recorded as the API token owner (username + sub).
- Comment mentions (`@username`) are processed identically to the web UI: matching org members who can view the board receive an in-app mention notification.
- Personal boards do **not** write audit entries (single-author by definition).

---

## Examples

See the [`Examples/`](./Examples) directory for ready-to-run demonstrations:

- `curl-basic.sh` — minimal read + create card
- `node-full-flow.js` — Node.js script using native `fetch` (Node 18+)
- `python-client.py` — Python 3 + `requests`
- `github-action.yml` — skeleton for using the API from GitHub Actions to sync issues → Jokelboard cards

All examples are self-contained and do **not** depend on any Jokelboard source files.

---

## Security Best Practices

1. **Treat tokens like passwords.** A token with `boards:write` can fully mutate any board the owner can access.
2. **Never commit tokens** to git. Use environment variables or a secrets manager.
3. **Use the narrowest scope possible.** Many automation tasks only need `boards:read`.
4. **Rotate tokens regularly.** The UI makes revocation trivial.
5. **Monitor `last_used_at`** via the token list endpoint (web) or by watching audit logs on org boards.
6. All traffic must be HTTPS. The API rejects cleartext in production.
7. The `jkb_` prefix makes it easy to scan logs / `.env` files for accidental leaks.

---

## License

Jokelboard is proprietary commercial software. All rights reserved.

Documentation, examples, and API access are provided solely to customers with valid paid subscriptions in accordance with Jokelboard's terms of service. Unauthorized reproduction, modification, or distribution is prohibited.

---

**Maintained by the Jokelboard team.** Last updated: May 2026.
