/* GitHub date buckets are already aligned to the API calendar. Work with date keys, not timestamps. */
(() => {
  'use strict';
  const offset = (key, delta) => {
    const date = new Date(`${key}T00:00:00Z`);
    date.setUTCDate(date.getUTCDate() + delta);
    return date.toISOString().slice(0, 10);
  };
  const weekday = key => new Date(`${key}T00:00:00Z`).getUTCDay();
  const monday = key => offset(key, -((weekday(key) + 6) % 7));
  const localDay = date => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;

  function statistics(input, today) {
    const days = [...new Map(input.filter(day => day.date <= today).map(day => [day.date, day])).values()]
      .sort((a, b) => a.date < b.date ? -1 : a.date > b.date ? 1 : 0);
    const byDate = new Map(days.map(day => [day.date, day.contributionCount]));
    const count = date => byDate.get(date) ?? 0;
    const sum = (from, through) => days.reduce((total, day) => total + (day.date >= from && day.date <= through ? day.contributionCount : 0), 0);
    const todayCount = count(today);
    let streak = 0;
    for (let d = todayCount > 0 ? today : offset(today, -1); count(d) > 0; d = offset(d, -1)) streak++;
    let previousBest = 0, longestStreak = 0, run = 0, previousDay, activeDays = 0;
    const weeks = new Map();
    for (const { date, contributionCount: n } of days) {
      if (date < today) previousBest = Math.max(n, previousBest);
      const week = monday(date);
      weeks.set(week, (weeks.get(week) ?? 0) + n);
      if (n > 0) activeDays++;
      run = n > 0 ? (previousDay && offset(previousDay, 1) === date ? run + 1 : 1) : 0;
      longestStreak = Math.max(longestStreak, run);
      previousDay = date;
    }
    const week = monday(today), year = today.slice(0, 4), target = previousBest + 1;
    const yearTotal = (y, cutoff = '12-31') => sum(`${y}-01-01`, `${y}-${cutoff}`);
    return { days, todayCount, count, previousBest, streak, longestStreak, activeDays, bestWeek: Math.max(0, ...weeks.values()),
      bestDay: Math.max(todayCount, previousBest), isRecord: todayCount > previousBest, target, progress: Math.min(1, todayCount / target),
      weekTotal: weeks.get(week) ?? 0, lastWeekTotal: weeks.get(offset(week, -7)) ?? 0,
      monthTotal: sum(today.slice(0, 7) + '-01', today), yearTotal: yearTotal(year), totalInYear: yearTotal };
  }

  const widgetIds = ['today', 'streak', 'heatmap', 'favourites', 'momentum', 'records', 'people', 'years'];
  function preferences(mac = {}, registry = widgetIds.map((id, index) => ({ id, hiddenByDefault: index >= 4 }))) {
    const list = value => Array.isArray(value) ? value : [];
    const ids = registry.map(widget => widget.id);
    const order = [...new Set([...list(mac.modules), ...ids])].filter(id => ids.includes(id));
    const hidden = registry.filter(({ id, hiddenByDefault }) => hiddenByDefault && (!mac.hidden ||
      (!list(mac.modules).includes(id) && (id === 'years' || !widgetIds.includes(id))))).map(widget => widget.id);
    return { ...mac, modules: order, hidden: [...new Set([...list(mac.hidden), ...hidden])].filter(id => ids.includes(id)),
      favourites: list(mac.favourites), favouriteOrder: list(mac.favouriteOrder), historyWeeks: mac.historyWeeks === 26 ? 26 : 53,
      reminderHour: Number.isInteger(mac.reminderHour) && mac.reminderHour >= 0 && mac.reminderHour < 24 ? mac.reminderHour : 18,
      appearance: ['system', 'light', 'dark'].includes(mac.appearance) ? mac.appearance : 'system' };
  }

  function moveWidget(prefs, id, delta) {
    const visible = prefs.modules.filter(key => !prefs.hidden.includes(key));
    const from = visible.indexOf(id), neighbour = visible[from + delta];
    if (from < 0 || !neighbour) return prefs;
    const modules = [...prefs.modules], a = modules.indexOf(id), b = modules.indexOf(neighbour);
    [modules[a], modules[b]] = [modules[b], modules[a]];
    return { ...prefs, modules };
  }

  // Preserve the Swift Codable Dashboard shape, including Date's 2001-01-01 reference epoch.
  const cacheTimestamp = value => new Date(Date.UTC(2001, 0, 1) + value * 1000);
  const accountChanged = (cache, verifiedViewer) => !!cache && cache.profile.person.login.toLowerCase() !== verifiedViewer.toLowerCase();

  function orderPeople(people, { favourites, favouriteOrder }) {
    const selected = new Set(favourites), rank = new Map(favouriteOrder.map((login, index) => [login, index]));
    return [...people].sort((a, b) => Number(selected.has(b.login)) - Number(selected.has(a.login)) ||
      (selected.has(a.login) && (rank.get(a.login) ?? Infinity) - (rank.get(b.login) ?? Infinity)) ||
      a.login.localeCompare(b.login, undefined, { sensitivity:'base' }));
  }

  const core = { offset, weekday, monday, localDay, statistics, preferences, moveWidget, cacheTimestamp, accountChanged, orderPeople };
  if (typeof module === 'object') module.exports = core;
  else globalThis.gitGazeCore = core;
})();
