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
  let data, prefs, today, stats, page = 'GitGaze', configuring, status = '';

  function change(next) { prefs = next; post('preferences', next); render(); }
  function navigate(next) { page = next; configuring = undefined; render(); main.scrollTop = 0; main.focus(); }

  function todayCard() {
    const chart = svg('svg', { viewBox:'0 0 100 100', 'aria-hidden':'true' });
    for (let i = 0; i < 36; i++) {
      chart.append(svg('line', { x1:50, x2:50, y1:3, y2:i % 3 ? 5 : 7, transform:`rotate(${i * 10} 50 50)`, stroke:'var(--edge)' }));
    }
    for (const [r, stroke, width] of [[33, 'var(--edge)', 1], [40, 'var(--edge)', 3], [40, stats.isRecord ? 'var(--gold)' : 'var(--accent)', 3]]) {
      chart.append(svg('circle', { cx:50, cy:50, r, fill:'none', stroke, 'stroke-width':width }));
    }
    chart.lastChild.setAttribute('pathLength', 100);
    chart.lastChild.setAttribute('stroke-dasharray', `${stats.progress * 100} 100`);
    chart.lastChild.setAttribute('transform', 'rotate(-90 50 50)');
    const dial = group('dial', chart, group('center', text(num(stats.todayCount), 'number'), text('today')));
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
    input.addEventListener('change', () => onChange(input.value));
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
    const openSettings = configuring === key;
    const flip = (next, target) => { configuring = next; render(); main.querySelector(`[data-widget="${key}"] ${target}`)?.focus(); };
    if (gallery) tools.append(button('+', `Add ${title}`, () => change({ ...prefs, hidden:prefs.hidden.filter(id => id !== key) })));
    else if (openSettings) tools.append(button('↶ Back', `Back from ${title}`, () => flip(undefined, 'button[aria-label^="Configure"]')));
    else {
      for (const [delta, glyph, word] of [[-1, '↑', 'up'], [1, '↓', 'down']]) {
        tools.append(button(glyph, `Move ${title} ${word}`, () => change(core.moveWidget(prefs, key, delta)), !visible[visible.indexOf(key) + delta]));
      }
      if (settings) tools.append(button('☷', `Configure ${title}`, () => flip(key, 'select')));
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
      button('↻', 'Refresh', () => post('refresh')), button('☷', 'Settings', () => navigate('Settings'))] : [button('↶ Back', 'Back to dashboard', () => navigate('GitGaze'))]));
    main.classList.toggle('gallery', page === 'Add widgets');
    main.replaceChildren();
    if (page === 'Settings') {
      const section = el('section');
      section.append(el('h2', '', 'Appearance'), select('Theme', [['system','Auto'],['light','Light'],['dark','Dark']], prefs.appearance, appearance => change({ ...prefs, appearance })));
      main.append(section);
    } else if (!data) {
      main.append(el('h2', '', 'Your work, in view.'), el('p', '', 'Connect with your GitHub CLI session.'), button('Connect GitHub CLI', 'Connect GitHub CLI', () => post('refresh')));
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
    render();
  };
  window.gitGazeOpen = () => navigate('GitGaze');
  if (window === window.top && window.chrome?.webview) window.chrome.webview.addEventListener('message', event => window.gitGazeReceive(event.data));
  document.addEventListener('keydown', event => {
    if (event.key !== 'Escape' || event.defaultPrevented) return;
    if (configuring) { configuring = undefined; render(); }
    else if (page !== 'GitGaze') navigate('GitGaze');
    else post('dismiss');
  });
  post('ready');
})();
