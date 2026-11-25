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

export async function standings(organization, period, now = new Date()) {
  const members = [];
  let after = null, total = 0;
  do {
    const data = await query(`query($login:String!, $org:ID!, $from:DateTime!, $to:DateTime!, $after:String) {
      organization(login:$login) { membersWithRole(first:50, after:$after) { totalCount pageInfo { hasNextPage endCursor }
        nodes { login name avatarUrl contributionsCollection(organizationID:$org, from:$from, to:$to) {
          totalCommitContributions totalIssueContributions totalPullRequestContributions totalPullRequestReviewContributions } } } } }`,
    { login: organization.login, org: organization.id, from: periodStart(period, now), to: now.toISOString(), after });
    const page = data.organization.membersWithRole;
    total = page.totalCount;
    for (const { login, name, avatarUrl, contributionsCollection: c } of page.nodes) {
      const count = c.totalCommitContributions + c.totalIssueContributions + c.totalPullRequestContributions + c.totalPullRequestReviewContributions;
      members.push({ login, ...(name ? { name } : {}), avatarUrl, count });
    }
    after = page.pageInfo.hasNextPage && members.length < memberLimit ? page.pageInfo.endCursor : null;
  } while (after);
  return { rows: rank(members), total, partial: total > members.length };
}
