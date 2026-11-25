// The only way the UI reaches the native shell. In a plain browser (the UI preview and the
// website demo) it answers with deterministic sample data instead, so the same UI code runs.

import { dayKey, offset } from './stats.js';

const tauri = globalThis.__TAURI__;
export const native = Boolean(tauri);

export function invoke(command, args = {}) {
  return native ? tauri.core.invoke(command, args) : preview(command, args);
}

const handlers = new Map();
export function listen(event, handler) {
  if (native) return tauri.event.listen(event, message => handler(message.payload));
  if (!handlers.has(event)) handlers.set(event, new Set());
  handlers.get(event).add(handler);
}
/** Preview only: delivers an event as the native shell would. */
export const emitLocal = (event, payload) => handlers.get(event)?.forEach(handler => handler(payload));
if (!native) globalThis.gitgazeEmit = emitLocal; // Lets the website demo drive an embedded celebration.

export const plugin = name => (native ? tauri[name] : undefined);

export function openURL(url) {
  if (native) return tauri.opener.openUrl(url);
  window.open(url, '_blank', 'noopener,noreferrer');
}

// ----- Preview data -----

function random(seed) {
  return () => {
    seed = (seed * 1664525 + 1013904223) >>> 0;
    return seed / 2 ** 32;
  };
}

const levels = ['#ebedf0', '#9be9a8', '#40c463', '#30a14e', '#216e39'];
/** Each day's count depends only on the login and date, so overlapping queries agree. */
function calendar(login, from, through) {
  const base = [...login].reduce((sum, c) => (sum * 31 + c.charCodeAt(0)) >>> 0, 7);
  const busy = 0.35 + random(base)() * 0.5;
  const days = [];
  for (let date = from; date <= through; date = offset(date, 1)) {
    const next = random((base ^ Math.imul(Number(date.replaceAll('-', '')), 2654435761)) >>> 0);
    next();
    const roll = next();
    let count = roll < busy ? Math.floor(next() * next() * 18) + 1 : 0;
    // The signed-in sample user is mid-streak, so the demo shows a lively dashboard.
    if (login === me[0] && date >= offset(dayKey(), -11)) count = Math.max(count, date === dayKey() ? 6 : 2 + Math.floor(next() * 7));
    days.push({ date, contributionCount: count, color: levels[count ? Math.min(4, Math.floor(count / 5) + 1) : 0] });
  }
  return days;
}

// Fictional people with stock sample portraits, and the app's author as the signed-in user.
const sample = [
  ['hanasato', 'Hana Sato'], ['leomartins', 'Leo Martins'], ['julespark', 'Jules Park'], ['samrivera', 'Sam Rivera'],
  ['avathompson', 'Ava Thompson'], ['omarhaddad', 'Omar Haddad'], ['ellanovak', 'Ella Novak'], ['theogrant', 'Theo Grant'],
  ['meilin', 'Mei Lin'], ['ethancole', 'Ethan Cole'], ['sofiarossi', 'Sofia Rossi'], ['noahbecker', 'Noah Becker'],
  ['iriswalsh', 'Iris Walsh'], ['lucasferreira', 'Lucas Ferreira'],
];
const me = ['AlexanderHeffernan', 'Alexander Heffernan'];
const avatar = login => `demo/${login.toLowerCase()}.jpg`;
const person = ([login, name]) => ({ login, name, avatarUrl: avatar(login) });

function profile(login, name, from, through) {
  const days = calendar(login, from, through);
  return {
    login, name, avatarUrl: avatar(login),
    contributionsCollection: {
      contributionYears: [2026, 2025, 2024, 2023],
      restrictedContributionsCount: 0,
      contributionCalendar: {
        totalContributions: days.reduce((sum, day) => sum + day.contributionCount, 0),
        weeks: [{ contributionDays: days }],
      },
    },
  };
}

let previewPrefs = null;
async function preview(command, args) {
  const today = dayKey();
  const yearAgo = offset(today, -371);
  switch (command) {
    case 'platform': return new URLSearchParams(location.search).get('platform') ?? 'macos';
    case 'gh_installed': return true;
    case 'github_connect': return null;
    case 'launch_at_login': return false;
    case 'set_launch_at_login': return args.enabled;
    case 'load_state': return { preferences: previewPrefs ?? { modules: ['today', 'streak', 'heatmap', 'favourites', 'leaderboard'], hidden: ['records', 'people', 'years'], favourites: ['hanasato', 'leomartins', 'julespark'] }, migrated: false, cache: null };
    case 'save_preferences': previewPrefs = args.preferences; return null;
    case 'celebrate': if (parent !== window) parent.postMessage({ gitgaze: 'celebrate', args }, location.origin); return null;
    case 'github_query': {
      const { query, variables } = args;
      if (query.includes('organizations(')) return { viewer: { organizations: { nodes: [{ id: 'O_1', login: 'acme', name: 'Acme Labs', avatarUrl: '' }, { id: 'O_2', login: 'octo-collective', name: 'Octo Collective', avatarUrl: '' }] } } };
      if (query.includes('membersWithRole')) {
        const members = [me, ...sample.slice(0, 11)];
        return { organization: { membersWithRole: { totalCount: members.length, pageInfo: { hasNextPage: false, endCursor: null },
          nodes: members.map(([login, name]) => ({ id: `U_${login}`, login, name, avatarUrl: avatar(login) })) } } };
      }
      // Sample org members' commits over a period, by member and organisation.
      const commits = (id, org, from) => {
        const span = Math.max(1, Math.round((Date.now() - Date.parse(from)) / 86400000));
        const next = random([...id + org].reduce((sum, c) => (sum * 31 + c.charCodeAt(0)) >>> 0, 3));
        return Math.floor(next() * 6 * span);
      };
      if (query.includes('nodes(ids:')) {
        return { nodes: variables.ids.map(id => {
          const total = commits(id, variables.org, variables.from);
          return { id, contributionsCollection: { totalCommitContributions: total, totalIssueContributions: 0, totalPullRequestContributions: Math.floor(total / 4), totalPullRequestReviewContributions: 0 } };
        }) };
      }
      if (query.includes('repositories(')) {
        return { organization: { repositories: { pageInfo: { hasNextPage: false, endCursor: null }, nodes: [{ name: 'app', pushedAt: new Date().toISOString(), defaultBranchRef: { id: 'R_app' } }] } } };
      }
      if (query.includes('history(')) {
        const authors = [...query.matchAll(/(a\d+): history\([^)]*author:\{id:"([^"]+)"\}\)/g)];
        return { repository: { defaultBranchRef: { target: Object.fromEntries(authors.map(([, alias, id]) => [alias, { totalCount: commits(id, variables.owner, variables.from) }])) } } };
      }
      if (query.includes('search(type:ISSUE')) {
        const searches = [...query.matchAll(/(s\d+): search\(type:ISSUE, first:0, query:"org:(\S+) is:pr author:(\S+) created:(\S+)\+00:00\.\./g)];
        return Object.fromEntries(searches.map(([, alias, org, login, from]) => [alias, { issueCount: Math.floor(commits(`U_${login}`, org, `${from}Z`) / 4) }]));
      }
      if (query.includes('following(')) return { viewer: { following: { nodes: sample.map(person), pageInfo: { hasNextPage: false, endCursor: null } } } };
      if (variables.from) {
        const year = variables.from.slice(0, 4);
        return { user: profile(...me, `${year}-01-01`, `${year}-12-31` < today ? `${year}-12-31` : today) };
      }
      if (variables.login) {
        const match = sample.find(([login]) => login === variables.login) ?? [variables.login, variables.login];
        return { user: profile(match[0], match[1], yearAgo, today) };
      }
      return { viewer: profile(...me, yearAgo, today) };
    }
    default: return null; // Tray, celebration, cache and window commands do nothing in a browser.
  }
}
