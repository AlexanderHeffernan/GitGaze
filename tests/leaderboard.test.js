import test from 'node:test';
import assert from 'node:assert/strict';

// A fake native shell: an organisation of 23 members whose contribution queries time out once.
const people = Array.from({ length: 23 }, (_, i) => ({ id: `U${i}`, login: `m${i}`, name: '', avatarUrl: '' }));
const batches = [];
let timeouts = 1;
globalThis.__TAURI__ = { core: { invoke: async (command, { query, variables } = {}) => {
  if (command === 'github_scopes') return 'gist, read:org, repo, workflow';
  if (query.includes('membersWithRole')) {
    const start = variables.after ? Number(variables.after) : 0, nodes = people.slice(start, start + 20);
    return { organization: { membersWithRole: { totalCount: people.length, nodes, pageInfo: { hasNextPage: start + 20 < people.length, endCursor: String(start + 20) } } } };
  }
  if (timeouts-- > 0) throw new Error('GitHub returned HTTP 502. Try again shortly.');
  batches.push(variables.ids.length);
  return { nodes: variables.ids.map(id => ({ id, contributionsCollection: { totalCommitContributions: Number(id.slice(1)), totalIssueContributions: 1, totalPullRequestContributions: 0, totalPullRequestReviewContributions: 2 } })) };
} } };
const { rank, periodStart, standings } = await import('../ui/js/leaderboard.js');

test('ties share a rank and the next rank skips past them', () => {
  const rows = rank([{ login: 'b', count: 5 }, { login: 'c', count: 9 }, { login: 'A', count: 5 }, { login: 'd', count: 0 }]);
  assert.deepEqual(rows.map(r => [r.login, r.rank]), [['c', 1], ['A', 2], ['b', 2], ['d', 4]]);
});

test('periods start at local calendar boundaries, with Monday weeks', () => {
  const now = new Date(2026, 10, 25, 15, 30); // Wednesday 25 November 2026
  const local = iso => { const d = new Date(iso); return [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getHours()]; };
  assert.deepEqual(local(periodStart('today', now)), [2026, 11, 25, 0]);
  assert.deepEqual(local(periodStart('week', now)), [2026, 11, 23, 0]);
  assert.deepEqual(local(periodStart('week', new Date(2026, 10, 29, 9))), [2026, 11, 23, 0]); // Sunday
  assert.deepEqual(local(periodStart('month', now)), [2026, 11, 1, 0]);
  assert.deepEqual(local(periodStart('year', now)), [2026, 1, 1, 0]);
});

test('counts every member in small batches and retries GitHub timeouts', async () => {
  const result = await standings({ login: 'acme', id: 'O1' }, 'year', new Date(2026, 10, 25), 10, 2);
  assert.deepEqual(batches.sort(), [10, 10, 3]);
  assert.equal(result.rows.length, 23);
  assert.equal(result.partial, false);
  assert.deepEqual(result.rows.slice(0, 2).map(r => [r.login, r.count, r.rank]), [['m22', 25, 1], ['m21', 24, 2]]);
  assert.equal(result.rows.at(-1).count, 3);
  assert.equal(result.privateHidden, true); // The CLI's default scopes hide private work.
});
