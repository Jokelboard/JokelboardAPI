# Board API Usage Examples

This directory contains language- and tool-specific examples for the Jokelboard Board API v1.

All examples are **self-contained** — they use only standard library HTTP clients or very common packages (requests, curl, jq). None of them import or depend on any code from the main Jokelboard repository.

## Quick Start

1. Create an API key from one of the current key-management surfaces:
   - Board key: board **Automations** menu, or `POST /api/v1/boards/:id/tokens`
   - Profile key: **User Settings -> Security -> API Keys**, or `POST /api/me/tokens`
   - Organisation key: organisation **API Keys** tab, or `POST /api/organisations/:id/tokens`
2. For an organisation automation that should appear as an official bot, configure the key from the **API Keys** tab or `PATCH /api/organisations/:id/tokens/:tokenId/bot`. This changes attribution, not scopes or reach.
3. Copy the secret **immediately** — it is shown only once.
4. Export the token and a board ID:

   ```bash
   export JKB_TOKEN="jkb_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
   export BOARD_ID="board-abc123def456"
   ```

5. Run the example of your choice.

## Examples

| File                        | Language / Tool          | What it demonstrates                              | Requirements          |
|-----------------------------|--------------------------|---------------------------------------------------|-----------------------|
| `curl-basic.sh`             | bash + curl + jq         | Auth check, list boards, create list+card+comment | curl, jq, bash        |
| `vault-flow.sh`             | bash + curl + jq         | List, vault, restore, and purge soft-deleted cards | curl, jq, bash        |
| `node-full-flow.js`         | Node.js 18+ (native fetch) | Bot-aware identity, revision retry, PATCH, MOVE, bulk import | Node 18+             |
| `python-client.py`          | Python 3 + requests      | CSV-style import, fieldValues + descriptionMode=fields, 409 handling | `pip install requests` |
| `github-action-sync.yml`    | GitHub Actions           | React to `issues` webhooks, create cards, resolve the card's shareable link | A GitHub repo with Actions + two secrets |
| `plugin-checklist.sh`       | bash + curl + jq         | Board Plugin API: access probe, checklist summary, item toggle | curl, jq, bash, `plugin:checklist` key |

## Tips for Writing Your Own Client

- Always send the latest `revision` on mutating calls to avoid 409s. `GET /api/v1/boards/:id/revision` is the cheap probe.
- Handle `429 rate_limited` (HTTP budget) and `429 card_rate_limited` (card-create burst). Honour `RateLimit-*` / `retryAfter`.
- Repeat GETs with `If-None-Match` from the previous `ETag`. Unchanged boards return 304.
- Use `?projection=cards` when you do not need comments, attachments, or cover images.
- On organisation boards, every write appears in the audit log. A configured organisation bot key appears as `actor_bot`, while the human key creator remains attached for accountability.
- `GET /api/v1/me` keeps the human creator in `user` and exposes the optional official identity in `token.bot`.
- Bot-authored comments are server-stamped with the bot identity. Cards created without `assignees` default to unassigned for bot keys.
- Use the narrowest key reach that works: board key before profile or organisation key.
- Use `categoryId` for the card category. `severity` is still accepted as a legacy alias.
- Set custom `fieldValues` with `PATCH /api/v1/boards/:id/cards/:cardId`; card creation does not apply them. Values are stored as strings (max 64 characters each, 64 keys per card).
- Set `dateType` to `due` for deadlines, `static` for neutral dates, or `employee` with `dueJoin`/`dueDepart` for employment dates. Switching modes preserves the other stored dates.
- The `ticket` field on cards is a short human-friendly identifier (e.g. `PROD-1842`). It is generated server-side if you omit it.
- Plugin keys (`plugin:checklist`) only work with the `/api/v1/plugin/*` endpoints, and organisation-owned keys cannot use the Plugin API at all.

## Need an SDK?

None exist yet. The API is deliberately small and stable, so most teams just use the HTTP client built into their language.

Happy automating!
