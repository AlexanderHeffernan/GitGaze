const test = require('node:test');
const assert = require('node:assert/strict');
const { leaderboard, organizations, standings } = require('./leaderboard');
const operations = require('./operations.json');
const { preferences } = require('./core');

const at = Date.parse('2025-03-03T07:40:00Z');
const north = { id:'org-1', login:'northstar', viewerIsAMember:true };
const south = { id:'org-2', login:'tideline', viewerIsAMember:true };
const page = (nodes, endCursor = null) => ({ nodes, pageInfo:{ hasNextPage:endCursor !== null, endCursor } });
const discovery = (nodes = [north, south], next) => ({ viewer:{ login:'Viewer', organizations:page(nodes, next) } });
const roster = (org, nodes, totalCount = nodes.length, next) => ({ viewer:{ login:'Viewer' },
  organization:{ ...org, membersWithRole:{ ...page(nodes, next), totalCount } } });
const member = (login, commits, issues = 0, pulls = 0, reviews = 0) => ({ login, name:null, avatarUrl:'',
  contributionsCollection:{ totalCommitContributions:commits, totalIssueContributions:issues,
    totalPullRequestContributions:pulls, totalPullRequestReviewContributions:reviews, restrictedContributionsCount:1000 } });
const context = (query, options = {}) => ({ login:'viewer', at, signal:new AbortController().signal, query, ...options });
const good = (operation, { org }) => operation === 'leaderboardOrganizations' ? discovery() :
  org === north.id ? roster(north, [member('other', 2), member('Viewer', 1)]) : roster(south, [member('Viewer', 0)]);

test('registering the leaderboard does not change default or upgraded visible layouts', () => {
  const ids = preferences().modules;
  const registry = [...ids.map((id, i) => ({ id, hiddenByDefault:i >= 4 })), { id:'leaderboard', hiddenByDefault:true }];
  const visible = prefs => prefs.modules.filter(id => !prefs.hidden.includes(id));
  for (const saved of [{}, { modules:['records', 'heatmap', 'today'], hidden:['heatmap'], historyWeeks:26 }]) {
    const upgraded = preferences(saved, registry);
    assert.deepEqual(visible(upgraded), visible(preferences(saved)));
    assert.equal(upgraded.historyWeeks, preferences(saved).historyWeeks);
    assert.ok(upgraded.hidden.includes('leaderboard'));
    assert.ok(visible(preferences({ ...upgraded, hidden:upgraded.hidden.filter(id => id !== 'leaderboard') }, registry)).includes('leaderboard'));
  }
});

test('discovers only active memberships and ranks all pages with scoped counts and ties', async () => {
  assert.match(operations.leaderboardMembers, /contributionsCollection\(organizationID:\$org,from:\$from,to:\$to\)/);
  assert.doesNotMatch(operations.leaderboardMembers, /contributionCalendar|restrictedContributionsCount|mutation/);
  const available = await organizations(context((operation, { after }) => {
    assert.equal(operation, 'leaderboardOrganizations');
    return after ? discovery([north]) : discovery([south, { ...north, viewerIsAMember:false }], 'org-page-2');
  }));
  assert.deepEqual(available.map(org => org.id), [north.id, south.id]);
  const rows = await standings(context((operation, variables) => {
    assert.equal(operation, 'leaderboardMembers');
    assert.deepEqual(variables, { login:north.login, org:north.id, from:'2025-02-01T07:40:00.000Z',
      to:'2025-03-03T07:40:00.000Z', after:variables.after });
    if (variables.after === null) return roster(north, [member('Zeke', 6), member('quiet', 0)], 4, 'member-page-2');
    assert.equal(variables.after, 'member-page-2');
    return roster(north, [member('alice', 0, 2, 3, 1), member('viewer', 1, 2, 3, 4)], 4);
  }), north);
  assert.deepEqual(rows.map(({ login, count, rank }) => [login, count, rank]),
    [['viewer', 10, 1], ['alice', 6, 2], ['Zeke', 6, 2], ['quiet', 0, 4]]);
});

test('withholds incomplete, oversized, changed roster and wrong-account results', async () => {
  for (const [response, code] of [
    [roster(north, [member('one', 0)], 2), 'incomplete'],
    [roster(north, [member('one', 0), member('One', 2)]), 'incomplete'],
    [roster(north, [member('one')]), 'incomplete'],
    [roster(north, [], 501, 'unneeded'), 'roster_limit'],
    [roster({ ...north, viewerIsAMember:false }, []), 'access'],
    [{ ...roster(north, []), viewer:{ login:'switched' } }, 'access']
  ]) await assert.rejects(standings(context((_op, { after }) => { assert.equal(after, null); return response; }), north), { code });
  await assert.rejects(standings(context((_op, { after }) => after ? roster(north, [], 1) : roster(north, [], 2, 'p2')), north),
    { code:'incomplete' });
});

test('retains only a dated complete snapshot through refresh and confirmed transient failure', async () => {
  const state = leaderboard({ publish:() => {}, now:() => at + 40 });
  await state.refresh(context(good));
  const first = state.snapshot().snapshot;
  assert.equal(first.updatedAt, at + 40);
  for (const code of ['rate_limit', 'server', 'network', 'unknown', 'access', 'roster_limit']) {
    await state.refresh(context(good), { force:true });
    const pending = state.refresh(context(() => { throw Object.assign(new Error(), { code }); }), { force:true });
    assert.equal(state.snapshot().loading, true);
    assert.deepEqual(state.snapshot().snapshot, first);
    await pending;
    assert.equal(state.snapshot().error, code);
    assert.deepEqual(state.snapshot().snapshot, ['rate_limit', 'server', 'network'].includes(code) ? first : null);
  }
  await state.refresh(context(good), { force:true });
  await state.refresh(context(() => discovery([south])), { force:true });
  assert.equal(state.snapshot().error, 'access');
  assert.equal(state.snapshot().snapshot, null);
  assert.deepEqual(state.snapshot().organizations.map(org => org.id), [south.id]);
});

test('scope changes and aborted native responses never publish ranks from the previous request', async () => {
  const state = leaderboard({ publish:() => {} });
  await state.refresh(context(good));
  const controller = new AbortController();
  let complete;
  const pending = state.refresh(context((operation, variables) => operation === 'leaderboardOrganizations' ? good(operation, variables) :
    new Promise(resolve => { complete = resolve; }), { signal:controller.signal }), { force:true });
  while (!complete) await Promise.resolve();
  controller.abort();
  assert.equal(state.snapshot().loading, false);
  state.scope('viewer', south.id);
  assert.equal(state.snapshot().snapshot, null);
  await state.refresh(context(good));
  complete(roster(north, [member('viewer', 99)]));
  await pending;
  assert.equal(state.snapshot().snapshot.rows[0].count, 0);
  state.scope('another');
  assert.equal(state.snapshot().snapshot, null);
  assert.equal(state.snapshot().organizations, undefined);
});
