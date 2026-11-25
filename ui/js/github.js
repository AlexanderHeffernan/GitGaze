// GitHub's GraphQL contribution calendar is the source of truth. Requests go through the native
// shell, which holds the GitHub CLI token; the UI never sees it.

import { invoke } from './bridge.js';

const collection = `contributionYears restrictedContributionsCount
  contributionCalendar { totalContributions weeks { contributionDays { date contributionCount color } } }`;

const query = (text, variables = {}) => invoke('github_query', { query: text, variables });

function toProfile(user) {
  if (!user) throw new Error('This GitHub profile is no longer available.');
  const c = user.contributionsCollection;
  return {
    person: { login: user.login, ...(user.name ? { name: user.name } : {}), avatarUrl: user.avatarUrl },
    days: c.contributionCalendar.weeks.flatMap(week => week.contributionDays),
    years: c.contributionYears,
    totalContributions: c.contributionCalendar.totalContributions,
    restrictedCount: c.restrictedContributionsCount,
  };
}

export const connect = () => invoke('github_connect');

export async function viewer() {
  return toProfile((await query(`query { viewer { login name avatarUrl contributionsCollection { ${collection} } } }`)).viewer);
}

export async function profile(login) {
  const data = await query(`query($login:String!) { user(login:$login) { login name avatarUrl contributionsCollection { ${collection} } } }`, { login });
  return toProfile(data.user);
}

export async function history(login, year) {
  const data = await query(`query($login:String!, $from:DateTime!, $to:DateTime!) {
    user(login:$login) { login name avatarUrl contributionsCollection(from:$from,to:$to) { ${collection} } } }`,
  { login, from: `${year}-01-01T00:00:00Z`, to: `${year}-12-31T23:59:59Z` });
  return toProfile(data.user).days;
}

export async function following() {
  const people = [];
  let cursor = null;
  do {
    const after = cursor ? `, after: ${JSON.stringify(cursor)}` : '';
    const page = (await query(`query { viewer { following(first:100${after}) { nodes { login name avatarUrl } pageInfo { hasNextPage endCursor } } } }`)).viewer.following;
    people.push(...page.nodes.map(({ login, name, avatarUrl }) => ({ login, ...(name ? { name } : {}), avatarUrl })));
    cursor = page.pageInfo.hasNextPage ? page.pageInfo.endCursor : null;
  } while (cursor);
  return people;
}

export const displayName = person => person.name || person.login;
