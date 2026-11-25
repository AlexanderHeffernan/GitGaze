// Contribution figures from GitHub's own day buckets: never rebins commits or guesses private
// activity. Every derived figure is computed once, so views and the menu bar read them freely.
// Date keys are `YYYY-MM-DD` strings; arithmetic uses proleptic Gregorian day numbers, so DST and
// time zones can't shift a day.

/** Days since 1970-01-01 for a `YYYY-MM-DD` key (Howard Hinnant's days_from_civil). */
export function dayNumber(key) {
  const match = /^(\d+)-(\d+)-(\d+)$/.exec(key ?? '');
  if (!match) return 0;
  let [year, month, day] = match.slice(1).map(Number);
  if (month < 1 || month > 12 || day < 1 || day > 31) return 0;
  if (month <= 2) year -= 1;
  const era = Math.floor(year / 400);
  const yearOfEra = year - era * 400;
  const dayOfYear = Math.floor((153 * (month + (month > 2 ? -3 : 9)) + 2) / 5) + day - 1;
  const dayOfEra = yearOfEra * 365 + Math.floor(yearOfEra / 4) - Math.floor(yearOfEra / 100) + dayOfYear;
  return era * 146097 + dayOfEra - 719468;
}

const pad = (value, width) => String(value).padStart(width, '0');

/** Howard Hinnant's civil_from_days. */
export function keyForDayNumber(number) {
  const shifted = number + 719468;
  const era = Math.floor(shifted / 146097);
  const dayOfEra = shifted - era * 146097;
  const yearOfEra = Math.floor((dayOfEra - Math.floor(dayOfEra / 1460) + Math.floor(dayOfEra / 36524) - Math.floor(dayOfEra / 146096)) / 365);
  const dayOfYear = dayOfEra - (365 * yearOfEra + Math.floor(yearOfEra / 4) - Math.floor(yearOfEra / 100));
  const monthIndex = Math.floor((5 * dayOfYear + 2) / 153);
  const day = dayOfYear - Math.floor((153 * monthIndex + 2) / 5) + 1;
  const month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9;
  return `${pad(yearOfEra + era * 400 + (month <= 2 ? 1 : 0), 4)}-${pad(month, 2)}-${pad(day, 2)}`;
}

/** 0 for Monday through 6 for Sunday. 1970-01-01 was a Thursday. */
const daysSinceMonday = number => (((number + 3) % 7) + 7) % 7;

export const offset = (key, count) => keyForDayNumber(dayNumber(key) + count);
export const weekStart = key => { const n = dayNumber(key); return keyForDayNumber(n - daysSinceMonday(n)); };
/** The local calendar date, matching the "today" GitHub's buckets are read with. */
export const dayKey = (date = new Date()) => `${pad(date.getFullYear(), 4)}-${pad(date.getMonth() + 1, 2)}-${pad(date.getDate(), 2)}`;

export class Stats {
  constructor(days, today) {
    const unique = new Map();
    for (const day of days) if (day.date <= today) unique.set(day.date, day);
    const sorted = [...unique.values()].sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
    this.days = sorted;
    this.today = today;
    this.counts = new Map();
    this.running = [0];
    const weeks = new Map();
    let previousBest = 0, longest = 0, run = 0, active = 0, previous;
    for (const day of sorted) {
      const number = dayNumber(day.date);
      this.counts.set(day.date, day.contributionCount);
      this.running.push(this.running[this.running.length - 1] + day.contributionCount);
      const week = number - daysSinceMonday(number);
      weeks.set(week, (weeks.get(week) ?? 0) + day.contributionCount);
      if (day.date < today) previousBest = Math.max(previousBest, day.contributionCount);
      if (day.contributionCount > 0) active += 1;
      if (previous !== undefined && previous + 1 !== number) run = 0;
      run = day.contributionCount > 0 ? run + 1 : 0;
      longest = Math.max(longest, run);
      previous = number;
    }
    this.previousBest = previousBest;
    this.longestStreak = longest;
    this.bestWeek = Math.max(0, ...weeks.values());
    this.activeDays = active;
    this.todayCount = this.count(today);
    const todayNumber = dayNumber(today);
    let cursor = this.todayCount > 0 ? todayNumber : todayNumber - 1, streak = 0;
    while (this.count(keyForDayNumber(cursor)) > 0) { streak += 1; cursor -= 1; }
    this.currentStreak = streak;
    const start = todayNumber - daysSinceMonday(todayNumber);
    this.weekTotal = this.sum(keyForDayNumber(start), today);
    this.lastWeekTotal = this.sum(keyForDayNumber(start - 7), keyForDayNumber(start - 1));
    this.monthTotal = this.sum(today.slice(0, 7) + '-01', today);
    this.yearTotal = this.sum(today.slice(0, 4) + '-01-01', today);
  }

  get bestDay() { return Math.max(this.previousBest, this.todayCount); }
  get isNewRecord() { return this.todayCount > 0 && this.todayCount > this.previousBest; }
  get target() { return this.previousBest + 1; }
  get progress() { return Math.min(1, this.todayCount / this.target); }

  /** GitHub's count for a day key, or zero when the calendar has no bucket for it. */
  count(date) { return this.counts.get(date) ?? 0; }

  /** First index whose date no longer satisfies `before`. */
  boundary(before) {
    let low = 0, high = this.days.length;
    while (low < high) {
      const middle = (low + high) >> 1;
      if (before(this.days[middle].date)) low = middle + 1; else high = middle;
    }
    return low;
  }

  /** Inclusive sum over a date-key range. */
  sum(from, through) {
    const lower = this.boundary(date => date < from);
    const upper = Math.max(lower, this.boundary(date => date <= through));
    return this.running[upper] - this.running[lower];
  }

  /** Days in an inclusive date-key range, in calendar order. */
  between(from, through) {
    const lower = this.boundary(date => date < from);
    return this.days.slice(lower, Math.max(lower, this.boundary(date => date <= through)));
  }

  /** Compare calendar years through the same month/day, rather than a leap-sensitive day offset. */
  totalInYear(year, throughMonthDay = '12-31') { return this.sum(`${year}-01-01`, `${year}-${throughMonthDay}`); }

  /** The last `count` days ending today, oldest first. */
  recent(count) { return Array.from({ length: count }, (_, i) => this.count(offset(this.today, i - count + 1))); }
}

/** Tracks a day's high-water mark so retries and downward API corrections don't celebrate twice. */
export class IncreaseTracker {
  observe(day, count) {
    if (this.day === undefined) { this.day = day; this.highest = count; return 0; } // Sign-in is a baseline.
    if (this.day !== day) { this.day = day; this.highest = 0; }
    const increase = Math.max(0, count - this.highest);
    this.highest = Math.max(this.highest, count);
    return increase;
  }
}
