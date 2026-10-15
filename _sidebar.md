- [Overview](README.md#overview)
- [Quick Start](README.md#quick-start)
- [Access Requirements](README.md#access-requirements)
  - [Programmatic Access](README.md#programmatic-access)
  - [Plugin Access](README.md#plugin-access)
- [Authentication](README.md#authentication)
  - [API Key Reach](README.md#api-key-reach)
  - [Managing API Keys](README.md#managing-api-keys)
  - [Official Bot Accounts](README.md#official-bot-accounts)
  - [Organisation key endpoint permissions](README.md#organisation-key-endpoint-permissions)
- [Endpoints Reference](README.md#programmatic-board-api)
  - [GET /me](README.md#get-apiv1me)
  - [Boards](README.md#get-apiv1boards)
  - [Board revision](README.md#get-apiv1boardsidrevision)
  - [Lists](README.md#post-apiv1boardsidlists)
  - [Cards](README.md#post-apiv1boardsidcards)
  - [Comments & Move](README.md#post-apiv1boardsidcardscardidcomments)
  - [Card Link](README.md#get-apiv1boardsidcardscardidlink)
  - [Vault](README.md#vault)
- [Board Plugin API](README.md#board-plugin-api)
- [Sandbox API](README.md#sandbox-api)
  - [Sandbox tokens](README.md#sandbox-tokens)
  - [Forcing a failure](README.md#forcing-a-failure-x-sandbox-scenario)
  - [What it does not prove](README.md#what-a-green-sandbox-run-does-not-prove)
- [Data Model](README.md#data-model)
- [Revisions & Concurrency](README.md#optimistic-concurrency-and-revisions)
- [Rate Limits](README.md#rate-limits-and-quotas)
- [Error Handling](README.md#error-handling)
- [Audit & Mentions](README.md#audit-logging-and-mentions)
- [Examples](README.md#examples)
- [Security Best Practices](README.md#security-best-practices)
- [License](README.md#license)

---

**Examples**

- [Examples README](Examples/README.md)
- [curl-basic.sh](https://github.com/Jokelboard/JokelboardAPI/blob/main/Examples/curl-basic.sh)
- [vault-flow.sh](https://github.com/Jokelboard/JokelboardAPI/blob/main/Examples/vault-flow.sh)
- [node-full-flow.js](https://github.com/Jokelboard/JokelboardAPI/blob/main/Examples/node-full-flow.js)
- [python-client.py](https://github.com/Jokelboard/JokelboardAPI/blob/main/Examples/python-client.py)
- [github-action-sync.yml](https://github.com/Jokelboard/JokelboardAPI/blob/main/Examples/github-action-sync.yml)
- [plugin-checklist.sh](https://github.com/Jokelboard/JokelboardAPI/blob/main/Examples/plugin-checklist.sh)
- [sandbox-smoke.sh](https://github.com/Jokelboard/JokelboardAPI/blob/main/Examples/sandbox-smoke.sh)
- [node-sandbox-resilience.js](https://github.com/Jokelboard/JokelboardAPI/blob/main/Examples/node-sandbox-resilience.js)

---

**Live API**

- [https://api.jokelboard.com/api/v1](https://api.jokelboard.com/api/v1)
- [https://api.jokelboard.com/api/sandbox/v1](https://api.jokelboard.com/api/sandbox/v1) (sandbox, no key needed)
