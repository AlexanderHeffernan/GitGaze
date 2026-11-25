// The dashboard flyout: header, widgets, settings, and the widget gallery.

import { html, render, useState, useEffect, useLayoutEffect, useRef } from '../vendor/preact-htm.js';
import { Store, moduleTitles } from './store.js';
import { invoke, listen, openURL, plugin, native } from './bridge.js';
import { icons } from './icons.js';
import { offset, weekStart } from './stats.js';
import { palettes, title, parseHex, accent, gold, background, systemDark, accentRGB } from './theme.js';
import { figures, drawLabel, drawTrayIcon, tooltip, menuStyles } from './status.js';
import { displayName } from './github.js';
import { markSVG } from './mark.js';
import { periods, memberLimit, scopeCommand } from './leaderboard.js';

const store = new Store();
window.gitgaze = store; // For debugging and UI tests.

const num = value => value.toLocaleString();
const shortDate = date => date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
const configurable = ['favourites', 'people', 'streak', 'heatmap', 'years', 'leaderboard'];

// ----- Small controls -----

function Icon({ name, size = 11 }) {
  return html`<svg class="icon" width=${size} height=${size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
    stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" dangerouslySetInnerHTML=${{ __html: icons[name] }} />`;
}

function IconButton({ icon, label, onClick, disabled, size }) {
  return html`<button class="quiet icon-button" title=${label} aria-label=${label} disabled=${disabled} onClick=${onClick}><${Icon} name=${icon} size=${size} /></button>`;
}

const Heading = ({ children }) => html`<div class="heading">${children}</div>`;
const Card = ({ children, class: extra = '' }) => html`<section class=${`card ${extra}`}>${children}</section>`;

function Toggle({ label, checked, onChange }) {
  return html`<label class="toggle"><span>${label}</span>
    <input type="checkbox" role="switch" checked=${checked} onChange=${event => onChange(event.currentTarget.checked)} /></label>`;
}

function ChoiceMenu({ label, value, options, onChange }) {
  return html`<label class="choice-menu"><span class="secondary">${label}</span>
    <span class="select"><select aria-label=${label} value=${String(value)} onChange=${event => {
      const option = options.find(([v]) => String(v) === event.currentTarget.value);
      onChange(option[0]);
    }}>${options.map(([v, text]) => html`<option value=${String(v)}>${text}</option>`)}</select><${Icon} name="chevrons" size=${9} /></span></label>`;
}

function ChoiceStrip({ label, value, options, onChange }) {
  return html`<div class="choice-strip" role="group" aria-label=${label}><div class="strip-label">${label}</div>
    <div class="strip">${options.map(([v, text]) => html`<button class=${v === value ? 'selected' : ''} aria-pressed=${v === value} onClick=${() => onChange(v)}>${text}</button>`)}</div></div>`;
}

/** The record instrument: ticks light up toward the next daily best. No artificial target. */
function RecordDial({ progress, active, record, size = 112 }) {
  const steps = size < 30 ? 16 : 40, lit = active ? Math.max(1, Math.ceil(Math.min(1, Math.max(0, progress)) * steps)) : 0;
  const mini = size < 30, w = mini ? 1.3 : 3, h = mini ? 3 : 8;
  return html`<svg class="dial" width=${size} height=${size} viewBox=${`0 0 ${size} ${size}`} aria-hidden="true">
    ${Array.from({ length: steps }, (_, i) => html`<rect x=${size / 2 - w / 2} y="1" width=${w} height=${h} rx="1.5"
      transform=${`rotate(${(i / steps) * 360} ${size / 2} ${size / 2})`}
      class=${i < lit ? (record ? 'tick gold' : 'tick lit') : 'tick'} />`)}</svg>`;
}

// ----- Widgets -----

function TodayCard({ stats }) {
  const complete = store.dashboard.historyComplete;
  return html`<${Card}>
    <div class="row"><${Heading}>TODAY<//><span class="spacer" /><span class="caption">${shortDate(new Date())}</span></div>
    <div class="today">
      <div class="today-dial" role="img" aria-label=${`${stats.todayCount} contributions today. ${Math.trunc(stats.progress * 100)} percent of your next daily record.`}>
        <${RecordDial} progress=${stats.progress} active=${stats.todayCount > 0} record=${stats.isNewRecord} />
        <div class="today-count" aria-hidden="true"><div class=${`today-number ${stats.todayCount > 99 ? 'compact' : ''}`}>${num(stats.todayCount)}</div><div class="tiny secondary">today</div></div>
      </div>
      <div class="today-best">
        <div title=${store.historyLabel}>
          <div class=${`eyebrow ${stats.isNewRecord ? 'gold' : ''}`}>${stats.isNewRecord ? 'NEW DAILY BEST' : 'DAILY BEST'}</div>
          ${!complete && html`<div class="tiny secondary">Past year only</div>`}
          <div class="baseline"><span class="best-number">${num(stats.bestDay)}</span><span class="tiny secondary">contributions</span></div>
        </div>
        ${stats.isNewRecord
          ? html`<div class="above gold"><${Icon} name="upRight" size=${10} /> +${stats.todayCount - stats.previousBest} above previous</div>`
          : html`<div class="to-beat">${Math.max(0, stats.target - stats.todayCount)} to beat it</div>`}
      </div>
    </div><//>`;
}

function StreakCard({ stats }) {
  return html`<${Card}><${Heading}>STREAK<//>
    <div class="streak">
      <div class="baseline"><span class="streak-number">${stats.currentStreak}</span><span class="small secondary">days</span></div>
      <span class="spacer" />
      <div class="marks">${Array.from({ length: 7 }, (_, i) => {
        const key = offset(stats.today, i - 6), active = stats.count(key) > 0;
        return html`<span class=${`mark ${active ? 'active' : ''} ${i === 6 ? 'today' : ''}`} title=${`${key}: ${active ? 'Active' : 'No contributions'}`} />`;
      })}</div>
      <div class="streak-best"><div class="streak-best-number">${stats.longestStreak}</div><div class="tiny secondary">best</div></div>
    </div><//>`;
}

const swatchLevels = { '#9be9a8': 1, '#0e4429': 1, '#40c463': 2, '#006d32': 2, '#30a14e': 3, '#26a641': 3, '#216e39': 4, '#39d353': 4 };
const level = day => swatchLevels[day.color?.toLowerCase()] ?? (day.contributionCount > 0 ? Math.min(4, Math.max(1, Math.floor(day.contributionCount / 5) + 1)) : 0);

/** Columns run Sunday to Saturday, ending with the week that contains today. */
function Heatmap({ days, today, weeks, width, height, showDates = true }) {
  const [hovered, setHovered] = useState(null);
  const sunday = offset(weekStart(offset(today, 1)), -1);
  const start = offset(sunday, -(weeks - 1) * 7);
  const indexed = new Map(days.map(day => [day.date, day]));
  const cells = Array.from({ length: weeks * 7 }, (_, i) => {
    const key = offset(start, i);
    return key <= today ? indexed.get(key) ?? { date: key, contributionCount: 0 } : null;
  });
  const pitch = width / weeks, gridHeight = height - (showDates ? 16 : 0);
  const size = Math.max(1, Math.min(pitch - 1.7, gridHeight / 7 - 1.7));
  const move = event => {
    const box = event.currentTarget.getBoundingClientRect();
    const column = Math.floor((event.clientX - box.left) / pitch), row = Math.floor((event.clientY - box.top) / (size + 1.7));
    setHovered(row >= 0 && row < 7 && column >= 0 && column < weeks ? cells[column * 7 + row] ?? null : null);
  };
  const label = hovered ? `${hovered.contributionCount} contributions · ${hovered.date}` : null;
  return html`<div class="heatmap" style=${{ width: `${width}px`, height: `${height}px` }}>
    <svg width=${width} height=${7 * (size + 1.7)} onMouseMove=${move} onMouseLeave=${() => setHovered(null)}
      role="img" aria-label=${`${weeks}-week contribution graph`}>
      ${cells.map((day, i) => day && html`<rect x=${Math.floor(i / 7) * pitch} y=${(i % 7) * (size + 1.7)} width=${size} height=${size} rx="1.2"
        class=${`heat l${level(day)} ${hovered?.date === day.date ? 'hovered' : ''}`}><title>${day.contributionCount} contributions · ${day.date}</title></rect>`)}
    </svg>
    ${showDates && html`<div class="heat-dates"><span>${label ?? offset(today, -(weeks - 1) * 7).slice(0, 7)}</span>${!hovered && html`<span>Today</span>`}</div>`}
  </div>`;
}

function HistoryCard() {
  const { profile } = store.dashboard, weeks = store.prefs.historyWeeks === 26 ? 26 : 53;
  return html`<${Card}><${Heading}>CONTRIBUTIONS<//>
    <div class="baseline"><span class="history-number">${num(profile.totalContributions)}</span><span class="small secondary">past year</span></div>
    <${Heatmap} days=${profile.days} today=${store.today} weeks=${weeks} width=${340} height=${weeks === 53 ? 59 : 94} /><//>`;
}

function MomentumCard({ stats }) {
  const start = weekStart(store.today);
  const values = Array.from({ length: 7 }, (_, i) => stats.count(offset(start, i)));
  const maximum = Math.max(1, ...values);
  return html`<${Card}><${Heading}>THIS WEEK<//>
    <div class="baseline"><span class="streak-number">${stats.weekTotal}</span><span class="small secondary">contributions</span><span class="spacer" /><span class="small secondary">${stats.lastWeekTotal} last week</span></div>
    <div class="week" title="Monday–Sunday · this week so far versus all of last week">${values.map((value, i) => html`
      <div class="week-day"><span class="micro secondary">${value}</span>
        <span class=${`bar ${value > 0 ? 'active' : ''}`} style=${{ height: `${Math.max(3, (42 * value) / maximum)}px` }} />
        <span class="tiny secondary">${'MTWTFSS'[i]}</span></div>`)}</div><//>`;
}

function RecordsCard({ stats }) {
  const record = (label, value, unit) => html`<div class="record"><div class="small secondary">${label}</div><div class="record-number">${num(value)}</div><div class="micro secondary">${unit}</div></div>`;
  return html`<${Card}><${Heading}>PERSONAL BESTS<//>
    <div class="row records">${record('Day', stats.bestDay, 'contributions')}<span class="spacer" />${record('Week', stats.bestWeek, 'contributions')}<span class="spacer" />${record('Streak', stats.longestStreak, 'days')}</div><//>`;
}

const position = monthDay => { const [m, d] = monthDay.split('-').map(Number); return [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335][m - 1] + d; };

function YearCard({ stats }) {
  const { dashboard, prefs, today } = store;
  const year = Number(today.slice(0, 4));
  const previous = dashboard.profile.years.includes(prefs.comparisonYear) && prefs.comparisonYear < year ? prefs.comparisonYear : year - 1;
  const cutoff = prefs.comparisonMode === 'ytd' ? today.slice(5) : '12-31';
  const current = stats.yearTotal, older = stats.totalInYear(previous, cutoff);
  if (!dashboard.historyComplete) {
    return html`<${Card}><${Heading}>YEAR IN PERSPECTIVE<//><div class="empty">${store.loadingHistory ? 'Loading yearly history…' : 'Yearly history unavailable. Refresh to try again.'}</div><//>`;
  }
  const W = 340, H = 100, maximum = Math.max(1, current, older), end = position(cutoff);
  const line = value => {
    let count = 0, points = [[0, H]];
    for (const day of stats.between(`${value}-01-01`, `${value}-${cutoff}`)) {
      count += day.contributionCount;
      points.push([(position(day.date.slice(5)) / end) * W, H * (1 - count / maximum)]);
    }
    return points;
  };
  const path = points => points.map(([x, y], i) => `${i ? 'L' : 'M'}${x.toFixed(1)},${y.toFixed(1)}`).join('');
  const now = line(year), then = line(previous), last = now[now.length - 1];
  return html`<${Card}><${Heading}>YEAR IN PERSPECTIVE<//>
    <div class="baseline"><span class="streak-number">${num(current)}</span><span class="small secondary">${year}</span><span class="spacer" />
      <span class="delta">${current >= older ? '+' : '−'}${num(Math.abs(current - older))}</span></div>
    <svg class="year-chart" width=${W} height=${H} role="img" aria-label=${`${year} and ${previous} cumulative contributions, ${prefs.comparisonMode === 'ytd' ? 'same point in each year' : 'full years'}`}>
      <defs><linearGradient id="area" x1="0" y1="0" x2="0" y2="1"><stop offset="0" class="area-top" /><stop offset="1" class="area-bottom" /></linearGradient></defs>
      ${[0, 1, 2].map(i => html`<line x1="0" x2=${W} y1=${(H * i) / 2} y2=${(H * i) / 2} class="grid" />`)}
      <path d=${`${path(now)}L${last[0].toFixed(1)},${H}Z`} fill="url(#area)" />
      <path d=${path(then)} class="previous-line" />
      <path d=${path(now)} class="current-line" />
    </svg>
    <div class="row small"><span class="accent"><span class="legend-dot" />${year} · ${num(current)}</span><span class="spacer" /><span class="secondary">${previous} · ${num(older)}</span></div>
    <div class="tiny secondary">${prefs.comparisonMode === 'ytd' ? `Both years through ${shortDate(new Date())}` : 'Current year to date · previous full year'}</div><//>`;
}

function Avatar({ person, size = 27 }) {
  const [failed, setFailed] = useState(false);
  // GitHub avatars in the app; the bundled sample faces in browser previews.
  const valid = native ? /^https:\/\/avatars\.githubusercontent\.com\//.test(person.avatarUrl ?? '') : /^demo\/[a-z]+\.jpg$/.test(person.avatarUrl ?? '');
  return html`<span class="avatar" style=${{ width: `${size}px`, height: `${size}px` }}>${valid && !failed
    ? html`<img src=${person.avatarUrl} alt="" referrerpolicy="no-referrer" onError=${() => setFailed(true)} />`
    : person.login[0].toUpperCase()}</span>`;
}

function PersonRow({ person }) {
  const [expanded, setExpanded] = useState(false);
  const profile = store.dashboard.people?.[person.login];
  const stats = profile && store.statsFor(person.login);
  const metric = (label, count) => html`<div class="metric"><div class=${`metric-number ${label === 'Today' && count > 0 ? 'accent' : ''}`}>${num(count)}</div><div class="micro-7 secondary">${label}</div></div>`;
  const graph = (weeks, dates, width, height) => html`<button class="graph-button" onClick=${() => setExpanded(!expanded)}
    title=${expanded ? 'Collapse full-year history' : 'Expand full-year history'} aria-label=${`${expanded ? 'Collapse' : 'Expand'} ${person.login}’s contribution graph`} aria-expanded=${expanded}>
    <${Heatmap} days=${profile.days} today=${store.today} weeks=${weeks} width=${width} height=${height} showDates=${dates} /></button>`;
  return html`<div class="person">
    <div class="person-top">
      <div class="person-info">
        <div class="person-name"><${Avatar} person=${person} size=${21} />
          <button class="quiet link" onClick=${() => openURL(`https://github.com/${person.login}`)} title=${`Open ${person.login} on GitHub`}>${displayName(person)}</button></div>
        ${stats ? html`<div class="metrics">${metric('Today', stats.todayCount)}${metric('Week', stats.weekTotal)}${metric('Month', stats.monthTotal)}${metric('Year', stats.yearTotal)}</div>`
          : html`<div class="tiny secondary">History not loaded</div>`}
      </div>
      ${profile && graph(26, false, 142, 37)}
    </div>
    ${expanded && profile && html`<div class="person-full">${graph(53, true, 330, 62)}</div>`}
  </div>`;
}

function PeopleCard({ favouritesOnly }) {
  const people = favouritesOnly ? store.favouritePeople : store.orderedPeople;
  const shown = people.slice(0, store.peopleLimit);
  return html`<${Card}><${Heading}>${favouritesOnly ? 'FAVOURITES' : 'FOLLOWING'}<//>
    ${store.peopleError && html`<div class="small gold">${store.peopleError}</div>`}
    ${!people.length && html`<div class="empty-people secondary">Choose people in this widget’s settings.</div>`}
    ${shown.map((person, i) => html`<${PersonRow} key=${person.login} person=${person} />${i < shown.length - 1 && html`<div class="divider" />`}`)}
    ${people.length > store.peopleLimit && html`<button class="quiet more" onClick=${() => { store.peopleLimit += 12; store.changed(); void store.loadPeople(); }}>Show more</button>`}<//>`;
}

/** Search and ordering live only on the back face; the front never inherits the search state. */
function PeopleSettings() {
  const [search, setSearch] = useState('');
  const [limit, setLimit] = useState(20);
  const term = search.toLocaleLowerCase();
  const matches = store.orderedPeople.filter(p => !term || p.login.toLocaleLowerCase().includes(term) || displayName(p).toLocaleLowerCase().includes(term));
  const favourites = store.favouritePeople;
  return html`<div class="people-settings">
    <label class="search"><${Icon} name="search" /><input type="text" placeholder="Find someone you follow" value=${search} onInput=${e => setSearch(e.currentTarget.value)} />
      ${search && html`<${IconButton} icon="x" label="Clear search" onClick=${() => setSearch('')} />`}</label>
    ${matches.slice(0, limit).map(person => {
      const selected = store.prefs.favourites.includes(person.login);
      return html`<div class="person-option" key=${person.login}><${Avatar} person=${person} size=${25} />
        <span class="option-name" title=${`@${person.login}`}>${displayName(person)}</span><span class="spacer" />
        ${selected && html`<${IconButton} icon="up" label=${`Move ${person.login} up`} disabled=${favourites[0]?.login === person.login} onClick=${() => store.moveFavourite(person.login, -1)} />
          <${IconButton} icon="down" label=${`Move ${person.login} down`} disabled=${favourites[favourites.length - 1]?.login === person.login} onClick=${() => store.moveFavourite(person.login, 1)} />`}
        <${IconButton} icon=${selected ? 'minus' : 'add'} label=${`${selected ? 'Unfavourite' : 'Favourite'} ${person.login}`} onClick=${() => store.toggleFavourite(person.login)} /></div>`;
    })}
    ${!matches.length && html`<div class="empty secondary">No matching people</div>`}
    ${matches.length > limit && html`<button class="quiet" onClick=${() => setLimit(limit + 20)}>Show more</button>`}
  </div>`;
}

/** Members ranked by contributions to the organisation's repositories this period. */
function LeaderboardCard() {
  const [limit, setLimit] = useState(10);
  const { organizations, result, loading, error } = store.board;
  const period = periods.find(([key]) => key === store.prefs.leaderboardPeriod)?.[1] ?? 'Week';
  const viewer = store.dashboard.profile.person.login;
  const rows = result?.rows ?? [];
  const maximum = Math.max(1, ...rows.map(row => row.count));
  const body = () => {
    if (error && !rows.length) return html`<div class="small gold">${error}</div>`;
    if (organizations && !organizations.length) return html`<div class="empty-people secondary">You aren’t a member of any GitHub organisations.</div>`;
    if (!result) return html`<div class="empty-people secondary">${loading ? 'Loading the leaderboard…' : 'Refresh to load the leaderboard.'}</div>`;
    return html`<div class="board">${rows.slice(0, limit).map(row => html`
      <div class=${`board-row ${row.login.toLowerCase() === viewer.toLowerCase() ? 'viewer' : ''}`} key=${row.login}>
        <span class="board-rank">${row.rank}</span><${Avatar} person=${row} size=${21} />
        <button class="quiet link board-name" onClick=${() => openURL(`https://github.com/${row.login}`)} title=${`Open ${row.login} on GitHub`}>${displayName(row)}</button>
        <span class="board-bar"><span style=${{ width: `${(row.count / maximum) * 100}%` }} /></span>
        <span class="board-count">${num(row.count)}</span></div>`)}</div>
      ${rows.length > limit && html`<button class="quiet more" onClick=${() => setLimit(limit + 10)}>Show more</button>`}
      ${result.partial && html`<div class="tiny secondary">Ranked from the first ${memberLimit} of ${num(result.total)} members.</div>`}`;
  };
  return html`<${Card}><div class="row"><${Heading}>LEADERBOARD<//><span class="spacer" />
    <span class="caption">${result ? `${result.organization.name || result.organization.login} · ${period}` : period}</span></div>
    ${error && rows.length > 0 && html`<div class="small gold">${error}</div>`}
    ${body()}<//>`;
}

function WidgetContent({ module }) {
  const { stats } = store;
  if (!stats || !store.dashboard) return null;
  switch (module) {
    case 'today': return html`<${TodayCard} stats=${stats} />`;
    case 'streak': return html`<${StreakCard} stats=${stats} />`;
    case 'heatmap': return html`<${HistoryCard} />`;
    case 'favourites': return html`<${PeopleCard} favouritesOnly=${true} />`;
    case 'people': return html`<${PeopleCard} favouritesOnly=${false} />`;
    case 'momentum': return html`<${MomentumCard} stats=${stats} />`;
    case 'records': return html`<${RecordsCard} stats=${stats} />`;
    case 'years': return html`<${YearCard} stats=${stats} />`;
    case 'leaderboard': return html`<${LeaderboardCard} />`;
  }
}

function WidgetOptions({ module }) {
  const { prefs } = store;
  switch (module) {
    case 'favourites': case 'people': return html`<${PeopleSettings} />`;
    case 'streak': return html`<${Toggle} label="Streak reminder" checked=${prefs.streakReminder} onChange=${v => store.enableReminder(v)} />
      ${prefs.streakReminder && html`<${ChoiceMenu} label="When today is empty after" value=${prefs.reminderHour}
        options=${Array.from({ length: 24 }, (_, h) => [h, `${String(h).padStart(2, '0')}:00`])} onChange=${h => store.set({ reminderHour: h })} />`}`;
    case 'heatmap': return html`<${ChoiceStrip} label="Visible history" value=${prefs.historyWeeks === 26 ? 26 : 53} options=${[[26, '6 months'], [53, 'Year']]} onChange=${w => store.set({ historyWeeks: w })} />`;
    case 'years': {
      const year = Number(store.today.slice(0, 4));
      const years = (store.dashboard?.profile.years ?? []).filter(y => y < year).sort((a, b) => b - a);
      return html`<div class="year-options"><${ChoiceMenu} label="Compare with" value=${years.includes(prefs.comparisonYear) ? prefs.comparisonYear : 0}
        options=${[[0, 'Previous year'], ...years.map(y => [y, String(y)])]} onChange=${y => store.set({ comparisonYear: y })} />
        <${ChoiceStrip} label="Period" value=${prefs.comparisonMode} options=${[['ytd', 'Same point in year'], ['full', 'Full years']]} onChange=${m => store.set({ comparisonMode: m })} /></div>`;
    }
    case 'leaderboard': {
      const organizations = store.board.organizations ?? [];
      const current = organizations.find(o => o.login === prefs.leaderboardOrg)?.login ?? organizations[0]?.login ?? '';
      const choose = patch => { store.set(patch); void store.loadLeaderboard(); };
      return html`<div class="year-options">
        ${organizations.length ? html`<${ChoiceMenu} label="Organisation" value=${current}
          options=${organizations.map(o => [o.login, o.name || o.login])} onChange=${login => choose({ leaderboardOrg: login })} />`
          : html`<div class="small secondary">${store.board.loading ? 'Finding your organisations…' : 'No organisations found for this account.'}</div>`}
        <${ChoiceStrip} label="Period" value=${prefs.leaderboardPeriod} options=${periods} onChange=${period => choose({ leaderboardPeriod: period })} />
        <div class="tiny secondary">Counts commits, pull requests, reviews and issues in the organisation’s repositories you can see, private ones included.</div>
        ${store.board.result && !store.board.result.scoped && html`<${ScopeTip} />`}</div>`;
    }
  }
  return null;
}

/** Counting from repositories already includes private work; GitHub's exact counts are optional. */
function ScopeTip() {
  const [copied, setCopied] = useState(false);
  const copy = async () => { try { await navigator.clipboard.writeText(scopeCommand); setCopied(true); setTimeout(() => setCopied(false), 1500); } catch { /* The command stays selectable. */ } };
  return html`<div class="tiny secondary scope-note">For GitHub’s exact contribution counts, run this once in a terminal, then refresh:
    <div class="scope-command"><code>${scopeCommand}</code><button class="quiet link" onClick=${copy}>${copied ? 'Copied' : 'Copy'}</button></div></div>`;
}

/** Both faces keep their own state; only the facing side is interactive or exposed to accessibility. */
function Flipping({ flipped, front, back }) {
  const frontRef = useRef(), backRef = useRef();
  const [height, setHeight] = useState(null);
  useLayoutEffect(() => {
    const measure = () => setHeight((flipped ? backRef : frontRef).current?.offsetHeight ?? null);
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(frontRef.current);
    observer.observe(backRef.current);
    return () => observer.disconnect();
  }, [flipped]);
  return html`<div class=${`flip ${flipped ? 'flipped' : ''}`} style=${height ? { height: `${height}px` } : {}}>
    <div class="face front" ref=${frontRef} inert=${flipped} aria-hidden=${flipped}>${front}</div>
    <div class="face back" ref=${backRef} inert=${!flipped} aria-hidden=${!flipped}>${back}</div></div>`;
}

function WidgetShell({ module, configuring, onConfigure }) {
  const visible = store.visibleModules, name = moduleTitles[module];
  return html`<div class="widget">
    <${Flipping} flipped=${configuring}
      front=${html`<${WidgetContent} module=${module} />
        <div class="widget-tools">
          <${IconButton} icon="up" label=${`Move ${name} up`} disabled=${visible[0] === module} onClick=${() => store.moveModule(module, -1)} />
          <${IconButton} icon="down" label=${`Move ${name} down`} disabled=${visible[visible.length - 1] === module} onClick=${() => store.moveModule(module, 1)} />
          ${configurable.includes(module) && html`<${IconButton} icon="sliders" label=${`Configure ${name}`} onClick=${onConfigure} />`}
          <${IconButton} icon="minus" label=${`Remove ${name}`} onClick=${() => store.setHidden(module, true)} /></div>`}
      back=${html`<${Card} class="options"><div class="row"><${Heading}>${name.toUpperCase()}<//><span class="spacer" />
        <button class="quiet back-button small-label" onClick=${onConfigure}><${Icon} name="undo" size=${10} /> Back</button></div>
        ${configuring && html`<${WidgetOptions} module=${module} />`}<//>`} />
  </div>`;
}

function Gallery() {
  const hidden = store.prefs.modules.filter(m => store.prefs.hidden.includes(m));
  return html`<div class="gallery">
    ${!hidden.length && html`<div class="empty secondary">All widgets added</div>`}
    ${hidden.map(module => html`<button class="tile gallery-item" key=${module} aria-label=${`Add ${moduleTitles[module]}`} onClick=${() => store.setHidden(module, false)}>
      <div class="row gallery-title"><span>${moduleTitles[module]}</span><span class="spacer" /><span class="add-badge"><${Icon} name="plus" size=${11} /></span></div>
      <div class="gallery-preview" inert aria-hidden="true"><${WidgetContent} module=${module} /></div></button>`)}
  </div>`;
}

function Welcome() {
  return html`<div class="welcome">
    <${RecordDial} progress=${0.65} active=${true} size=${64} />
    <h2>Your work, in view.</h2>
    <p class="secondary">Connect with your GitHub CLI session.</p>
    ${!store.ghInstalled && html`<code>${store.platform === 'windows' ? 'winget install GitHub.cli' : 'brew install gh'}</code>`}
    <code>gh auth login</code>
    <button class="tile connect" disabled=${store.loading} onClick=${() => store.useCLI()}><span>Connect GitHub CLI</span><span class="spacer" />→</button>
  </div>`;
}

// ----- Settings -----

function StylePreview({ style }) {
  const ref = useRef();
  const dark = isDark();
  useEffect(() => {
    const canvas = ref.current, f = { ...figures(store, style, true), stale: false };
    // Windows previews the tray icon at about its taskbar size; macOS shows the full label.
    const size = store.platform === 'windows' ? { width: 24, height: 24 } : drawLabel(canvas, f, { prefs: store.prefs, dark, scale: 2 });
    if (store.platform === 'windows') drawTrayIcon(canvas, f, { prefs: store.prefs, dark });
    canvas.style.width = `${size.width}px`; canvas.style.height = `${size.height}px`;
  });
  return html`<canvas ref=${ref} aria-hidden="true" />`;
}

function HexField({ label, value, onChange }) {
  const [draft, setDraft] = useState(value);
  useEffect(() => { if (draft.toUpperCase() !== value) setDraft(value); }, [value]);
  const rgb = parseHex(value) ?? [0.69, 0.32, 0.87];
  const hex = '#' + rgb.map(c => Math.round(c * 255).toString(16).padStart(2, '0')).join('');
  const invalid = draft && !parseHex(draft);
  return html`<div class="hex-field"><div class="tiny secondary">${label}</div>
    <div class=${`hex-input ${invalid ? 'invalid' : ''}`}><input type="color" value=${hex} aria-label=${label} onInput=${e => onChange(e.currentTarget.value.slice(1).toUpperCase())} />
      <span class="secondary">#</span><input type="text" value=${draft} placeholder="RRGGBB" aria-label=${`${label} hex colour`} onInput=${e => {
        const next = e.currentTarget.value; setDraft(next);
        if (parseHex(next)) onChange(next.replace(/[#\s]/g, '').toUpperCase());
      }} /></div></div>`;
}

async function confirmPushDetection() {
  const message = 'Adds Git\'s trace2.eventTarget setting to your user configuration. Events stay on this computer, in memory. Turning this off removes only Stoke\'s setting. Clients that bypass Git aren\'t covered.';
  const dialog = plugin('dialog');
  if (!dialog) return window.confirm(message);
  return dialog.ask(message, { title: 'Enable push detection across repositories?', okLabel: 'Enable Git integration', cancelLabel: 'Cancel' });
}

function Settings() {
  const { prefs } = store;
  const [version, setVersion] = useState('');
  useEffect(() => { plugin('app')?.getVersion().then(setVersion); }, []);
  const appearance = (value, label, icon) => html`<button class=${`tile appearance ${prefs.appearance === value ? 'selected' : ''}`} aria-pressed=${prefs.appearance === value}
    title=${`${label} appearance`} onClick=${() => store.set({ appearance: value })}>
    <span class=${`window-art ${value}`}><span class="art-accent" /><span class="art-line" /><span class="art-line short" />${value === 'system' && html`<span class="art-dark" />`}</span>
    <span class="tile-label"><${Icon} name=${icon} size=${10} /> ${label}</span></button>`;
  const person = store.dashboard?.profile.person;
  return html`<div class="settings">
    <${Card}><${Heading}>APPEARANCE<//>
      <div class="appearances">${appearance('system', 'Auto', 'contrast')}${appearance('light', 'Light', 'sun')}${appearance('dark', 'Dark', 'moon')}</div>
      <div class="palettes">${[...Object.keys(palettes), 'custom'].map(name => {
        const swatch = accent({ ...prefs, palette: name }, isDark());
        const selected = prefs.palette === name;
        return html`<button class=${`tile palette ${selected ? 'selected' : ''}`} title=${title(name)} aria-label=${`${title(name)} theme`} aria-pressed=${selected}
          style=${{ '--swatch': swatch }} onClick=${() => store.set({ palette: name })}>
          <span class="swatch">${selected && html`<${Icon} name="check" size=${9} />`}</span><span class="micro-8 secondary">${title(name)}</span></button>`;
      })}</div>
      ${prefs.palette === 'custom' && html`<div class="hex-fields"><${HexField} label="Light accent" value=${prefs.customLight} onChange=${v => store.set({ customLight: v })} />
        <${HexField} label="Dark accent" value=${prefs.customDark} onChange=${v => store.set({ customDark: v })} /></div>`}<//>
    <${Card}><${Heading}>${store.platform === 'windows' ? 'TRAY ICON' : 'MENU BAR'}<//>
      ${store.platform === 'windows' && html`<div class="tiny secondary">Tray icons are small squares, so each style has a compact version. Hover the icon for your streak.</div>`}
      <div class="styles">${Object.keys(menuStyles).map(style => html`<button class=${`tile style ${prefs.menuStyle === style ? 'selected' : ''}`}
        aria-pressed=${prefs.menuStyle === style} title=${`${title(style)} menu bar display`} onClick=${() => store.set({ menuStyle: style })}>
        <span class="style-preview"><${StylePreview} style=${style} /></span><span class="tile-label">${title(style)}</span></button>`)}</div>
      ${store.platform !== 'windows' && html`<${Toggle} label="Show streak" checked=${prefs.menuStreak} onChange=${v => store.set({ menuStreak: v })} />`}<//>
    <${Card}><${Heading}>CELEBRATIONS<//>
      <${Toggle} label="Visual celebrations" checked=${prefs.visualCelebrations} onChange=${v => store.set({ visualCelebrations: v })} />
      <div class="celebrations">${[['fireworks', 'Fireworks', 'sparkles'], ['nova', 'Supernova', 'sun'], ['meteors', 'Meteor shower', 'sparkle']].map(([style, label, icon]) => html`
        <button class=${`tile celebration ${prefs.celebrationStyle === style ? 'selected' : ''}`} aria-pressed=${prefs.celebrationStyle === style}
          onClick=${() => { store.set({ celebrationStyle: style }); store.showCelebration(3, false, true); }}>
          <span class="accent"><${Icon} name=${icon} size=${19} /></span><span class="micro-9">${label}</span></button>`)}</div>
      <${Toggle} label="Milestone notifications" checked=${prefs.notifications} onChange=${v => store.enableNotifications(v)} /><//>
    <${Card}><${Heading}>GENERAL<//>
      <${Toggle} label="Launch at login" checked=${store.launchAtLogin} onChange=${v => store.toggleLaunchAtLogin(v)} />
      <${Toggle} label="Detect pushes automatically" checked=${prefs.detectPushes} onChange=${async v => {
        if (v && !(await confirmPushDetection())) return store.changed();
        await store.enablePushDetection(v);
      }} /><//>
    <${Card}><div class="row"><${Heading}>UPDATES<//><span class="spacer" /><span class="small secondary">${version || 'Development'}</span></div>
      <${Toggle} label="Check automatically" checked=${prefs.autoUpdate} onChange=${v => store.set({ autoUpdate: v })} />
      <div class="row"><span class="small secondary">Verified updates, installed in place.</span><span class="spacer" />
        <button class="quiet" disabled=${!native || store.checkingUpdates} onClick=${() => store.checkForUpdates(true)}>Check now</button></div><//>
    ${person && html`<div class="account"><${Avatar} person=${person} size=${28} /><div><div class="account-name">${displayName(person)}</div><div class="micro-9 secondary">@${person.login}</div></div>
      <span class="spacer" /><span class="micro-9 secondary">GitHub CLI</span></div>`}
  </div>`;
}

// ----- Frame -----

function isDark() {
  const { appearance } = store.prefs;
  return appearance === 'dark' || (appearance === 'system' && systemDark());
}

function updatedText() {
  if (store.loading) return 'Refreshing…';
  if (!store.dashboard) return 'Not connected';
  const seconds = Math.max(0, Math.floor((Date.now() - store.updatedAt) / 1000));
  return seconds < 60 ? 'Updated now' : seconds < 3600 ? `Updated ${Math.floor(seconds / 60)}m ago` : `Updated ${Math.floor(seconds / 3600)}h ago`;
}

/** A draggable overlay scroll knob that appears while scrolling or hovering. */
function KnobView({ scroll, handle }) {
  const node = useRef(), timer = useRef();
  const update = (active = false) => {
    const main = scroll.current, knob = node.current;
    if (!main || !knob) return;
    const ratio = main.clientHeight / main.scrollHeight;
    knob.hidden = ratio >= 1;
    const height = Math.max(24, main.clientHeight * ratio);
    knob.style.height = `${height}px`;
    knob.style.top = `${(main.scrollTop / (main.scrollHeight - main.clientHeight || 1)) * (main.clientHeight - height)}px`;
    if (active) { knob.classList.add('active'); clearTimeout(timer.current); timer.current = setTimeout(() => knob.classList.remove('active'), 900); }
  };
  if (handle) handle.current = { update };
  useEffect(() => {
    const observer = new ResizeObserver(() => update());
    observer.observe(scroll.current);
    for (const child of scroll.current.children) observer.observe(child);
    update();
    return () => observer.disconnect();
  });
  const drag = event => {
    const main = scroll.current, knob = node.current, startY = event.clientY, start = main.scrollTop;
    const scale = (main.scrollHeight - main.clientHeight) / (main.clientHeight - knob.offsetHeight || 1);
    knob.classList.add('dragging');
    knob.setPointerCapture(event.pointerId);
    const move = e => { main.scrollTop = start + (e.clientY - startY) * scale; };
    const end = () => { knob.classList.remove('dragging'); knob.removeEventListener('pointermove', move); };
    knob.addEventListener('pointermove', move);
    knob.addEventListener('pointerup', end, { once: true });
  };
  return html`<div class="knob" ref=${node} onPointerDown=${drag} aria-hidden="true" />`;
}

function Dashboard() {
  const [configuring, setConfiguring] = useState(null);
  const scroll = useRef(), knob = useRef();
  const { page } = store;
  useEffect(() => { scroll.current.scrollTop = 0; }, [page]);
  useEffect(() => {
    const key = event => {
      if (event.key !== 'Escape' || event.defaultPrevented) return;
      if (store.page !== 'dashboard') { store.page = 'dashboard'; store.changed(); } else void invoke('hide_popover');
    };
    addEventListener('keydown', key);
    return () => removeEventListener('keydown', key);
  }, []);
  const go = next => () => { store.page = next; store.changed(); };
  return html`<div class="panel">
    <header>
      ${page === 'dashboard' && html`<span class="logo" dangerouslySetInnerHTML=${{ __html: markSVG(accentRGB(store.prefs, isDark()), { size: 17 }) }} />`}
      <h1>${page === 'settings' ? 'Settings' : page === 'gallery' ? 'Add widgets' : 'Stoke'}</h1><span class="spacer" />
      ${page !== 'dashboard'
        ? html`<button class="quiet back-button" onClick=${go('dashboard')}><${Icon} name="back" /> Back</button>`
        : html`<${IconButton} icon="plus" label="Add widgets" onClick=${go('gallery')} />
          <button class=${`quiet icon-button refresh ${store.loading ? 'spinning' : ''}`} disabled=${store.loading} title=${store.loading ? 'Refreshing…' : 'Refresh'}
            aria-label=${store.loading ? 'Refreshing contributions' : 'Refresh contributions'} onClick=${() => store.refresh(true)}><${Icon} name="refresh" size=${12} /></button>
          <${IconButton} icon="sliders" label="Settings" onClick=${go('settings')} />`}
    </header>
    <div class="scroller"><main ref=${scroll} onScroll=${() => knob.current?.update(true)}>
      ${store.error && html`<div class="message"><${Icon} name="offline" /> <span>${store.error}</span></div>`}
      ${page === 'settings' ? html`<${Settings} />`
        : page === 'gallery' ? html`<${Gallery} />`
        : store.dashboard ? html`${store.visibleModules.map(module => html`<${WidgetShell} key=${module} module=${module} configuring=${configuring === module}
            onConfigure=${() => setConfiguring(configuring === module ? null : module)} />`)}
          ${!store.visibleModules.length && html`<button class="quiet add-widget" onClick=${go('gallery')}><${Icon} name="plus" /> Add a widget</button>`}`
        : store.loading ? html`<div class="syncing"><span class="spinner" /> Syncing activity…</div>`
        : html`<${Welcome} />`}
    </main><${KnobView} scroll=${scroll} handle=${knob} /></div>
    <footer>
      <span class=${`status-dot ${store.error ? 'stale' : ''}`} /><span class="micro-9 secondary">${updatedText()}</span><span class="spacer" />
      ${store.dashboard && html`<button class="quiet micro-9" onClick=${() => openURL(`https://github.com/${store.dashboard.profile.person.login}`)}>@${store.dashboard.profile.person.login}</button>`}
    </footer>
  </div>`;
}

function App() {
  const [, setVersion] = useState(0);
  useEffect(() => {
    const unsubscribe = store.subscribe(() => setVersion(v => v + 1));
    setVersion(v => v + 1); // Catch changes made before this subscription existed.
    return unsubscribe;
  }, []);
  return html`<${Dashboard} key=${store.presentation} />`;
}

// ----- Theme and tray -----

function applyTheme() {
  const dark = isDark(), root = document.documentElement;
  root.dataset.scheme = dark ? 'dark' : 'light';
  root.style.setProperty('--accent-rgb', accentRGB(store.prefs, dark).map(v => Math.round(v * 255)).join(' '));
  root.style.setProperty('--gold', gold(dark));
  root.style.setProperty('--background', background(dark));
}

let lastTray = '', menuBarDark = null;
/** macOS tints the menu bar from the wallpaper, so ask the shell rather than the system setting. */
async function checkMenuBar() {
  if (!native || store.platform !== 'macos') return;
  const dark = await invoke('menu_bar_dark');
  if (dark !== menuBarDark) { menuBarDark = dark; updateTray(); }
}
function updateTray() {
  if (!native) return;
  const f = { ...figures(store) };
  const dark = menuBarDark ?? systemDark(), windows = store.platform === 'windows';
  const key = JSON.stringify([f, dark, store.prefs.palette, store.prefs.customLight, store.prefs.customDark, store.flashing, windows]);
  if (key === lastTray) return;
  lastTray = key;
  const canvas = document.createElement('canvas');
  const size = windows ? drawTrayIcon(canvas, f, { prefs: store.prefs, dark }) : drawLabel(canvas, f, { prefs: store.prefs, dark, scale: 2, celebrating: store.flashing });
  void invoke('set_tray', { png: canvas.toDataURL('image/png').split(',')[1], width: size.width, height: size.height, tooltip: tooltip(store) });
}

store.subscribe(() => { applyTheme(); updateTray(); });
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => { applyTheme(); updateTray(); void checkMenuBar(); store.changed(); });

listen('tick', checkMenuBar);
setTimeout(checkMenuBar, 500);

listen('popover-shown', ({ arrow }) => {
  document.documentElement.style.setProperty('--arrow-x', `${arrow}px`);
  store.presented();
});

store.subscribe(() => { document.documentElement.dataset.platform = store.platform; });
render(html`<${App} />`, document.getElementById('app'));
store.start().catch(error => console.error(error));
