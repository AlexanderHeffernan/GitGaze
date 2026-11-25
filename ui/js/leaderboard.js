// Organisation leaderboard: members ranked by their contributions to an organisation's
// repositories over a calendar period. Read-only; uses the same GitHub CLI session.

import { invoke } from './bridge.js';

export const periods = [['today', 'Today'], ['week', 'Week'], ['month', 'Month'], ['year', 'Year']];
/** Large organisations are ranked from their first members only, to keep requests bounded. */
export const memberLimit = 200;

const query = (text, variables = {}) => invoke('github_query', { query: text, variables });

/** Local start of the period containing `now`, as an ISO timestamp. Weeks start on Monday. */
export function periodStart(period, now = new Date()) {
  const start = new Date(now);
  start.setHours(0, 0, 0, 0);
  if (period === 'week') start.setDate(start.getDate() - ((start.getDay() + 6) % 7));
  if (period === 'month') start.setDate(1);
  if (period === 'year') start.setMonth(0, 1);
  return start.toISOString();
}

/** Highest count first; equal counts share a rank (1, 2, 2, 4) and sort by login. */
export function rank(members) {
  const sorted = [...members].sort((a, b) => b.count - a.count || a.login.localeCompare(b.login, undefined, { sensitivity: 'base' }));
  let current = 0;
  return sorted.map((member, i) => {
    if (i === 0 || member.count !== sorted[i - 1].count) current = i + 1;
    return { ...member, rank: current };
  });
}

export async function organizations() {
  const data = await query('query { viewer { organizations(first:100) { nodes { id login name avatarUrl } } } }');
  return data.viewer.organizations.nodes.filter(Boolean).sort((a, b) => a.login.localeCompare(b.login, undefined, { sensitivity: 'base' }));
}

/** GitHub times out (HTTP 502/504) on heavy contribution queries; those are worth retrying. */
async function retrying(request, attempts = 3) {
  for (let attempt = 1; ; attempt++) {
    try { return await request(); } catch (error) {
      if (attempt >= attempts || !/HTTP 50[234]/.test(String(error.message ?? error))) throw error;
    }
  }
}

/** True when GitHub said the token's scopes, and they lack the one that reveals private work. */
async function privateHidden() {
  const scopes = await invoke('github_scopes');
  return typeof scopes === 'string' && !scopes.split(',').some(scope => ['read:user', 'user'].includes(scope.trim()));
}

/** Adding the scope needs a browser approval, so the command is shown rather than run. */
export const scopeCommand = 'gh auth refresh -h github.com -s read:user';

async function members(login) {
  const found = [];
  let after = null, total = 0;
  do {
    const data = await query(`query($login:String!, $after:String) { organization(login:$login) { membersWithRole(first:100, after:$after) {
      totalCount pageInfo { hasNextPage endCursor } nodes { id login name avatarUrl } } } }`, { login, after });
    const page = data.organization.membersWithRole;
    total = page.totalCount;
    found.push(...page.nodes);
    after = page.pageInfo.hasNextPage && found.length < memberLimit ? page.pageInfo.endCursor : null;
  } while (after);
  return { found: found.slice(0, memberLimit), total };
}

/**
 * Each member's contributions are counted in small batches, a few at a time: a year of
 * contributions for 50 members in one request exceeds GitHub's ten-second limit.
 */
export async function standings(organization, period, now = new Date(), batch = 10, parallel = 3) {
  const { found, total } = await members(organization.login);
  const counts = new Map();
  const variables = { org: organization.id, from: periodStart(period, now), to: now.toISOString() };
  const batches = [];
  for (let i = 0; i < found.length; i += batch) batches.push(found.slice(i, i + batch).map(member => member.id));
  const work = async () => {
    for (let ids; (ids = batches.shift());) {
      const data = await retrying(() => query(`query($ids:[ID!]!, $org:ID!, $from:DateTime!, $to:DateTime!) { nodes(ids:$ids) { ... on User { id
        contributionsCollection(organizationID:$org, from:$from, to:$to) {
          totalCommitContributions totalIssueContributions totalPullRequestContributions totalPullRequestReviewContributions } } } }`, { ...variables, ids }));
      for (const node of data.nodes) {
        const c = node?.contributionsCollection;
        if (c) counts.set(node.id, c.totalCommitContributions + c.totalIssueContributions + c.totalPullRequestContributions + c.totalPullRequestReviewContributions);
      }
    }
  };
  await Promise.all(Array.from({ length: parallel }, work));
  const rows = found.map(({ id, login, name, avatarUrl }) => ({ login, ...(name ? { name } : {}), avatarUrl, count: counts.get(id) ?? 0 }));
  return { rows: rank(rows), total, partial: total > found.length, privateHidden: await privateHidden() };
}
