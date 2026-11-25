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
  let data, prefs, today, stats, page = 'GitGaze', configuring, status = '', error, live;
  const requests = new Map();
  let serial = 0, activity;
  let leaderboardContext, leaderboardLimit = 5, leaderboardRequested = false;
  const leaderboard = globalThis.gitGazeLeaderboard.leaderboard({ publish:() => { if (prefs) render(); } });
  const leaderboardEnabled = () => prefs && !prefs.hidden.includes('leaderboard');
  function updateLeaderboard(context, force = false) {
    if (!leaderboardEnabled() || !context || context.signal.aborted) return;
    const account = context.login.toLowerCase();
    if (leaderboard.snapshot().account !== account) {
      leaderboardLimit = 5;
      const selection = prefs.leaderboardOrganization;
      leaderboard.scope(account, selection?.account === account ? selection.id : null);
    }
    void leaderboard.refresh(context, { force });
  }

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

  function change(next) {
    const wasEnabled = leaderboardEnabled();
    prefs = next;
    if (activity) void activity.setPreferences(next); else post('preferences', next);
    if (wasEnabled && !leaderboardEnabled()) { leaderboardRequested = false; leaderboard.cancel(); }
    if (!wasEnabled && leaderboardEnabled()) updateLeaderboard(leaderboardContext);
    render();
  }
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

  function heatmap() {
    const weeks = prefs.historyWeeks, start = core.offset(today, -(weeks - 1) * 7 - core.weekday(today));
    const graph = el('div', 'heat');
    graph.dataset.weeks = weeks;
    graph.setAttribute('role', 'img');
    graph.setAttribute('aria-label', `${weeks}-week contribution graph`);
    const firstMonth = core.offset(today, -(weeks - 1) * 7).slice(0, 7);
    const label = text(firstMonth), end = text('Today');
    const days = new Map(data.profile.days.map(d => [d.date, d]));
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
    return group('', group('heat-total', text(num(data.profile.totalContributions), 'large'), text('past year')),
      group('heat-calendar', graph, group('split heat-dates', label, end)));
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

  function leaderboardStatus(state) {
    const { snapshot, loading, error, organizations } = state;
    const panel = group('leaderboard-status');
    panel.tabIndex = -1;
    const refreshRank = () => {
      leaderboardRequested = true;
      render();
      void activity.refresh({ force:true, extensionForce:true });
    };
    const busy = loading || leaderboardRequested;
    const accessHelp = 'Check gh auth status, confirm organization access (read:org for classic tokens), and authorize GitHub CLI for your organization’s SSO if required. Then refresh.';
    if (snapshot) {
      const time = el('time', 'secondary', `Leaderboard updated ${new Date(snapshot.updatedAt).toLocaleString(undefined, { month:'short', day:'numeric', hour:'numeric', minute:'2-digit' })}`);
      time.dateTime = new Date(snapshot.updatedAt).toISOString();
      panel.append(group('split', time, ...(!busy && !error && activity ? [button('Refresh', 'Refresh leaderboard', refreshRank)] : [])));
    }
    if (busy) panel.append(text(loading ? snapshot ? 'Refreshing leaderboard…' : organizations ? 'Ranking visible members…' : 'Finding organizations…' : 'Waiting to refresh leaderboard…'));
    else if (error) {
      const messages = { access:'Your GitHub CLI session can’t access this organization or roster.',
        roster_limit:`This organization exceeds the limit of ${globalThis.gitGazeLeaderboard.memberLimit} visible members. Choose a smaller organization in widget settings.`,
        rate_limit:'GitHub is limiting requests. Try again later.', network:'GitHub couldn’t be reached.', server:'GitHub is temporarily unavailable.',
        incomplete:'GitHub didn’t return a complete visible roster. No ranking is shown.', unknown:'GitGaze couldn’t verify the leaderboard response. No ranking is shown.' };
      panel.append(text(messages[error], 'secondary record'));
      if (error === 'access') {
        panel.append(text(accessHelp));
        if (activity) panel.append(button('Recheck access', 'Recheck leaderboard access', refreshRank));
      }
      if (['network', 'server', 'rate_limit'].includes(error)) {
        if (snapshot) panel.append(text('Showing the last complete ranking.'));
        if (activity) panel.append(button('Try again', 'Retry leaderboard', refreshRank));
      }
    } else if (organizations?.length === 0) panel.append(text('No organizations are visible to this GitHub CLI session.'), text(accessHelp));
    else if (!snapshot) panel.append(text('Connect an eligible GitHub CLI session to rank organization members.'));
    return panel;
  }

  function leaderboardCard(gallery) {
    if (gallery) return text('Compare visible contribution activity within an organization.');
    const state = leaderboard.snapshot();
    const organization = state.organizations?.find(org => org.id === state.selected);
    const body = group('leaderboard', ...(organization ? [text(organization.login, 'leaderboard-org')] : []), leaderboardStatus(state));
    const rows = state.snapshot?.rows;
    if (!rows) return body;
    if (!rows.length) { body.append(text('GitHub returned no visible members to rank.')); return body; }
    const viewer = rows.find(row => row.login.toLowerCase() === state.account);
    body.append(viewer ? group('leaderboard-place split', group('', text('YOUR PLACE'),
      text(`#${num(viewer.rank)} of ${num(rows.length)} visible members`, 'leaderboard-rank')), text(`${num(viewer.count)} contributions`)) :
      text('Your account isn’t in the visible roster, so no personal rank is available.'));
    body.append(text('Last 30 days · commits, issues, PRs and reviews. Only members and activity visible to your GitHub CLI session count.'));
    if (rows[0].count === 0) body.append(text('No visible activity in this period. All ranked members are tied.'));
    const list = el('ol', 'leaderboard-rows'); list.setAttribute('aria-label', 'Visible member rankings');
    for (const row of rows.slice(0, leaderboardLimit)) {
      const item = el('li');
      const initial = el('span', 'leaderboard-avatar', (row.name || row.login).slice(0, 1).toUpperCase());
      initial.setAttribute('aria-hidden', 'true');
      const name = text(row.name || row.login, 'leaderboard-name'); name.title = `@${row.login}`;
      item.append(text(`#${num(row.rank)}`), initial, name);
      if (row === viewer) item.append(text('You', 'leaderboard-you'));
      item.append(text(num(row.count), 'leaderboard-count')); list.append(item);
    }
    body.append(list);
    if (rows.length > leaderboardLimit) body.append(button(`Show more (${num(rows.length - leaderboardLimit)} remaining)`, 'Show more ranked members', () => {
      leaderboardLimit += 10; render();
    }));
    return body;
  }

  function leaderboardSettings() {
    const state = leaderboard.snapshot();
    const body = group('leaderboard', leaderboardStatus(state));
    if (state.organizations?.length) {
      const options = state.organizations.map(org => [org.id, org.login]);
      if (!options.some(([id]) => id === state.selected)) options.unshift(['', 'Choose an organization']);
      body.prepend(select('Organization', options, options.some(([id]) => id === state.selected) ? state.selected : '', id => {
        if (!id || !leaderboardContext || leaderboardContext.signal.aborted) return;
        leaderboardLimit = 5;
        change({ ...prefs, leaderboardOrganization:{ account:state.account, id } });
        leaderboard.scope(state.account, id);
        updateLeaderboard({ ...leaderboardContext, at:Date.now() }, true);
      }));
    }
    return body;
  }

  const widgets = {
    today: { title:'Today', face:todayCard },
    streak: { title:'Streak', face:streakCard, settings:() => select('Reminder hour', Array.from({ length:24 }, (_, i) => [i, `${String(i).padStart(2, '0')}:00`]), prefs.reminderHour, h => change({ ...prefs, reminderHour:Number(h) })) },
    heatmap: { title:'Contribution history', heading:'Contributions', face:heatmap, settings:() => select('Visible history', [[26,'6 months'],[53,'Year']], prefs.historyWeeks, weeks => change({ ...prefs, historyWeeks:Number(weeks) })) },
    favourites: { title:'Favourite people', face:() => {
      const rows = data.following.filter(p => prefs.favourites.includes(p.login)).sort((a, b) => {
        const rank = p => { const i = prefs.favouriteOrder.indexOf(p.login); return i < 0 ? Infinity : i; };
        return rank(a) - rank(b) || a.login.localeCompare(b.login);
      }).map(p => el('p', '', p.name || p.login));
      return group('', ...(rows.length ? rows : [text('Choose people in this widget’s settings.', 'secondary')]));
    } },
    momentum: { title:'Weekly momentum', heading:'This week', face:momentumCard },
    records: { title:'Personal bests', face:() => group('split records', ...[
      ['Day', stats.bestDay, 'contributions'], ['Week', stats.bestWeek, 'contributions'], ['Streak', stats.longestStreak, 'days']
    ].map(([title, value, unit]) => group('personal-best', text(title), text(num(value), 'best-number'), text(unit, 'best-unit')))) },
    people: { title:'People you follow', face:() => group('', ...data.following.map(p => el('p', '', p.name || p.login))) },
    years: { title:'Year in perspective', face:() => {
      const year = Number(today.slice(0, 4)), older = prefs.comparisonYear || year - 1;
      return group('split', text(`${num(stats.yearTotal)} in ${year}`, 'large'), text(`${num(stats.totalInYear(older, prefs.comparisonMode === 'full' ? undefined : today.slice(5)))} in ${older}`));
    } },
    leaderboard: { title:'Organization leaderboard', hiddenByDefault:true, face:leaderboardCard, settings:leaderboardSettings }
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
    if (openSettings && key !== 'leaderboard') panel.classList.add('flipping');
    panel.append(openSettings ? settings() : face(gallery));
    return section;
  }

  function render() {
    const oldOffset = main.scrollTop;
    const oldFocus = document.activeElement;
    const oldControl = oldFocus?.getAttribute('aria-label');
    const rankFocus = oldFocus?.closest('.leaderboard-status');
    const actions = $('actions');
    $('title').textContent = page;
    document.documentElement.dataset.mode = prefs.appearance;
    actions.replaceChildren(...(page === 'GitGaze' ? [button(icon('M8 3v10M3 8h10'), 'Add widgets', () => navigate('Add widgets')),
      button(icon('M12.5 6a5 5 0 1 0 .2 4M12.5 2.8V6H9.3'), 'Refresh', refresh, !live),
      button(icon('M2.5 4h3m3 0h5m-8-1.4v2.8M2.5 8h6m3 0h2m-5-1.4v2.8M2.5 12h2m3 0h6m-9-1.4v2.8'), 'Settings', () => navigate('Settings'))] :
      [button('↶ Back', 'Back to dashboard', () => navigate('GitGaze'))]));
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
    const statusPanel = main.querySelector('.leaderboard-status');
    const matchingControl = oldControl && [...document.querySelectorAll('button')].find(b => !b.disabled && b.getAttribute('aria-label') === oldControl);
    const nextFocus = matchingControl || (rankFocus && (statusPanel?.querySelector('button') || statusPanel)) ||
      (oldControl === 'Add Organization leaderboard' && $('actions').querySelector('button'));
    if (nextFocus) nextFocus.focus({ preventScroll:true });
    const announcement = $('leaderboard-announcement');
    const state = leaderboard.snapshot();
    const message = !leaderboardEnabled() ? '' : leaderboardRequested ? 'Waiting to refresh leaderboard.' :
      state.loading ? 'Refreshing organization leaderboard.' : state.error ? `Leaderboard: ${statusPanel?.textContent || 'refresh failed.'}` :
      state.snapshot ? 'Organization leaderboard updated.' : state.organizations?.length === 0 ? 'No visible organizations.' : '';
    if (announcement.textContent !== message) announcement.textContent = message;
    main.scrollTop = oldOffset;
  }

  window.gitGazeReceive = snapshot => {
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
    activity = globalThis.gitGazeActivity({ request, core, registry, onChange:window.gitGazeReceive,
      onVerifiedRefresh: context => {
        leaderboardContext = context;
        if (leaderboard.snapshot().account && leaderboard.snapshot().account !== context.login.toLowerCase()) leaderboard.scope(context.login,
          prefs.leaderboardOrganization?.account === context.login.toLowerCase() ? prefs.leaderboardOrganization.id : null);
        if (context.extensionForce) leaderboardRequested = false;
        updateLeaderboard(context, context.extensionForce);
      }, onViewerFailure: failure => {
        leaderboardContext = undefined;
        leaderboardRequested = false;
        leaderboard.fail(failure);
      } });
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
