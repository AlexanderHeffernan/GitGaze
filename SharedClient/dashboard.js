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
    const node = el('button', '', text);
    node.setAttribute('aria-label', label);
    node.title = label;
    node.disabled = disabled;
    node.addEventListener('click', fn);
    return node;
  };
  const group = (css, ...children) => { const node = el('div', css); node.append(...children); return node; };
  const text = (s, css = 'secondary') => el('div', css, s);
  const num = n => n.toLocaleString();
  let data, prefs, today, stats, page = 'GitGaze', configuring, status = '', error, live;
  const requests = new Map();
  let serial = 0, activity;

  window.gitGazeReply = ({ id, result, error }) => {
    const request = requests.get(id);
    if (!request) return;
    requests.delete(id);
    if (error) request.reject(new Error(error));
    else request.resolve(result);
  };
  const request = (method, args) => new Promise((resolve, reject) => {
    const id = ++serial;
    requests.set(id, { resolve, reject });
    post('request', { version:1, id, method, args:args ?? null });
  });

  function change(next) { prefs = next; if (activity) void activity.setPreferences(next); else post('preferences', next); render(); }
  function flip(key, open) {
    configuring = open ? key : undefined;
    render();
    main.querySelector(`[data-widget="${key}"] ${open ? 'select' : 'button[aria-label^="Configure"]'}`)?.focus();
  }
  function refresh() { if (activity) void activity.refresh({ force:true }); else post('refresh'); }
  function navigate(next) { page = next; configuring = undefined; render(); main.scrollTop = 0; main.focus(); }

  function todayCard() {
    const chart = svg('svg', { viewBox:'0 0 112 112', 'aria-hidden':'true' });
    const lit = stats.todayCount > 0 ? Math.max(1, Math.ceil(stats.progress * 40)) : 0;
    for (let i = 0; i < 40; i++) {
      chart.append(svg('rect', { x:54.5, y:1, width:3, height:8, rx:1.5, transform:`rotate(${i * 9} 56 56)`,
        fill:i < lit ? (stats.isRecord ? 'var(--gold)' : 'var(--accent)') : 'currentColor', opacity:i < lit ? 1 : .16 }));
    }
    const count = group('center', text(num(stats.todayCount), stats.todayCount > 99 ? 'number compact' : 'number'), text('today'));
    count.setAttribute('aria-hidden', 'true');
    const dial = group('dial', chart, count);
    dial.setAttribute('role', 'img');
    dial.setAttribute('aria-label', `${num(stats.todayCount)} contributions today. ${Math.trunc(stats.progress * 100)} percent of your next daily record.`);
    const progress = stats.isRecord ? `↗ +${stats.todayCount - stats.previousBest} above previous` : `${stats.target - stats.todayCount} to beat it`;
    return group('hero', dial, group('', text(stats.isRecord ? 'NEW DAILY BEST' : 'DAILY BEST'), group('split', text(num(stats.bestDay), 'large'), text('contributions')),
      text(progress, stats.isRecord ? 'metric record' : 'metric'), ...(data.historyComplete ? [] : [text('Past year only')])));
  }

  function streakCard() {
    const marks = group('marks');
    for (let i = -6; i <= 0; i++) {
      const date = core.offset(today, i), count = stats.count(date);
      const mark = el('span', count > 0 ? 'mark active' : 'mark');
      mark.title = `${date} · ${count} contributions`;
      marks.append(mark);
    }
    return group('split', group('split', text(num(stats.streak), 'large'), text('days')), marks, group('', text(num(stats.longestStreak), 'large'), text('best')));
  }

  function heatmap() {
    const weeks = prefs.historyWeeks, start = core.offset(today, -(weeks - 1) * 7 - core.weekday(today));
    const graph = svg('svg', { class:'heat', viewBox:`0 0 ${weeks * 6} 42`, role:'img', 'aria-label':`${weeks}-week contribution graph` });
    const label = text(start.slice(0, 7));
    const days = new Map(data.profile.days.map(d => [d.date, d]));
    const colours = ['#9be9a8 #0e4429', '#40c463 #006d32', '#30a14e #26a641', '#216e39 #39d353'];
    for (let i = 0; i < weeks * 7; i++) {
      const date = core.offset(start, i);
      if (date > today) break;
      const day = days.get(date), count = day?.contributionCount ?? 0;
      const level = count ? (colours.findIndex(pair => pair.split(' ').includes(day.color?.toLowerCase())) + 1 || Math.min(4, Math.floor(count / 5) + 1)) : 0;
      const cell = svg('rect', { x:Math.floor(i / 7) * 6, y:i % 7 * 6, width:4.5, height:4.5, rx:1, class:level ? 'cell' : 'empty', opacity:[1,.22,.42,.67,1][level] });
      cell.addEventListener('pointerenter', () => label.textContent = `${count} contributions · ${date}`);
      graph.append(cell);
    }
    graph.addEventListener('pointerleave', () => label.textContent = start.slice(0, 7));
    return group('', group('split', text(num(data.profile.totalContributions), 'large'), text('past year')), graph, group('split', label, text('Today')));
  }

  function select(label, values, current, onChange) {
    const input = el('select');
    for (const [value, name] of values) { const choice = el('option', '', name); choice.value = value; input.append(choice); }
    input.value = current;
    input.addEventListener('change', () => {
      const key = configuring;
      onChange(input.value);
      if (key) flip(key, false);
      else main.querySelector('select')?.focus();
    });
    const field = el('label', 'option', label); field.append(input); return field;
  }

  const widgets = {
    today: { title:'Today', face:todayCard },
    streak: { title:'Your streak', face:streakCard, settings:() => select('Reminder hour', Array.from({ length:24 }, (_, i) => [i, `${String(i).padStart(2, '0')}:00`]), prefs.reminderHour, h => change({ ...prefs, reminderHour:Number(h) })) },
    heatmap: { title:'Contribution history', face:heatmap, settings:() => select('Visible history', [[26,'6 months'],[53,'Year']], prefs.historyWeeks, weeks => change({ ...prefs, historyWeeks:Number(weeks) })) },
    favourites: { title:'Favourite people', face:() => {
      const rows = data.following.filter(p => prefs.favourites.includes(p.login)).sort((a, b) => {
        const rank = p => { const i = prefs.favouriteOrder.indexOf(p.login); return i < 0 ? Infinity : i; };
        return rank(a) - rank(b) || a.login.localeCompare(b.login);
      }).map(p => el('p', '', p.name || p.login));
      return group('', ...(rows.length ? rows : [text('No favourites in this fixture.') ]));
    } },
    momentum: { title:'Weekly momentum', face:() => group('split', text(`${stats.weekTotal} this week`, 'large'), text(`${stats.lastWeekTotal} last week`)) },
    records: { title:'Personal bests', face:() => group('split', text(`${stats.bestDay} day`), text(`${stats.bestWeek} week`), text(`${stats.longestStreak} streak`)) },
    people: { title:'People you follow', face:() => group('', ...data.following.map(p => el('p', '', p.name || p.login))) },
    years: { title:'Year in perspective', face:() => {
      const year = Number(today.slice(0, 4)), older = prefs.comparisonYear || year - 1;
      return group('split', text(`${num(stats.yearTotal)} in ${year}`, 'large'), text(`${num(stats.totalInYear(older, prefs.comparisonMode === 'full' ? undefined : today.slice(5)))} in ${older}`));
    } }
  };

  function widget(key, visible, gallery) {
    const { title, face, settings } = widgets[key];
    const template = $('widget').content.cloneNode(true);
    const section = template.querySelector('section'), tools = section.querySelector('.tools');
    section.querySelector('h2').textContent = title;
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
    actions.replaceChildren(...(page === 'GitGaze' ? [button('+', 'Add widgets', () => navigate('Add widgets')),
      button('↻', 'Refresh', refresh, !live), button('☷', 'Settings', () => navigate('Settings'))] : [button('↶ Back', 'Back to dashboard', () => navigate('GitGaze'))]));
    main.classList.toggle('gallery', page === 'Add widgets');
    main.replaceChildren();
    if (error) main.append(text(error, 'metric record'));
    if (page === 'Settings') {
      const section = el('section');
      section.append(el('h2', '', 'Appearance'), select('Theme', [['system','Auto'],['light','Light'],['dark','Dark']], prefs.appearance, appearance => change({ ...prefs, appearance })));
      main.append(section);
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
    if (oldControl) [...document.querySelectorAll('button')].find(b => !b.disabled && b.getAttribute('aria-label') === oldControl)?.focus({ preventScroll:true });
    main.scrollTop = oldOffset;
  }

  window.gitGazeReceive = snapshot => {
    data = snapshot.dashboard;
    prefs = core.preferences(snapshot.preferences);
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
    activity = globalThis.gitGazeActivity({ request, core, onChange:window.gitGazeReceive });
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
})();
