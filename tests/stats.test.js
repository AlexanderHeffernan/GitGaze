import test from 'node:test';
import assert from 'node:assert/strict';
import { Stats, IncreaseTracker, offset, weekStart, dayKey } from '../ui/js/stats.js';

const day = (date, contributionCount) => ({ date, contributionCount, color: '#ebedf0' });

test('a streak survives until today ends, but not an earlier gap', () => {
  const days = [day('2026-10-11', 2), day('2026-10-12', 1), day('2026-10-13', 0),
    day('2026-10-14', 7), day('2026-10-15', 3), day('2026-10-16', 0)];
  const stats = new Stats(days, '2026-10-16');
  assert.equal(stats.currentStreak, 2);
  assert.equal(stats.longestStreak, 2);
  assert.equal(new Stats([...days, day('2026-10-16', 1)], '2026-10-16').currentStreak, 3);
  assert.equal(new Stats(days, '2026-10-17').currentStreak, 0);
});

test('a record must beat, not tie, and ignores future and duplicate days', () => {
  const days = [day('2026-10-13', 20), day('2026-10-15', 3), day('2026-10-16', 19), day('2026-10-17', 900)];
  const tie = new Stats([...days, day('2026-10-16', 20)], '2026-10-16');
  assert.equal(tie.isNewRecord, false);
  assert.equal(tie.target, 21);
  assert.equal(tie.todayCount, 20);
  const best = new Stats([...days, day('2026-10-16', 21)], '2026-10-16');
  assert.equal(best.isNewRecord, true);
  assert.equal(best.bestDay, 21);
  assert.equal(best.progress, 1);
});

test('missing dates break the longest streak; year boundaries do not', () => {
  const stats = new Stats([day('2025-12-29', 2), day('2025-12-31', 1), day('2026-01-01', 4), day('2026-01-02', 3)], '2026-01-02');
  assert.equal(stats.currentStreak, 3);
  assert.equal(stats.longestStreak, 3);
  assert.equal(stats.weekTotal, 10);
});

test('weeks start on Monday rather than rolling seven-day windows', () => {
  const stats = new Stats([day('2026-10-04', 50), day('2026-10-05', 4), day('2026-10-11', 8),
    day('2026-10-12', 2), day('2026-10-16', 3)], '2026-10-16');
  assert.equal(stats.weekTotal, 5);
  assert.equal(stats.lastWeekTotal, 12);
  assert.equal(stats.bestWeek, 50);
});

test('calendar periods and year comparisons align across leap years', () => {
  const days = [day('2023-01-01', 7), day('2023-02-28', 5), day('2023-03-01', 11),
    day('2023-03-02', 1000), day('2023-12-31', 200), day('2024-02-28', 2),
    day('2024-02-29', 3), day('2024-03-01', 4), day('2024-03-02', 900)];
  const march = new Stats(days, '2024-03-01');
  assert.equal(march.todayCount, 4);
  assert.equal(march.weekTotal, 9);
  assert.equal(march.monthTotal, 4);
  assert.equal(march.yearTotal, 9);
  assert.equal(march.totalInYear(2023, '03-01'), 23);
  assert.equal(march.totalInYear(2023), 1223);
  const leap = new Stats(days, '2024-02-29');
  assert.equal(leap.monthTotal, 5);
  assert.equal(leap.totalInYear(2023, '02-29'), 12);
});

test('an empty history has an achievable first target', () => {
  const stats = new Stats([], '2026-10-16');
  assert.deepEqual([stats.todayCount, stats.target, stats.currentStreak, stats.longestStreak, stats.isNewRecord], [0, 1, 0, 0, false]);
});

test('day arithmetic matches the Gregorian calendar across centuries', () => {
  const key = date => date.toISOString().slice(0, 10);
  for (let t = Date.UTC(1899, 11, 25); t < Date.UTC(2101, 0, 8); t += 13 * 86400000) {
    const date = new Date(t);
    assert.equal(offset(key(date), 1), key(new Date(t + 86400000)));
    assert.equal(weekStart(key(date)), key(new Date(t - ((date.getUTCDay() + 6) % 7) * 86400000)));
  }
  assert.equal(offset('2024-03-01', -1), '2024-02-29');
  assert.equal(offset('2026-10-16', -3650), '2016-10-18');
  assert.equal(offset('not-a-date', 1), '1970-01-02');
  assert.equal(dayKey(new Date(2026, 9, 16, 0, 30)), '2026-10-16');
});

test('range sums match full scans', () => {
  const days = Array.from({ length: 900 }, (_, i) => day(offset('2024-01-01', i), (i * 7) % 13));
  const stats = new Stats([...days].reverse(), '2026-03-15');
  assert.equal(stats.count('2025-06-01'), days.find(d => d.date === '2025-06-01').contributionCount);
  assert.equal(stats.count('2030-01-01'), 0);
  const scanned = days.filter(d => d.date >= '2025-01-01' && d.date <= '2025-07-04').reduce((sum, d) => sum + d.contributionCount, 0);
  assert.equal(stats.totalInYear(2025, '07-04'), scanned);
  assert.equal(stats.activeDays, days.filter(d => d.date <= '2026-03-15' && d.contributionCount > 0).length);
  assert.deepEqual(stats.recent(3), [stats.count('2026-03-13'), stats.count('2026-03-14'), stats.count('2026-03-15')]);
});

test('celebrations ignore baselines, retries and corrections, but reset at midnight', () => {
  const tracker = new IncreaseTracker();
  const seen = [[12, '16'], [15, '16'], [15, '16'], [13, '16'], [15, '16'], [16, '16'], [2, '17'], [2, '17']]
    .map(([count, d]) => tracker.observe(`2026-10-${d}`, count));
  assert.deepEqual(seen, [0, 3, 0, 0, 0, 1, 2, 0]);
});
