const { test } = require('node:test');
const assert = require('node:assert/strict');
const core = require('./core');
const { activity } = require('./activity');
const { dashboard } = require('./fixture.json');

test('offline cache survives, then a verified switch never carries the old history or people forward', async () => {
  let offline = true, now = new Date(2024, 2, 4, 12), viewers = 0;
  const observed = [], writes = [], cursors = [];
  const person = login => ({ login, name: null, avatarUrl: 'https://example.invalid/avatar' });
  const profile = login => ({ ...person(login), contributionsCollection: { contributionYears: [2024], restrictedContributionsCount: 0,
    contributionCalendar: { totalContributions: 2, weeks: [{ contributionDays: [{ date: '2024-03-04', contributionCount: 2, color: '#40c463' }] }] } } });
  const engine = activity({ core, now: () => now, onChange: snapshot => observed.push(snapshot), async request(method, args) {
    if (method === 'readLocal') return { dashboard, preferences: { historyWeeks: 53, palette: 'violet' } };
    if (method.startsWith('write')) { writes.push([method, structuredClone(args)]); return; }
    const { operation, variables } = args;
    if (operation === 'viewer') {
      viewers++;
      if (offline) throw new Error('offline');
      return { viewer: profile('different-account') };
    }
    if (operation === 'following') {
      cursors.push(variables.after);
      return { viewer: { following: { nodes: [person(variables.after ? 'second' : 'first')],
        pageInfo: { hasNextPage: !variables.after, endCursor: 'next-page' } } } };
    }
    if (operation === 'history') assert.deepEqual(variables, { login: 'different-account', from: '2024-01-01T00:00:00Z', to: '2024-12-31T23:59:59Z' });
    return { user: profile(variables.login) };
  } });
  await engine.start();
  assert.equal(engine.snapshot().dashboard, dashboard);
  assert.equal(engine.snapshot().error, 'offline');
  assert.deepEqual(writes, []);
  await engine.setPreferences({ ...core.preferences(engine.snapshot().preferences), historyWeeks: 26 });
  assert.deepEqual(writes.shift(), ['writePreferences', { historyWeeks: 26 }]);
  offline = false;
  await Promise.all([engine.refresh({ force: true }), engine.refresh({ force: true })]);
  assert.equal(viewers, 2);
  const switched = observed.find(s => s.dashboard?.profile.person.login === 'different-account').dashboard;
  assert.deepEqual([switched.history, switched.following, switched.people], [[], [], {}]);
  const final = engine.snapshot().dashboard;
  assert.deepEqual(cursors, [null, 'next-page']);
  assert.deepEqual(Object.keys(final.people).sort(), ['first', 'second']);
  assert.deepEqual([final.historyComplete, final.history[0].contributionCount], [true, 2]);
  assert.ok(writes.every(([, cache]) => cache.profile.person.login === 'different-account'));
  now = new Date(+now + 299_000);
  await engine.refresh({ background: true });
  assert.equal(viewers, 2);
  now = new Date(+now + 1000);
  await engine.refresh({ background: true });
  assert.equal(viewers, 3);
});

test('extension queries are scoped to a verified refresh and discard results after an account switch', async () => {
  let login = 'first-account', release;
  const contexts = [], profile = {
    name: null, avatarUrl: 'https://example.invalid/avatar', contributionsCollection: {
      contributionYears: [], restrictedContributionsCount: 0, contributionCalendar: { totalContributions: 0, weeks: [] }
    }
  };
  const engine = activity({ core, onChange() {}, onVerifiedRefresh: context => contexts.push(context), async request(method, args) {
    if (method === 'readLocal') return { preferences: {} };
    if (method !== 'github') return;
    if (args.operation === 'viewer') return { viewer: { ...profile, login } };
    if (args.operation === 'following') return { viewer: { following: { nodes: [], pageInfo: { hasNextPage: false } } } };
    return new Promise(resolve => { release = resolve; });
  } });
  await engine.start();
  assert.equal(contexts[0].login, 'first-account');
  await assert.rejects(contexts[0].query('viewer'), /cannot renew/);
  const lateResult = assert.rejects(contexts[0].query('profile', { login: 'first-account' }), { name: 'AbortError' });
  login = 'second-account';
  await engine.refresh({ force: true });
  assert.equal(contexts[1].login, 'second-account');
  assert.equal(contexts[0].signal.aborted, true);
  release({ user: { login: 'first-account' } });
  await lateResult;
  await assert.rejects(contexts[0].query('profile'), { name: 'AbortError' });
});

test('section refresh requested during Following is replayed without revoking the same-account scope', async () => {
  let releaseFollowing, viewers = 0;
  const contexts = [];
  const engine = activity({ core, onChange() {}, onVerifiedRefresh: context => contexts.push(context), async request(method, args) {
    if (method === 'readLocal') return { preferences:{} };
    if (method !== 'github') return;
    if (args.operation === 'viewer') {
      viewers++;
      return { viewer:{ login:'viewer', contributionsCollection:{ contributionYears:[], contributionCalendar:{ weeks:[] } } } };
    }
    return new Promise(resolve => { releaseFollowing = resolve; });
  } });
  const start = engine.start();
  while (!releaseFollowing) await Promise.resolve();
  await engine.refresh({ force:true, extensionForce:true });
  await engine.refresh({ force:true, extensionForce:true });
  assert.equal(viewers, 1);
  releaseFollowing({ viewer:{ following:{ nodes:[], pageInfo:{ hasNextPage:false } } } });
  await start;
  assert.equal(viewers, 2);
  assert.deepEqual(contexts.map(c => c.extensionForce), [false, true]);
  assert.equal(contexts[0].signal.aborted, false);
});

test('an opt-in widget stays in the gallery until enabled and survives restart after enabling', async () => {
  const registry = [{ id:'today' }, { id:'optional-widget', hiddenByDefault:true }];
  let stored = { modules:['today'], hidden:[] };
  const makeEngine = () => activity({ core, registry, onChange() {}, async request(method, args) {
    if (method === 'readLocal') return { preferences: stored };
    if (method === 'writePreferences') { stored = { ...stored, ...args }; return; }
    throw new Error('offline');
  } });
  const first = makeEngine();
  await first.start();
  assert.deepEqual(first.snapshot().preferences.hidden, ['optional-widget']);
  await first.setPreferences({ ...first.snapshot().preferences, hidden:[] });
  assert.deepEqual(stored, { modules:['today', 'optional-widget'], hidden:[] });
  const restarted = makeEngine();
  await restarted.start();
  assert.deepEqual(restarted.snapshot().preferences.hidden, []);
});

test('viewer failure notifies the extension even with a cached account, without starting its refresh', async () => {
  const failures = [];
  const engine = activity({ core, now: () => new Date(1000), onChange() {},
    onVerifiedRefresh() { assert.fail('cached identity is not verification'); },
    onViewerFailure: failure => failures.push(failure), async request(method) {
      if (method === 'readLocal') return { dashboard, preferences: {} };
      throw Object.assign(new Error('denied'), { code: 'access' });
    }
  });
  await engine.start();
  assert.deepEqual(failures, [{ at:1000, code:'access' }]);
  assert.equal(engine.snapshot().dashboard, dashboard);
});
