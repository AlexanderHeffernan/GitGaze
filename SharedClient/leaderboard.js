/* Read-only GitHub organization rankings; independent of the widget and native transport. */
(() => {
  'use strict';
  const memberLimit = 500, pageLimit = memberLimit / 25;
  const interval = 15 * 60_000, windowMs = 30 * 86_400_000;
  const fields = ['totalCommitContributions', 'totalIssueContributions',
    'totalPullRequestContributions', 'totalPullRequestReviewContributions'];
  const transient = new Set(['rate_limit', 'network', 'server']);
  const errors = new Set([...transient, 'access', 'roster_limit', 'incomplete']);
  const failure = code => Object.assign(new Error(code), { code });
  const loginKey = login => typeof login === 'string' ? login.toLowerCase() : '';
  const byLogin = (a, b) => loginKey(a) < loginKey(b) ? -1 : loginKey(a) > loginKey(b) ? 1 : 0;

  async function request(context, operation, variables) {
    context.signal.throwIfAborted();
    const data = await context.query(operation, variables, context.signal);
    context.signal.throwIfAborted();
    if (loginKey(data?.viewer?.login) !== loginKey(context.login)) throw failure('access');
    return data;
  }

  function cursor(page, seen) {
    const info = page?.pageInfo;
    if (!Array.isArray(page?.nodes) || typeof info?.hasNextPage !== 'boolean') throw failure('incomplete');
    if (!info.hasNextPage) return null;
    if (typeof info.endCursor !== 'string' || !info.endCursor || seen.has(info.endCursor)) throw failure('incomplete');
    seen.add(info.endCursor);
    return info.endCursor;
  }

  async function organizations(context) {
    const found = new Map(), seen = new Set();
    let after = null;
    do {
      const page = (await request(context, 'leaderboardOrganizations', { after })).viewer.organizations;
      after = cursor(page, seen);
      for (const node of page.nodes) {
        if (node?.viewerIsAMember === true && typeof node.id === 'string' && node.id && loginKey(node.login)) {
          found.set(node.id, { id:node.id, login:node.login });
        }
      }
      if (after && seen.size >= 20) throw failure('incomplete');
    } while (after);
    return [...found.values()].sort((a, b) => byLogin(a.login, b.login));
  }

  async function standings(context, organization) {
    const from = new Date(context.at - windowMs).toISOString(), to = new Date(context.at).toISOString();
    const seen = new Set(), members = new Map();
    let after = null, total;
    do {
      const org = (await request(context, 'leaderboardMembers', { login:organization.login, org:organization.id, from, to, after })).organization;
      if (org?.id !== organization.id || org.viewerIsAMember !== true) throw failure('access');
      const page = org.membersWithRole;
      if (!Number.isSafeInteger(page?.totalCount) || page.totalCount < 0) throw failure('incomplete');
      if (page.totalCount > memberLimit) throw failure('roster_limit');
      if (total !== undefined && total !== page.totalCount) throw failure('incomplete');
      total = page.totalCount;
      after = cursor(page, seen);
      for (const member of page.nodes) {
        const key = loginKey(member?.login);
        if (!key || members.has(key)) throw failure('incomplete');
        const counts = fields.map(field => member.contributionsCollection?.[field]);
        if (counts.some(value => !Number.isSafeInteger(value) || value < 0)) throw failure('incomplete');
        const count = counts.reduce((sum, value) => sum + value, 0);
        if (!Number.isSafeInteger(count)) throw failure('incomplete');
        members.set(key, { login:member.login, name:member.name, avatarUrl:member.avatarUrl, count });
      }
      if (members.size > total || after && seen.size >= pageLimit) throw failure('incomplete');
    } while (after);
    if (members.size !== total) throw failure('incomplete');
    const rows = [...members.values()].sort((a, b) => b.count - a.count || byLogin(a.login, b.login));
    let rank = 0;
    return rows.map((row, index) => {
      if (row.count !== rows[index - 1]?.count) rank = index + 1;
      return { ...row, rank };
    });
  }

  function leaderboard({ publish, now = Date.now }) {
    let state = {}, active, attempted = -Infinity;
    const update = changes => { state = { ...state, ...changes }; publish(state); };
    function scope(login, selected = null) {
      const account = loginKey(login);
      if (account === state.account && selected === state.selected) return;
      active?.abort(); active = undefined; attempted = -Infinity;
      if (account !== state.account) state = {};
      update({ account, selected, snapshot:null, error:null, loading:false });
    }
    function cancel() {
      active?.abort(); active = undefined;
      if (state.loading) { attempted = -Infinity; update({ loading:false }); }
    }
    function fail(error) {
      const code = errors.has(error?.code) ? error.code : 'unknown';
      cancel();
      if (!transient.has(code)) attempted = -Infinity;
      update({ error:code, ...(!transient.has(code) ? { snapshot:null, organizations:null } : {}) });
    }
    async function refresh(context, { force = false } = {}) {
      if (context.signal.aborted) return;
      if (loginKey(context.login) !== state.account) scope(context.login);
      if (!force && (active || context.at - attempted < interval)) return;
      active?.abort();
      const run = active = new AbortController();
      const current = () => active === run && !context.signal.aborted;
      const abort = () => { if (active === run) cancel(); };
      const scoped = { ...context, signal:run.signal };
      context.signal.addEventListener('abort', abort, { once:true });
      attempted = context.at;
      update({ loading:true, error:null });
      let discovering = true;
      try {
        const available = await organizations(scoped);
        if (!current()) return;
        discovering = false;
        const organization = state.selected ? available.find(org => org.id === state.selected) : available[0];
        update({ organizations:available, selected:state.selected ?? organization?.id ?? null });
        if (state.selected && !organization) throw failure('access');
        if (!organization) { update({ snapshot:null }); return; }
        const rows = await standings(scoped, organization);
        if (current()) update({ snapshot:{ rows, updatedAt:now() } });
      } catch (error) {
        if (!current()) return;
        const code = errors.has(error?.code) ? error.code : 'unknown';
        update({ error:code, snapshot:transient.has(code) ? state.snapshot : null,
          ...(discovering && !transient.has(code) ? { organizations:null } : {}) });
      } finally {
        context.signal.removeEventListener('abort', abort);
        if (current()) { active = undefined; update({ loading:false }); }
      }
    }
    return { scope, refresh, cancel, fail, snapshot:() => state };
  }

  if (typeof module === 'object') module.exports = { leaderboard, organizations, standings, memberLimit };
  else globalThis.gitGazeLeaderboard = { leaderboard, memberLimit };
})();
