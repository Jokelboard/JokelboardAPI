#!/usr/bin/env node
/**
 * node-sandbox-resilience.js
 *
 * Does your client survive the failures a real integration meets? This script
 * runs a small client (retry on 409, honour 429 Retry-After, tolerate non-JSON
 * errors, never retry a 400) against the Sandbox API and forces each failure
 * with the X-Sandbox-Scenario header. Replace `createCard` with your own
 * wrapper to test it.
 *
 * Node 18+ (global fetch). No key, paid plan, or dependencies needed.
 *
 *   node node-sandbox-resilience.js
 *   JKB_BASE_URL=http://localhost:3000/api/sandbox/v1 node node-sandbox-resilience.js
 *
 * Exits non-zero if any check fails, so it also works as a CI step.
 *
 * The scenario header applies to ONE request: send it on the first attempt only
 * and omit it on the retry, which is how a retry path gets exercised.
 */

const BASE = process.env.JKB_BASE_URL || 'https://api.jokelboard.com/api/sandbox/v1';
const TOKEN = 'jkb_sandbox_full'; // a public sandbox token, not a secret
const BOARD = 'sbx-personal';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// One HTTP call. Never assumes the body is JSON: a 500 is plain text, a 502 is HTML.
async function http(method, path, body, extraHeaders = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      'Content-Type': 'application/json',
      ...extraHeaders,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* plain text or HTML */ }
  return { status: res.status, headers: res.headers, json, text };
}

// ---- The client under test ------------------------------------------------
// `firstAttemptScenario` only exists to make the first attempt fail on purpose.
async function createCard(title, { firstAttemptScenario } = {}) {
  const statuses = [];
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    // Always send the freshest revision, so a retry after a 409 uses a new one.
    const { json: probe } = await http('GET', `/boards/${BOARD}/revision`);
    const scenario = attempt === 1 && firstAttemptScenario
      ? { 'X-Sandbox-Scenario': firstAttemptScenario }
      : {};
    const res = await http('POST', `/boards/${BOARD}/cards`,
      { listId: 'sbx-list-done', title, revision: probe.revision }, scenario);
    statuses.push(res.status);

    if (res.status === 201) return { ok: true, card: res.json.card, statuses };
    if (res.status === 409 && res.json?.error === 'revision_conflict') continue; // re-read, retry
    if (res.status === 429) {
      // Demo only: wait at most 1 s. A real client sleeps the full Retry-After.
      await sleep(Math.min(Number(res.headers.get('retry-after') || 1), 1) * 1000);
      continue;
    }
    // Anything else is not retryable. Report it without assuming JSON.
    const error = res.json?.error ?? `non-JSON response (${res.headers.get('content-type')})`;
    return { ok: false, status: res.status, error, statuses };
  }
  return { ok: false, error: 'gave up after 3 attempts', statuses };
}

// ---- The checks -----------------------------------------------------------
const checks = [];
function check(name, passed, detail) {
  checks.push(passed);
  console.log(`${passed ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

async function main() {
  let r = await createCard('Plain create');
  check('happy path creates the card first time', r.ok && same(r.statuses, [201]), r.statuses);

  r = await createCard('After a conflict', { firstAttemptScenario: 'revision_conflict' });
  check('409 revision_conflict: refetch and retry', r.ok && same(r.statuses, [409, 201]), r.statuses);

  r = await createCard('After a throttle', { firstAttemptScenario: 'rate_limited' });
  check('429 rate_limited: back off, then retry', r.ok && same(r.statuses, [429, 201]), r.statuses);

  r = await createCard('After a burst limit', { firstAttemptScenario: 'card_rate_limited' });
  check('429 card_rate_limited: back off, then retry', r.ok && same(r.statuses, [429, 201]), r.statuses);

  r = await createCard('Server crash', { firstAttemptScenario: 'server_error' });
  check('500 plain text: reported, no JSON.parse crash', !r.ok && r.status === 500 && /non-JSON/.test(r.error), `${r.status}, ${r.error}`);

  r = await createCard('Proxy error', { firstAttemptScenario: 'bad_gateway' });
  check('502 HTML: reported, no JSON.parse crash', !r.ok && r.status === 502 && /non-JSON/.test(r.error), `${r.status}, ${r.error}`);

  r = await createCard('Hi <@123456789>');
  check('400 title_required is permanent: not retried', !r.ok && r.error === 'title_required' && same(r.statuses, [400]), r.error);

  const failed = checks.filter((passed) => !passed).length;
  console.log(failed ? `\n${failed} check(s) failed.` : '\nAll checks passed.');
  return failed ? 1 : 0;
}

main().then((code) => process.exit(code), (err) => {
  console.error(err);
  process.exit(1);
});
