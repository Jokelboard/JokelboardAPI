#!/usr/bin/env node
/**
 * node-full-flow.js
 *
 * Complete Board API demonstration in modern Node.js (no external deps).
 * Works with Node 18+ (global fetch + AbortController).
 *
 * Usage:
 *   JKB_TOKEN=jkb_xxx BOARD_ID=board-xxx node node-full-flow.js
 *
 * The script performs a realistic automation flow:
 *   - Auth check
 *   - Find or create a list called "CI / Automation"
 *   - Create several cards from an external data source (simulated)
 *   - Update one card (PATCH)
 *   - Move a card to another list
 *   - Handle 409 revision conflicts with automatic retry
 */

const BASE = 'https://jokelboard.com/api/v1';

const token = process.env.JKB_TOKEN;
const boardId = process.env.BOARD_ID;

if (!token || !boardId) {
  console.error('Usage: JKB_TOKEN=jkb_... BOARD_ID=board-... node node-full-flow.js');
  process.exit(1);
}

const headers = {
  'Authorization': `Bearer ${token}`,
  'Content-Type': 'application/json',
  'User-Agent': 'JokelboardAPI-Example/1.0 (node)',
};

async function api(path, opts = {}) {
  const res = await fetch(`${BASE}${path}`, {
    ...opts,
    headers: { ...headers, ...(opts.headers || {}) },
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(body.message || body.error || `HTTP ${res.status}`);
    err.status = res.status;
    err.body = body;
    throw err;
  }
  return body;
}

async function getBoardWithRetry() {
  // Simple helper that always returns the latest board payload
  const { board } = await api(`/boards/${boardId}`);
  return board;
}

async function findOrCreateList(board, title) {
  let list = board.data.lists.find(l => l.title === title);
  if (list) return list;

  const { list: created } = await api(`/boards/${boardId}/lists`, {
    method: 'POST',
    body: JSON.stringify({ title }),
  });
  return created;
}

async function createCardWithRevision(listId, cardData, currentRevision) {
  // Demonstrates sending the revision for optimistic concurrency
  const body = { listId, ...cardData, revision: currentRevision };
  try {
    return await api(`/boards/${boardId}/cards`, { method: 'POST', body: JSON.stringify(body) });
  } catch (e) {
    if (e.status === 409 && e.body?.error === 'revision_conflict') {
      console.log('  [!] Revision conflict — refetching board...');
      const fresh = await getBoardWithRetry();
      // Retry once with latest revision (real apps should have merge logic)
      const retryBody = { listId, ...cardData, revision: fresh.revision };
      return api(`/boards/${boardId}/cards`, { method: 'POST', body: JSON.stringify(retryBody) });
    }
    throw e;
  }
}

async function main() {
  console.log('=== Jokelboard Board API — Node.js Full Flow ===\n');

  // 1. Verify identity
  const me = await api('/me');
  console.log(`Authenticated as ${me.user.username} (${me.user.tier}) via token "${me.token.name}"`);
  console.log(`Token scopes: ${me.token.scopes.join(', ')}\n`);

  // 2. Get current board state
  let board = await getBoardWithRetry();
  console.log(`Board: ${board.name} (revision ${board.revision})`);
  console.log(`Lists: ${board.data.lists.length}, Cards: ${board.data.lists.reduce((n, l) => n + (l.cards?.length || 0), 0)}\n`);

  // 3. Ensure we have an "CI / Automation" list
  const ciList = await findOrCreateList(board, 'CI / Automation');
  console.log(`Using list: ${ciList.title} (${ciList.id})\n`);

  // 4. Simulate incoming work items (e.g. from GitHub Issues, Linear, PagerDuty, etc.)
  const incomingItems = [
    { title: '[CI] Deploy to staging failed', severity: 'P1', description: 'Pipeline #4821 errored on step "e2e"' },
    { title: 'Add rate-limit headers to public API', severity: 'P2' },
    { title: 'Update privacy policy link in footer', severity: 'P3' },
  ];

  for (const item of incomingItems) {
    const payload = {
      title: item.title,
      severity: item.severity || 'P2',
      description: item.description || '',
      descriptionMode: 'plain',
      labels: [{ name: 'ci', color: '#ff9f1c' }],
      assignees: [me.user.sub],
    };
    const { card } = await createCardWithRevision(ciList.id, payload, board.revision);
    console.log(`  + Created card: ${card.title} (${card.id})`);
    board = await getBoardWithRetry(); // keep revision fresh
  }

  // 5. PATCH the first card we created (raise severity + add checklist)
  const firstCard = ciList.cards?.[ciList.cards.length - 3]; // rough index
  if (firstCard) {
    console.log(`\nPatching card ${firstCard.id}...`);
    const patch = {
      severity: 'P0',
      checklist: {
        items: [
          { text: 'Re-run failed job with --debug', done: false },
          { text: 'Notify on-call via Discord', done: true },
        ],
      },
      revision: board.revision,
    };
    const { card: patched } = await api(`/boards/${boardId}/cards/${firstCard.id}`, {
      method: 'PATCH',
      body: JSON.stringify(patch),
    });
    console.log(`  ✓ Severity now ${patched.severity}, checklist items: ${patched.checklist?.items?.length || 0}`);
    board = await getBoardWithRetry();
  }

  // 6. Move the last created card to a "Done" list (create if missing)
  let doneList = board.data.lists.find(l => l.title.toLowerCase().includes('done'));
  if (!doneList) {
    const { list: created } = await api(`/boards/${boardId}/lists`, {
      method: 'POST',
      body: JSON.stringify({ title: 'Done (API)' }),
    });
    doneList = created;
  }

  const lastCardId = board.data.lists
    .find(l => l.id === ciList.id)?.cards?.slice(-1)[0]?.id;

  if (lastCardId) {
    console.log(`\nMoving card ${lastCardId} → ${doneList.title}...`);
    await api(`/boards/${boardId}/cards/${lastCardId}/move`, {
      method: 'POST',
      body: JSON.stringify({ toListId: doneList.id, position: 0, revision: board.revision }),
    });
    console.log('  ✓ Card moved to top of Done list');
  }

  console.log('\n✅ Flow complete. Refresh the board in the Jokelboard UI to see changes.');
  console.log('   (On org boards you will also see audit log entries for every mutation.)');
}

main().catch(err => {
  console.error('\n❌ Error:', err.message);
  if (err.body) console.error('Server response:', JSON.stringify(err.body, null, 2));
  process.exit(1);
});
