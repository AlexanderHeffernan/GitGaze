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

/**
 * GitHub attributes private-repository contributions to an organisation only for tokens with
 * read:user, which GitHub CLI doesn't request. Without it, members are counted from the
 * organisation's repositories instead, which the CLI's repo scope can read.
 */
async function exactCounts() {
  const scopes = await invoke('github_scopes');
  return typeof scopes !== 'string' || scopes.split(',').some(scope => ['read:user', 'user'].includes(scope.trim()));
}

/** Optional: lets GitHub count every contribution type exactly, instead of from repositories. */
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

/** Runs tasks a few at a time. */
async function pool(tasks, parallel) {
  const queue = [...tasks];
  await Promise.all(Array.from({ length: parallel }, async () => { for (let task; (task = queue.shift());) await task(); }));
}

const chunks = (items, size) => Array.from({ length: Math.ceil(items.length / size) }, (_, i) => items.slice(i * size, (i + 1) * size));

/** GitHub's own per-organisation contribution counts. A year for 50 members exceeds its ten-second limit, so ten at a time. */
async function contributionCounts(organization, people, variables, batch, parallel) {
  const counts = new Map();
  await pool(chunks(people.map(p => p.id), batch).map(ids => async () => {
    const data = await retrying(() => query(`query($ids:[ID!]!, $org:ID!, $from:DateTime!, $to:DateTime!) { nodes(ids:$ids) { ... on User { id
      contributionsCollection(organizationID:$org, from:$from, to:$to) {
        totalCommitContributions totalIssueContributions totalPullRequestContributions totalPullRequestReviewContributions } } } }`, { ...variables, org: organization.id, ids }));
    for (const node of data.nodes) {
      const c = node?.contributionsCollection;
      if (c) counts.set(node.id, c.totalCommitContributions + c.totalIssueContributions + c.totalPullRequestContributions + c.totalPullRequestReviewContributions);
    }
  }), parallel);
  return counts;
}

/**
 * Counts from the repositories themselves: commits on each active repository's default branch,
 * plus pull requests opened, issues opened and pull requests reviewed, from search. Search and
 * history include private repositories the CLI can read.
 */
async function repositoryCounts(organization, people, { from, to }, batch, parallel) {
  const counts = new Map(people.map(p => [p.id, 0]));
  const add = (id, n) => counts.set(id, counts.get(id) + n);
  const repositories = [];
  let after = null;
  do {
    const data = await query(`query($login:String!, $after:String) { organization(login:$login) { repositories(first:100, after:$after, orderBy:{field:PUSHED_AT, direction:DESC}) {
      pageInfo { hasNextPage endCursor } nodes { name pushedAt defaultBranchRef { id } } } } }`, { login: organization.login, after });
    const page = data.organization.repositories;
    const active = page.nodes.filter(r => r.pushedAt && r.pushedAt >= from);
    repositories.push(...active.filter(r => r.defaultBranchRef));
    after = page.pageInfo.hasNextPage && active.length === page.nodes.length ? page.pageInfo.endCursor : null;
  } while (after);

  const tasks = [];
  for (const repository of repositories) for (const group of chunks(people, batch)) tasks.push(async () => {
    const fields = group.map((p, i) => `a${i}: history(since:$from, until:$to, author:{id:${JSON.stringify(p.id)}}) { totalCount }`).join(' ');
    const data = await retrying(() => query(`query($owner:String!, $name:String!, $from:GitTimestamp!, $to:GitTimestamp!) {
      repository(owner:$owner, name:$name) { defaultBranchRef { target { ... on Commit { ${fields} } } } } }`, { owner: organization.login, name: repository.name, from, to }));
    const target = data.repository?.defaultBranchRef?.target ?? {};
    group.forEach((p, i) => add(p.id, target[`a${i}`]?.totalCount ?? 0));
  });
  const range = `${from.slice(0, 19)}+00:00..${to.slice(0, 19)}+00:00`;
  for (const [kind, qualifier] of [['pr', 'author'], ['issue', 'author'], ['pr', 'reviewed-by']]) {
    for (const group of chunks(people, 25)) tasks.push(async () => {
      const fields = group.map((p, i) => `s${i}: search(type:ISSUE, first:0, query:${JSON.stringify(`org:${organization.login} is:${kind} ${qualifier}:${p.login} created:${range}`)}) { issueCount }`).join(' ');
      const data = await retrying(() => query(`query { ${fields} }`));
      group.forEach((p, i) => add(p.id, data[`s${i}`]?.issueCount ?? 0));
    });
  }
  await pool(tasks, parallel);
  return counts;
}

export async function standings(organization, period, now = new Date(), batch = 10, parallel = 4) {
  const { found, total } = await members(organization.login);
  const variables = { from: periodStart(period, now), to: now.toISOString() };
  const scoped = await exactCounts();
  // GitHub's contribution counts ignore the time of day and cover whole UTC dates, which away
  // from UTC shifts a day or week by up to half a day. Repositories honour exact times.
  const exact = scoped && !['today', 'week'].includes(period);
  const counts = await (exact ? contributionCounts : repositoryCounts)(organization, found, variables, batch, parallel);
  const rows = found.map(({ id, login, name, avatarUrl }) => ({ login, ...(name ? { name } : {}), avatarUrl, count: counts.get(id) ?? 0 }));
  return { rows: rank(rows), total, partial: total > found.length, exact, scoped };
}
