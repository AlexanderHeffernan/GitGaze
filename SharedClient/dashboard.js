(() => {
  'use strict';
  const core = globalThis.gitGazeCore;
  const $ = id => document.getElementById(id);
  const main = $('content');
  const ns = 'http://www.w3.org/2000/svg';
  const post = (action, value) => {
    if (window !== window.top) return;
    const message = { action, value };
    if (window.webkit?.messageHandlers.gitgaze) window.webkit.messageHandlers.gitgaze.postMessage(message);
    else window.chrome?.webview?.postMessage(message);
  };
  const el = (tag, css, text) => {
    const node = document.createElement(tag);
    if (css) node.className = css;
    if (text !== undefined) node.textContent = text;
    return node;
  };
  const svg = (tag, attrs) => {
    const node = document.createElementNS(ns, tag);
    for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, value);
    return node;
  };
  const button = (text, label, fn, disabled = false) => {
    const node = el('button', '', typeof text === 'string' ? text : undefined);
    if (typeof text !== 'string') node.append(text);
    node.setAttribute('aria-label', label);
    node.title = label;
    node.disabled = disabled;
    node.addEventListener('click', fn);
    return node;
  };
  const group = (css, ...children) => { const node = el('div', css); node.append(...children); return node; };
  const icon = path => {
    const graphic = svg('svg', { class:'action-icon', viewBox:'0 0 16 16', 'aria-hidden':'true' });
    graphic.append(svg('path', { d:path, fill:'none', stroke:'currentColor', 'stroke-width':1.35, 'stroke-linecap':'round', 'stroke-linejoin':'round' }));
    return graphic;
  };
  const text = (s, css = 'secondary') => el('div', css, s);
  const num = n => n.toLocaleString();
  const palettes = { violet:['6E4AC9','B09CFF'], coral:['C44036','FF917D'], ice:['0F6EA3','6BCEF7'], graphite:['4A546B','D4D9E8'],
    mint:['14785C','75DBBA'], rose:['BF306E','FF8FBD'], amber:['A35C08','FFBF59'], cobalt:['2E5CD4','75A1FF'],
    orchid:['963BBF','DB8FFF'], lagoon:['0A737A','4DD9DB'] };
  const systemDark = matchMedia('(prefers-color-scheme: dark)');
  let data, prefs, today, stats, page = 'GitGaze', configuring, status = '', error, live;
  let peopleSearch = '', settingsLimit = 20, peopleLimit = 12;
  const expandedPeople = new Set();
  const requests = new Map();
  let serial = 0, activity;

  window.gitGazeReply = ({ id, result, error, code }) => {
    const request = requests.get(id);
    if (!request) return;
    requests.delete(id);
    if (error) request.reject(Object.assign(new Error(error), { code:code || 'unknown' }));
    else request.resolve(result);
  };
  const request = (method, args) => new Promise((resolve, reject) => {
    const id = ++serial;
    requests.set(id, { resolve, reject });
    post('request', { version:1, id, method, args:args ?? null });
  });

  function change(next) { prefs = next; if (activity) void activity.setPreferences(next); else post('preferences', next); render(); }
  function flip(key, open) {
    peopleSearch = ''; settingsLimit = 20;
    configuring = open ? key : undefined;
    render();
    main.querySelector(`[data-widget="${key}"] ${open ? '.face :is(input, select, button)' : 'button[aria-label^="Configure"]'}`)?.focus();
  }
  function refresh() { if (activity) void activity.refresh({ force:true }); else post('refresh'); }
  function navigate(next) { page = next; configuring = undefined; peopleLimit = 12; expandedPeople.clear(); render(); main.scrollTop = 0; main.focus(); }

  function todayCard() {
    const chart = svg('svg', { viewBox:'0 0 112 112', 'aria-hidden':'true' });
    const lit = stats.todayCount > 0 ? Math.max(1, Math.ceil(stats.progress * 40)) : 0;
    for (let i = 0; i < 40; i++) {
      chart.append(svg('rect', { x:54.5, y:1, width:3, height:8, rx:1.5, transform:`rotate(${i * 9} 56 56)`,
        fill:i < lit ? (stats.isRecord ? 'var(--gold)' : 'var(--accent)') : 'currentColor', opacity:i < lit ? 1 : .16 }));
    }
    const count = group('center', text(num(stats.todayCount), stats.todayCount > 99 ? 'number compact' : 'number'), text('today', 'secondary'));
    count.setAttribute('aria-hidden', 'true');
    const dial = group('dial', chart, count);
    dial.setAttribute('role', 'img');
    dial.setAttribute('aria-label', `${num(stats.todayCount)} contributions today. ${Math.trunc(stats.progress * 100)} percent of your next daily record.`);
    const progress = stats.isRecord ? `↗ +${stats.todayCount - stats.previousBest} above previous` : `${stats.target - stats.todayCount} to beat it`;
    return group('hero', dial, group('daily-best', text(stats.isRecord ? 'NEW DAILY BEST' : 'DAILY BEST', 'daily-best-label'),
      ...(data.historyComplete ? [] : [text('Past year only', 'secondary')]),
      group('split', text(num(stats.bestDay), 'large'), text('contributions', 'secondary')),
      text(progress, stats.isRecord ? 'metric record' : 'metric')));
  }

  function streakCard() {
    const marks = group('marks');
    for (let i = -6; i <= 0; i++) {
      const date = core.offset(today, i), count = stats.count(date);
      const mark = el('span', count > 0 ? 'mark active' : 'mark');
      mark.title = `${date}: ${count > 0 ? 'Active' : 'No contributions'}`;
      marks.append(mark);
    }
    return group('streak', group('streak-current', text(num(stats.streak), 'streak-number'), text('days')), marks,
      group('streak-best', text(num(stats.longestStreak), 'streak-number'), text('best')));
  }

  function calendar(profile, weeks, dates = true) {
    const start = core.offset(today, -(weeks - 1) * 7 - core.weekday(today));
    const graph = el('div', 'heat');
    graph.dataset.weeks = weeks;
    graph.setAttribute('role', 'img');
    graph.setAttribute('aria-label', `${weeks}-week contribution graph`);
    const firstMonth = core.offset(today, -(weeks - 1) * 7).slice(0, 7);
    const label = text(firstMonth), end = text('Today');
    const days = new Map(profile.days.map(d => [d.date, d]));
    const colours = ['#9be9a8 #0e4429', '#40c463 #006d32', '#30a14e #26a641', '#216e39 #39d353'];
    for (let i = 0; i < weeks * 7; i++) {
      const date = core.offset(start, i);
      if (date > today) break;
      const day = days.get(date), count = day?.contributionCount ?? 0;
      const level = count ? (colours.findIndex(pair => pair.split(' ').includes(day.color?.toLowerCase())) + 1 || Math.min(4, Math.floor(count / 5) + 1)) : 0;
      const cell = el('span');
      cell.dataset.level = level;
      cell.addEventListener('pointerenter', () => { label.textContent = `${count} contributions · ${date}`; end.hidden = true; });
      graph.append(cell);
    }
    graph.addEventListener('pointerleave', () => { label.textContent = firstMonth; end.hidden = false; });
    return group('heat-calendar', graph, ...(dates ? [group('split heat-dates', label, end)] : []));
  }

  function heatmap() {
    return group('', group('heat-total', text(num(data.profile.totalContributions), 'large'), text('past year')),
      calendar(data.profile, prefs.historyWeeks));
  }

  function orderedPeople() {
    return core.orderPeople(data.following, prefs);
  }

  function peopleCard(favouritesOnly) {
    const people = orderedPeople().filter(p => !favouritesOnly || prefs.favourites.includes(p.login));
    if (!people.length) return text('Choose people in this widget’s settings.', 'secondary yearly-empty');
    const rows = people.slice(0, peopleLimit).map(person => {
      const { login } = person, profile = data.people?.[login];
      const key = `${favouritesOnly}|${login}`, expanded = expandedPeople.has(key);
      const toggle = () => { if (expanded) expandedPeople.delete(key); else expandedPeople.add(key); render(); };
      const name = group('person-name', text(login[0].toUpperCase(), 'avatar'), text(person.name || login, 'person-title'));
      const row = group('person-row', name);
      if (!profile) { row.append(text('History not loaded')); return row; }
      const totals = core.statistics(profile.days, today);
      name.append(group('person-metrics', ...[['Today', totals.todayCount], ['Week', totals.weekTotal], ['Month', totals.monthTotal], ['Year', totals.yearTotal]]
        .map(([label, count]) => group('', text(num(count), 'person-title'), text(label)))));
      const control = (weeks, dates) => button(calendar(profile, weeks, dates), `${expanded ? 'Collapse' : 'Expand'} ${login}’s ${dates ? 'full-year ' : ''}contribution graph`, toggle);
      const mini = control(26, false); mini.className = 'person-mini'; mini.setAttribute('aria-expanded', String(expanded)); row.append(mini);
      if (expanded) { const full = control(53, true); full.className = 'person-full'; row.append(full); }
      return row;
    });
    if (people.length > peopleLimit) rows.push(button('Show more', `Show more ${favouritesOnly ? 'favourites' : 'people'}`, () => {
      peopleLimit += 12; render(); void activity?.loadPeople(peopleLimit);
    }));
    return group('people-list', ...rows);
  }

  function peopleSettings() {
    const search = el('input'); search.type = 'search'; search.placeholder = 'Find someone you follow';
    search.setAttribute('aria-label', search.placeholder); search.value = peopleSearch;
    const rows = group('people-list');
    const populate = () => {
      const people = orderedPeople(), favourites = people.filter(p => prefs.favourites.includes(p.login)).map(p => p.login);
      const term = peopleSearch.trim().toLocaleLowerCase();
      const matching = people.filter(p => [p.login, p.name].some(value => value?.toLocaleLowerCase().includes(term)));
      rows.replaceChildren(...matching.slice(0, settingsLimit).map(p => {
        const at = favourites.indexOf(p.login), selected = at >= 0, controls = group('people-controls');
        if (selected) for (const [delta, label, glyph] of [[-1, 'up', '↑'], [1, 'down', '↓']]) {
          controls.append(button(glyph, `Move ${p.login} ${label}`, () => {
            const order = [...favourites]; [order[at], order[at + delta]] = [order[at + delta], order[at]];
            change({ ...prefs, favouriteOrder:order });
          }, !favourites[at + delta]));
        }
        controls.append(button(selected ? '⊖' : '⊕', `${selected ? 'Unfavourite' : 'Favourite'} ${p.login}`, () => {
          const order = selected ? favourites.filter(login => login !== p.login) : [...favourites, p.login];
          change({ ...prefs, favourites:selected ? prefs.favourites.filter(login => login !== p.login) : [...prefs.favourites, p.login], favouriteOrder:order });
          if (!selected) void activity?.loadPeople(peopleLimit);
        }));
        return group('person-option', text(p.login[0].toUpperCase(), 'avatar'), text(p.name || p.login, 'person-title'), controls);
      }));
      if (!matching.length) rows.append(text('No matching people', 'secondary yearly-empty'));
      if (matching.length > settingsLimit) rows.append(button('Show more', 'Show more matches', () => { settingsLimit += 20; populate(); }));
    };
    search.addEventListener('input', () => { peopleSearch = search.value; settingsLimit = 20; populate(); });
    populate();
    return group('people-settings', search, rows);
  }

  function select(label, values, current, onChange, closeOnChange = true) {
    const input = el('select');
    for (const [value, name] of values) { const choice = el('option', '', name); choice.value = value; input.append(choice); }
    input.value = current;
    input.setAttribute('aria-label', label);
    input.addEventListener('change', () => {
      const key = configuring;
      onChange(input.value);
      if (key && closeOnChange) flip(key, false);
    });
    const field = el('label', 'option', label); field.append(input); return field;
  }

  const comparisonYears = () => data.profile.years.filter(y => y < Number(today.slice(0, 4))).sort((a, b) => b - a);
  function yearCard() {
    if (!data.historyComplete) return text('Yearly history unavailable. Refresh to try again.', 'secondary yearly-empty');
    const year = Number(today.slice(0, 4)), older = comparisonYears().includes(prefs.comparisonYear) ? prefs.comparisonYear : year - 1;
    const full = prefs.comparisonMode === 'full', cutoff = full ? '12-31' : today.slice(5);
    const current = stats.yearTotal, previous = stats.totalInYear(older, cutoff), max = Math.max(1, current, previous);
    const position = md => (Date.parse(`2000-${md}T00:00:00Z`) - Date.UTC(2000, 0, 1)) / 86400000 + 1;
    const graph = svg('svg', { class:'year-chart', viewBox:'0 0 340 100', preserveAspectRatio:'none', role:'img',
      'aria-label':`${year} and ${older} cumulative contributions, ${full ? 'full years' : 'same point in each year'}` });
    for (const y of [1, 50, 99]) graph.append(svg('path', { d:`M0 ${y}H340`, stroke:'currentColor', opacity:.08 }));
    for (const value of [older, year]) {
      let sum = 0, path = 'M0 99', x = 0;
      for (const day of stats.days) {
        if (day.date < `${value}-01-01` || day.date > `${value}-${cutoff}`) continue;
        x = 340 * position(day.date.slice(5)) / position(cutoff);
        path += `L${x} ${99 - 98 * (sum += day.contributionCount) / max}`;
      }
      if (value === year) graph.append(svg('path', { d:`${path}L${x} 99Z`, fill:'var(--accent)', opacity:.12 }));
      graph.append(svg('path', { d:path, fill:'none', stroke:value === year ? 'var(--accent)' : 'var(--muted)',
        'stroke-width':value === year ? 2 : 1.2, 'stroke-dasharray':value === year ? 'none' : '3 3' }));
    }
    const date = new Intl.DateTimeFormat(undefined, { month:'short', day:'numeric' }).format(new Date(`${today}T12:00:00`));
    return group('year-card', group('week-summary', text(num(current), 'streak-number'), text(String(year)),
      text(`${current >= previous ? '+' : '−'}${num(Math.abs(current - previous))}`, 'year-delta')), graph,
      group('split', text(`● ${year} · ${num(current)}`, 'year-key'), text(`${older} · ${num(previous)}`)),
      text(full ? 'Current year to date · previous full year' : `Both years through ${date}`));
  }

  function appearanceSettings() {
    const section = el('section');
    section.append(el('h2', '', 'Appearance'), select('Theme', [['system','Auto'],['light','Light'],['dark','Dark']], prefs.appearance,
      appearance => change({ ...prefs, appearance })));
    section.append(group('palette-options', ...[...Object.keys(palettes), 'custom'].map(value => {
      const title = value === 'custom' ? 'Custom theme' : `${value[0].toUpperCase()}${value.slice(1)}`;
      const control = button(title, `${title}${value === 'custom' ? '' : ' theme'}`, () => change({ ...prefs, palette:value }));
      control.setAttribute('aria-pressed', String((prefs.palette ?? 'violet') === value));
      control.style.setProperty('--swatch', `#${palettes[value]?.[0] ?? prefs.customLight ?? '6E4AC9'}`);
      return control;
    })));
    if (prefs.palette === 'custom') for (const [key, label, fallback] of [['customLight','Light accent','6E4AC9'], ['customDark','Dark accent','B09CFF']]) {
      const input = el('input'); input.type = 'color'; input.value = `#${prefs[key] ?? fallback}`; input.setAttribute('aria-label', label);
      input.addEventListener('change', () => change({ ...prefs, [key]:input.value.slice(1).toUpperCase() }));
      const row = el('label', 'option', label); row.append(input); section.append(row);
    }
    return section;
  }

  function momentumCard() {
    const monday = core.monday(today);
    const values = Array.from({ length:7 }, (_, i) => stats.count(core.offset(monday, i)));
    const peak = Math.max(1, ...values);
    const chart = group('week-chart', ...values.map((value, index) => {
      const bar = svg('svg', { width:28, height:Math.max(3, 42 * value / peak), 'aria-hidden':'true' });
      bar.append(svg('rect', { width:'100%', height:'100%', rx:3, fill:'var(--accent)', opacity:value ? .9 : .15 }));
      return group('week-day', text(num(value)), bar, text('MTWTFSS'[index]));
    }));
    chart.title = 'Monday–Sunday · this week so far versus all of last week';
    return group('', group('week-summary', text(num(stats.weekTotal), 'streak-number'), text('contributions'),
      text(`${num(stats.lastWeekTotal)} last week`, 'secondary previous-week')), chart);
  }

  const widgets = {
    today: { title:'Today', face:todayCard },
    streak: { title:'Streak', face:streakCard, settings:() => select('Reminder hour', Array.from({ length:24 }, (_, i) => [i, `${String(i).padStart(2, '0')}:00`]), prefs.reminderHour, h => change({ ...prefs, reminderHour:Number(h) })) },
    heatmap: { title:'Contribution history', heading:'Contributions', face:heatmap, settings:() => select('Visible history', [[26,'6 months'],[53,'Year']], prefs.historyWeeks, weeks => change({ ...prefs, historyWeeks:Number(weeks) })) },
    favourites: { title:'Favourite people', heading:'Favourites', face:() => peopleCard(true), settings:peopleSettings },
    momentum: { title:'Weekly momentum', heading:'This week', face:momentumCard },
    records: { title:'Personal bests', face:() => group('split records', ...[
      ['Day', stats.bestDay, 'contributions'], ['Week', stats.bestWeek, 'contributions'], ['Streak', stats.longestStreak, 'days']
    ].map(([title, value, unit]) => group('personal-best', text(title), text(num(value), 'best-number'), text(unit, 'best-unit')))) },
    people: { title:'People you follow', heading:'Following', face:() => peopleCard(false), settings:peopleSettings },
    years: { title:'Year in perspective', face:yearCard, settings:() => group('',
      select('Compare with', [[0, 'Previous year'], ...comparisonYears().map(y => [y, String(y)])],
        comparisonYears().includes(prefs.comparisonYear) ? prefs.comparisonYear : 0,
        year => change({ ...prefs, comparisonYear:Number(year) }), false),
      select('Period', [['ytd', 'Same point in year'], ['full', 'Full years']], prefs.comparisonMode ?? 'ytd',
        mode => change({ ...prefs, comparisonMode:mode }), false)) }
  };
  const registry = Object.entries(widgets).map(([id, widget], index) => ({ id, hiddenByDefault: widget.hiddenByDefault ?? index >= 4 }));

  function widget(key, visible, gallery) {
    const { title, heading = title, face, settings } = widgets[key];
    const template = $('widget').content.cloneNode(true);
    const section = template.querySelector('section'), tools = section.querySelector('.tools');
    section.querySelector('h2').textContent = heading;
    section.dataset.widget = key;
    if (key === 'today' && !gallery) {
      const date = new Date(`${today}T12:00:00`);
      const label = el('time', 'secondary', new Intl.DateTimeFormat(undefined, { month:'short', day:'numeric' }).format(date));
      label.dateTime = today;
      section.querySelector('.card-heading').append(label);
    }
    const openSettings = configuring === key;
    if (gallery) tools.append(button('+', `Add ${title}`, () => change({ ...prefs, hidden:prefs.hidden.filter(id => id !== key) })));
    else if (openSettings) tools.append(button('↶ Back', `Back from ${title}`, () => flip(key, false)));
    else {
      for (const [delta, glyph, word] of [[-1, '↑', 'up'], [1, '↓', 'down']]) {
        tools.append(button(glyph, `Move ${title} ${word}`, () => change(core.moveWidget(prefs, key, delta)), !visible[visible.indexOf(key) + delta]));
      }
      if (settings) tools.append(button('☷', `Configure ${title}`, () => flip(key, true)));
      tools.append(button('−', `Remove ${title}`, () => change({ ...prefs, hidden:[...prefs.hidden, key] })));
    }
    if (gallery || openSettings) tools.classList.add('active');
    const panel = section.querySelector('.face');
    if (openSettings) panel.classList.add('flipping');
    panel.append(openSettings ? settings() : face());
    return section;
  }

  function render() {
    const oldOffset = main.scrollTop;
    const oldControl = document.activeElement?.getAttribute('aria-label');
    const actions = $('actions');
    $('title').textContent = page;
    document.documentElement.dataset.mode = prefs.appearance;
    const dark = prefs.appearance === 'dark' || (prefs.appearance === 'system' && systemDark.matches);
    const accent = prefs.palette === 'custom' ? prefs[dark ? 'customDark' : 'customLight'] : palettes[prefs.palette]?.[Number(dark)];
    document.documentElement.style.setProperty('--accent', /^[0-9a-f]{6}$/i.test(accent ?? '') ? `#${accent}` : '');
    actions.replaceChildren(...(page === 'GitGaze' ? [button(icon('M8 3v10M3 8h10'), 'Add widgets', () => navigate('Add widgets')),
      button(icon('M12.5 6a5 5 0 1 0 .2 4M12.5 2.8V6H9.3'), 'Refresh', refresh, !live),
      button(icon('M2.5 4h3m3 0h5m-8-1.4v2.8M2.5 8h6m3 0h2m-5-1.4v2.8M2.5 12h2m3 0h6m-9-1.4v2.8'), 'Settings', () => navigate('Settings'))] :
      [button('↶ Back', 'Back to dashboard', () => navigate('GitGaze'))]));
    main.classList.toggle('gallery', page === 'Add widgets');
    main.replaceChildren();
    if (error) main.append(text(error, 'metric record'));
    if (page === 'Settings') {
      main.append(appearanceSettings());
    } else if (!data) {
      main.append(el('h2', '', 'Your work, in view.'), el('p', '', 'Connect with your GitHub CLI session.'), button('Connect GitHub CLI', 'Connect GitHub CLI', refresh));
    } else {
      const gallery = page === 'Add widgets';
      const visible = prefs.modules.filter(id => prefs.hidden.includes(id) === gallery);
      if (!visible.length) main.append(gallery ? text('All widgets added') : button('Add a widget', 'Add a widget', () => navigate('Add widgets')));
      for (const id of visible) main.append(widget(id, visible, gallery));
    }
    $('account').textContent = data ? '@' + data.profile.person.login : '';
    $('status').textContent = status;
    if (oldControl) [...document.querySelectorAll('button, select, input')].find(b => !b.disabled && b.getAttribute('aria-label') === oldControl)?.focus({ preventScroll:true });
    main.scrollTop = oldOffset;
  }

  window.gitGazeReceive = snapshot => {
    if (data?.profile.person.login !== snapshot.dashboard?.profile.person.login) {
      expandedPeople.clear(); peopleLimit = 12; peopleSearch = ''; settingsLimit = 20; configuring = undefined;
    }
    data = snapshot.dashboard;
    prefs = core.preferences(snapshot.preferences, registry);
    today = snapshot.today || core.localDay(new Date());
    stats = data ? core.statistics([...data.history, ...data.profile.days], today) : null;
    status = snapshot.status || (data ? 'Cached activity' : 'Not connected');
    error = snapshot.error;
    live = snapshot.live === true;
    render();
  };
  window.gitGazeOpen = () => navigate('GitGaze');
  window.gitGazeStart = () => {
    if (window !== window.top || activity) return;
    activity = globalThis.gitGazeActivity({ request, core, registry, onChange:window.gitGazeReceive });
    void activity.start();
    setInterval(() => void activity.refresh({ background:true }), 30000);
  };
  if (window === window.top && window.chrome?.webview) window.chrome.webview.addEventListener('message', ({ data }) => {
    if (data.kind === 'start') window.gitGazeStart();
    else if ('id' in data) window.gitGazeReply(data);
    else window.gitGazeReceive(data);
  });
  document.addEventListener('keydown', event => {
    if (event.key !== 'Escape' || event.defaultPrevented) return;
    if (configuring) flip(configuring, false);
    else if (page !== 'GitGaze') navigate('GitGaze');
    else post('dismiss');
  });
  post('ready');
  systemDark.addEventListener('change', () => { if (prefs?.appearance === 'system') render(); });
})();
