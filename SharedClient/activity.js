/* Shared persistence/identity/refresh policy. The host keeps credentials, files and HTTP outside the renderer. */
(() => {
  'use strict';
  const epoch = Date.UTC(2001, 0, 1);

  function readProfile(node) {
    const { login, name, avatarUrl, contributionsCollection } = node;
    const { contributionYears, restrictedContributionsCount, contributionCalendar } = contributionsCollection;
    return { person: { login, name, avatarUrl }, years: contributionYears, restrictedCount: restrictedContributionsCount,
      totalContributions: contributionCalendar.totalContributions, days: contributionCalendar.weeks.flatMap(w => w.contributionDays) };
  }

  function activity({ request, core, onChange, onVerifiedRefresh, onViewerFailure, registry, now = () => new Date() }) {
    let prefs, dashboard, error, pending = false, attempted = -Infinity, historyAt = -Infinity, followingAt = -Infinity, knownViewer, extension, queuedExtension, verifying;
    let peopleLimit = 12, peopleBusy = false, peopleRequested = false, generation = 0;
    const today = () => core.localDay(now());
    const snapshot = () => ({ today: today(), dashboard, preferences: prefs, live: true,
      status: pending ? 'Refreshing…' : error ? dashboard ? 'Cached activity · refresh failed' : 'Not connected' : dashboard ? 'Updated' : 'Not connected', error });
    const publish = () => onChange(snapshot());
    const cache = async () => { await request('writeCache', dashboard); };
    const query = (operation, variables = {}) => request('github', { operation, variables });

    async function loadPeople(limit = peopleLimit) {
      peopleLimit = Math.max(limit, peopleLimit);
      peopleRequested = true;
      if (pending || peopleBusy || !knownViewer || !dashboard) return;
      const scope = generation;
      const names = [...new Set([...core.orderPeople(dashboard.following, prefs).slice(0, peopleLimit).map(p => p.login),
        ...prefs.favourites.filter(login => dashboard.following.some(p => p.login === login))])].filter(login => !Object.hasOwn(dashboard.people, login));
      peopleRequested = false;
      if (!names.length) return;
      peopleBusy = true;
      try {
        const added = Object.create(null);
        for (let i = 0; i < names.length; i += 4) {
          if (scope !== generation) return;
          await Promise.all(names.slice(i, i + 4).map(async login => {
            const node = (await query('profile', { login })).user;
            if (node) added[login] = readProfile(node);
          }));
        }
        if (scope !== generation) return;
        dashboard = { ...dashboard, people:{ ...dashboard.people, ...added } };
        await cache(); publish();
      } catch (e) { if (scope === generation) { error = e.message; publish(); } }
      finally { peopleBusy = false; if (peopleRequested && !pending) void loadPeople(); }
    }

    async function refresh({ force = false, background = false, extensionForce = false } = {}) {
      const at = +now();
      if (pending) {
        queuedExtension ||= extensionForce;
        return;
      }
      if (!force && (background ? at - attempted < 300000 : dashboard && at - +core.cacheTimestamp(dashboard.updatedAt) < 30000)) return;
      generation++;
      pending = true; attempted = at; error = undefined; publish();
      let verified = false;
      let finishVerification;
      verifying = new Promise(resolve => { finishVerification = resolve; });
      try {
        const profile = readProfile((await query('viewer')).viewer);
        verified = true;
        const matching = dashboard && !core.accountChanged(dashboard, profile.person.login) ? dashboard : null;
        if (knownViewer !== profile.person.login.toLowerCase()) {
          extension?.abort(); extension = undefined;
          knownViewer = profile.person.login.toLowerCase(); historyAt = followingAt = -Infinity; peopleLimit = 12;
        }
        verifying = undefined; finishVerification();
        dashboard = { profile, history: matching?.history ?? [], historyComplete: matching?.historyComplete ?? false,
          following: matching?.following ?? [], people: matching?.people ?? {}, updatedAt: (+now() - epoch) / 1000 };
        if (onVerifiedRefresh) {
          extension ??= new AbortController();
          const { signal } = extension;
          // Same-account polls keep this scope; switching accounts or losing verification revokes it.
          const scopedQuery = async (operation, variables, runSignal) => {
            if (verifying) await verifying;
            signal.throwIfAborted();
            runSignal?.throwIfAborted();
            if (operation === 'viewer') throw new Error('Extensions cannot renew the GitHub session.');
            try { return await query(operation, variables); }
            finally { signal.throwIfAborted(); }
          };
          Promise.resolve().then(() => onVerifiedRefresh({ login: profile.person.login, at, signal, query: scopedQuery, extensionForce }))
            .catch(e => { if (!signal.aborted) console.error('Activity extension refresh failed', e); });
          // Give extensions a chance to synchronously clear old-account state before rendering.
          await Promise.resolve();
        }
        publish();
        await cache();
        if (at - historyAt >= 21600000) {
          const history = [];
          for (const year of [...profile.years].sort((a, b) => a - b)) {
            const data = await query('history', { login:profile.person.login, from:`${year}-01-01T00:00:00Z`, to:`${year}-12-31T23:59:59Z` });
            history.push(...readProfile(data.user).days);
          }
          dashboard = { ...dashboard, history:core.statistics(history, today()).days, historyComplete:true };
          historyAt = at; await cache(); publish();
        }
        if (at - followingAt >= 300000) {
          const following = [];
          let after = null;
          do {
            const page = (await query('following', { after })).viewer.following;
            following.push(...page.nodes.filter(Boolean));
            after = page.pageInfo.hasNextPage ? page.pageInfo.endCursor : null;
          } while (after);
          const accounts = [...new Set([...core.orderPeople(following, prefs).slice(0, peopleLimit).map(p => p.login), ...prefs.favourites.filter(login => following.some(p => p.login === login))])];
          const people = Object.assign(Object.create(null), dashboard.people);
          for (let i = 0; i < accounts.length; i += 4) {
            await Promise.all(accounts.slice(i, i + 4).map(async login => {
              const node = (await query('profile', { login })).user;
              if (node) people[login] = readProfile(node);
            }));
          }
          dashboard = { ...dashboard, following, people };
          followingAt = at; await cache();
        }
      } catch (e) {
        error = e.message;
        if (!verified) {
          knownViewer = undefined;
          extension?.abort(); extension = undefined;
          verifying = undefined; finishVerification();
          onViewerFailure?.({ at, code: e.code ?? 'unknown' });
        }
      }
      finally {
        pending = false;
        const queued = queuedExtension;
        queuedExtension = undefined;
        if (queued) void refresh({ force:true, extensionForce:true });
        else {
          publish();
          if (peopleRequested && knownViewer) void loadPeople();
        }
      }
    }

    return {
      async start() {
        try {
          const local = await request('readLocal');
          dashboard = local.dashboard;
          prefs = core.preferences(local.preferences, registry);
        } catch (e) { prefs = core.preferences(undefined, registry); error = e.message; }
        publish();
        await refresh({ force:true });
      },
      async setPreferences(value) {
        const changes = Object.fromEntries(Object.entries(value).filter(([key, next]) => JSON.stringify(prefs[key]) !== JSON.stringify(next)));
        // Persist the widget IDs seen by this installation when visibility changes so a newly
        // enabled, hidden-by-default widget stays enabled after a restart or upgrade.
        if ('hidden' in changes) changes.modules = value.modules;
        prefs = value;
        try { await request('writePreferences', changes); }
        catch (e) { error = e.message; publish(); }
      },
      refresh, snapshot, loadPeople
    };
  }

  if (typeof module === 'object') module.exports = { activity };
  else globalThis.gitGazeActivity = activity;
})();
