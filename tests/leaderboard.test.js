import test from 'node:test';
import assert from 'node:assert/strict';
import { rank, periodStart } from '../ui/js/leaderboard.js';

test('ties share a rank and the next rank skips past them', () => {
  const rows = rank([{ login: 'b', count: 5 }, { login: 'c', count: 9 }, { login: 'A', count: 5 }, { login: 'd', count: 0 }]);
  assert.deepEqual(rows.map(r => [r.login, r.rank]), [['c', 1], ['A', 2], ['b', 2], ['d', 4]]);
});

test('periods start at local calendar boundaries, with Monday weeks', () => {
  const now = new Date(2026, 10, 25, 15, 30); // Wednesday 25 November 2026
  const local = iso => { const d = new Date(iso); return [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getHours()]; };
  assert.deepEqual(local(periodStart('today', now)), [2026, 11, 25, 0]);
  assert.deepEqual(local(periodStart('week', now)), [2026, 11, 23, 0]);
  assert.deepEqual(local(periodStart('week', new Date(2026, 10, 29, 9))), [2026, 11, 23, 0]); // Sunday
  assert.deepEqual(local(periodStart('month', now)), [2026, 11, 1, 0]);
  assert.deepEqual(local(periodStart('year', now)), [2026, 1, 1, 0]);
});
