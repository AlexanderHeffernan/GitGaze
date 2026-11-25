const test = require('node:test');
const assert = require('node:assert/strict');
const { statistics, preferences, moveWidget, cacheTimestamp, accountChanged } = require('./core');
const { today, dashboard, preferences: saved } = require('./fixture');

test('Swift Codable fixture: Monday, leap day, duplicate, future bucket, previous-year cutoff', () => {
  const stats = statistics([...dashboard.history, ...dashboard.profile.days], today);
  assert.deepEqual([stats.todayCount, stats.streak, stats.previousBest, stats.bestWeek, stats.weekTotal, stats.lastWeekTotal, stats.monthTotal, stats.yearTotal],
    [7, 5, 12, 23, 7, 23, 17, 33]);
  assert.equal(stats.totalInYear(2023, '03-04'), 11);
  assert.equal(stats.totalInYear(2023), 44);
  assert.equal(stats.count('2024-02-29'), 4);
  assert.equal(stats.count('2024-03-05'), 0);
  assert.equal(stats.isRecord, false);
});

test('existing widget and account settings retain their meaning without a data migration', () => {
  const prefs = preferences({ ...saved, modules:['heatmap', 'streak', 'today'], hidden:['heatmap'], historyWeeks:26 });
  assert.deepEqual(prefs.modules.slice(0, 3), ['heatmap', 'streak', 'today']);
  assert.deepEqual(prefs.hidden, ['heatmap', 'years']);
  assert.deepEqual(moveWidget(prefs, 'today', -1).modules.slice(0, 3), ['heatmap', 'today', 'streak']);
  assert.equal(prefs.historyWeeks, 26);
  assert.deepEqual(prefs.favourites, ['mira-fixture']);
  assert.equal(cacheTimestamp(dashboard.updatedAt).toISOString(), '2024-03-05T00:00:00.000Z');
  assert.equal(accountChanged(dashboard, 'CALENDAR-FIXTURE'), false);
  assert.equal(accountChanged(dashboard, 'another-account'), true);
});
