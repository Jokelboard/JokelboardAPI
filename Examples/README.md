# Board API Usage Examples

This directory contains language- and tool-specific examples for the Jokelboard Board API v1.

All examples are **self-contained** — they use only standard library HTTP clients or very common packages (requests, curl, jq). None of them import or depend on any code from the main Jokelboard repository.

## Quick Start

1. Create an API key from one of the current key-management surfaces:
   - Board key: board **Automations** menu, or `POST /api/v1/boards/:id/tokens`
   - Profile key: **User Settings -> Security -> API Keys**, or `POST /api/me/tokens`
   - Organisation key: organisation **API Keys** tab, or `POST /api/organisations/:id/tokens`
2. Copy the secret **immediately** — it is shown only once.
3. Export the token and a board ID:

   ```bash
   export JKB_TOKEN="jkb_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
   export BOARD_ID="board-abc123def456"
   ```

4. Run the example of your choice.

## Examples

| File                        | Language / Tool          | What it demonstrates                              | Requirements          |
|-----------------------------|--------------------------|---------------------------------------------------|-----------------------|
| `curl-basic.sh`             | bash + curl + jq         | Auth check, list boards, create list+card+comment | curl, jq, bash        |
| `node-full-flow.js`         | Node.js 18+ (native fetch) | Full flow with revision retry, PATCH, MOVE, bulk import | Node 18+             |
| `python-client.py`          | Python 3 + requests      | CSV-style import, fieldValues + descriptionMode=fields, 409 handling | `pip install requests` |
| `github-action-sync.yml`    | GitHub Actions           | React to `issues` webhooks and create cards automatically | A GitHub repo with Actions + two secrets |
| `plugin-checklist.sh`       | bash + curl + jq         | Board Plugin API: access probe, checklist summary, item toggle | curl, jq, bash, `plugin:checklist` key |

## Tips for Writing Your Own Client

- Always send the latest `revision` on mutating calls to avoid 409s.
- Handle `429 card_rate_limited` with the `retryAfter` value.
- On organisation boards, every write appears in the audit log.
- Use the narrowest key reach that works: board key before profile or organisation key.
- Use `categoryId` for the card category. `severity` is still accepted as a legacy alias.
- Set custom `fieldValues` with `PATCH /api/v1/boards/:id/cards/:cardId`; card creation does not apply them. Values are stored as strings (max 64 characters each, 64 keys per card).
- The `ticket` field on cards is a short human-friendly identifier (e.g. `PROD-1842`). It is generated server-side if you omit it.
- Plugin keys (`plugin:checklist`) only work with the `/api/v1/plugin/*` endpoints, and organisation-owned keys cannot use the Plugin API at all.

## Need an SDK?

None exist yet. The API is deliberately small and stable, so most teams just use the HTTP client built into their language.

Happy automating!
