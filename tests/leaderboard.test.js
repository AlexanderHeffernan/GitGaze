import test from 'node:test';
import assert from 'node:assert/strict';

// A fake native shell: an organisation of 23 members. Member mN has made N commits, one pull
// request and two reviews, whichever way they are counted; the first heavy query times out.
const people = Array.from({ length: 23 }, (_, i) => ({ id: `U${i}`, login: `m${i}`, name: '', avatarUrl: '' }));
const commits = id => Number(id.slice(1));
let scopes, timeouts, calls;
globalThis.__TAURI__ = { core: { invoke: async (command, { query, variables } = {}) => {
  if (command === 'github_scopes') return scopes;
  if (query.includes('membersWithRole')) {
    const start = variables.after ? Number(variables.after) : 0, nodes = people.slice(start, start + 20);
    return { organization: { membersWithRole: { totalCount: people.length, nodes, pageInfo: { hasNextPage: start + 20 < people.length, endCursor: String(start + 20) } } } };
  }
  if (query.includes('repositories(')) {
    calls.push('repositories');
    return { organization: { repositories: { pageInfo: { hasNextPage: true, endCursor: 'next' }, nodes: [
      { name: 'busy', pushedAt: '2026-11-20T00:00:00Z', defaultBranchRef: { id: 'R1' } },
      { name: 'empty', pushedAt: '2026-11-21T00:00:00Z', defaultBranchRef: null },
      { name: 'idle', pushedAt: '2020-01-01T00:00:00Z', defaultBranchRef: { id: 'R2' } }] } } };
  }
  if (timeouts-- > 0) throw new Error('GitHub returned HTTP 502. Try again shortly.');
  if (query.includes('contributionsCollection')) {
    calls.push(`contributions:${variables.ids.length}`);
    return { nodes: variables.ids.map(id => ({ id, contributionsCollection: { totalCommitContributions: commits(id), totalIssueContributions: 0, totalPullRequestContributions: 1, totalPullRequestReviewContributions: 2 } })) };
  }
  if (query.includes('history(')) {
    const authors = [...query.matchAll(/(a\d+): history\(since:\$from, until:\$to, author:\{id:"(U\d+)"\}\)/g)];
    calls.push(`history:${variables.name}:${authors.length}`);
    return { repository: { defaultBranchRef: { target: Object.fromEntries(authors.map(([, alias, id]) => [alias, { totalCount: commits(id) }])) } } };
  }
  const searches = [...query.matchAll(/(s\d+): search\(type:ISSUE, first:0, query:"org:acme is:(\w+) ([\w-]+):m\d+ created:\S+\+00:00\.\.\S+\+00:00"\)/g)];
  calls.push(`search:${searches.length}`);
  return Object.fromEntries(searches.map(([, alias, kind, qualifier]) => [alias, { issueCount: qualifier === 'reviewed-by' ? 2 : kind === 'pr' ? 1 : 0 }]));
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

for (const [label, tokenScopes] of [['GitHub’s exact counts with read:user', 'gist, read:org, read:user, repo'], ['the repositories without it', 'gist, read:org, repo, workflow']]) {
  test(`ranks every member from ${label}, retrying GitHub timeouts`, async () => {
    scopes = tokenScopes; timeouts = 1; calls = [];
    const result = await standings({ login: 'acme', id: 'O1' }, 'year', new Date(2026, 10, 25), 10, 2);
    assert.equal(result.exact, tokenScopes.includes('read:user'));
    assert.equal(result.rows.length, 23);
    assert.equal(result.partial, false);
    assert.deepEqual(result.rows.slice(0, 2).map(r => [r.login, r.count, r.rank]), [['m22', 25, 1], ['m21', 24, 2]]);
    assert.equal(result.rows.at(-1).count, 3);
    if (result.exact) assert.deepEqual(calls.sort(), ['contributions:10', 'contributions:10', 'contributions:3']);
    // Only the active repository with a default branch is read, ten authors at a time, and
    // listing stops at the first repository pushed before the period.
    else assert.deepEqual(calls.sort(), ['history:busy:10', 'history:busy:10', 'history:busy:3', 'repositories', 'search:23', 'search:23', 'search:23']);
  });
}
