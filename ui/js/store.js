// App state and behaviour: refresh schedule, offline cache, preferences, people, reminders,
// celebrations and push detection. Views read this; the native shell only supplies OS services.

import { invoke, listen, plugin, native } from './bridge.js';
import * as github from './github.js';
import * as leaderboard from './leaderboard.js';
import { Stats, IncreaseTracker, dayKey } from './stats.js';
import { reduceMotion, accent, gold, systemDark } from './theme.js';

/** Swift's Date reference (2001-01-01) in Unix seconds; the cache keeps the original format. */
const REFERENCE = 978307200;
const nowSeconds = () => Date.now() / 1000 - REFERENCE;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

export const modules = ['today', 'streak', 'heatmap', 'favourites', 'momentum', 'records', 'people', 'years', 'leaderboard'];
export const moduleTitles = {
  today: 'Today', streak: 'Your streak', heatmap: 'Contribution history', favourites: 'Favourite people',
  momentum: 'Weekly momentum', records: 'Personal bests', people: 'People you follow', years: 'Year in perspective',
  leaderboard: 'Organisation leaderboard',
};

const defaults = {
  modules, hidden: ['momentum', 'records', 'people', 'years', 'leaderboard'], favourites: [], favouriteOrder: [],
  palette: 'violet', customLight: '6E4AC9', customDark: 'B09CFF', menuStyle: 'charge', menuStreak: false,
  appearance: 'system', notifications: false, visualCelebrations: true, celebrationStyle: 'fireworks',
  streakReminder: false, reminderHour: 18, lastReminderDay: null, detectPushes: false,
  historyWeeks: 53, comparisonYear: 0, comparisonMode: 'ytd', leaderboardOrg: null, leaderboardPeriod: 'week', autoUpdate: true, lastUpdateCheck: 0,
};

/** Accepts saved preferences, including the previous macOS app's user defaults. */
function normalise(saved) {
  const prefs = { ...defaults };
  for (const key of Object.keys(defaults)) if (saved?.[key] !== undefined && saved[key] !== null) prefs[key] = saved[key];
  if (typeof saved?.SUEnableAutomaticChecks === 'boolean' && saved.autoUpdate === undefined) prefs.autoUpdate = saved.SUEnableAutomaticChecks;
  const savedModules = Array.isArray(saved?.modules) ? saved.modules.filter(m => modules.includes(m)) : [];
  prefs.modules = [...new Set([...savedModules, ...modules])];
  prefs.hidden = Array.isArray(prefs.hidden) ? prefs.hidden.filter(m => modules.includes(m)) : defaults.hidden;
  // Widgets added after someone arranged their dashboard start hidden; they're in the gallery.
  for (const added of ['years', 'leaderboard']) if (!savedModules.includes(added) && !prefs.hidden.includes(added)) prefs.hidden.push(added);
  return prefs;
}

export class Store {
  dashboard = null;
  loading = false;
  loadingHistory = false;
  loadingPeople = false;
  error = null;
  peopleError = null;
  page = 'dashboard';
  presentation = 0;
  peopleLimit = 12;
  launchAtLogin = false;
  ghInstalled = true;
  platform = 'macos';
  celebration = null;
  board = { organizations: null, result: null, loading: false, error: null, key: null, fetchedAt: 0 };
  flashing = false;
  stats = null;
  orderedPeople = [];
  prefs = normalise({});
  today = dayKey();

  #listeners = new Set();
  #scheduled = false;
  #connected = false;
  #session = 0;
  #increases = new IncreaseTracker();
  #personStats = new Map();
  #lastHistoryRefresh = 0;
  #lastPeopleRefresh = 0;
  #lastAutomaticRefresh = 0;
  #activity = null;
  #celebrationTimer = null;
  #cacheWrite = Promise.resolve();

  subscribe(listener) { this.#listeners.add(listener); return () => this.#listeners.delete(listener); }
  /** Collapses bursts of changes into one render. */
  changed() {
    if (this.#scheduled) return;
    this.#scheduled = true;
    queueMicrotask(() => { this.#scheduled = false; for (const listener of this.#listeners) listener(); });
  }

  get visibleModules() { return this.prefs.modules.filter(m => !this.prefs.hidden.includes(m)); }
  get favouritePeople() { return this.orderedPeople.filter(p => this.prefs.favourites.includes(p.login)); }
  get historyLabel() {
    if (!this.dashboard) return 'GitHub history';
    if (!this.dashboard.historyComplete) return this.loadingHistory ? 'Past year · loading history' : 'Past year only';
    return `Since ${Math.min(...this.dashboard.profile.years, Number(this.today.slice(0, 4)))}`;
  }
  get updatedAt() { return this.dashboard ? (this.dashboard.updatedAt + REFERENCE) * 1000 : null; }

  /** Per-person figures, built at most once per profile and day. */
  statsFor(login) {
    const profile = this.dashboard?.people?.[login];
    if (!profile) return null;
    const cached = this.#personStats.get(login);
    if (cached?.days === profile.days) return cached.stats;
    const stats = new Stats(profile.days, this.today);
    this.#personStats.set(login, { days: profile.days, stats });
    return stats;
  }

  #rebuildStats() {
    this.stats = this.dashboard ? new Stats([...this.dashboard.history, ...this.dashboard.profile.days], this.today) : null;
  }

  #orderPeople() {
    const { favourites, favouriteOrder } = this.prefs;
    const rank = new Map(favouriteOrder.map((login, i) => [login, i]).reverse());
    this.orderedPeople = [...(this.dashboard?.following ?? [])].sort((a, b) => {
      const first = favourites.includes(a.login), second = favourites.includes(b.login);
      if (first !== second) return first ? -1 : 1;
      if (first) {
        const x = rank.get(a.login) ?? Infinity, y = rank.get(b.login) ?? Infinity;
        if (x !== y) return x - y;
      }
      return a.login.localeCompare(b.login, undefined, { sensitivity: 'base' });
    });
  }

  #setDashboard(dashboard) {
    const old = this.dashboard;
    this.dashboard = dashboard;
    if (old?.history !== dashboard?.history || old?.profile.days !== dashboard?.profile.days) this.#rebuildStats();
    if (old?.following !== dashboard?.following) this.#orderPeople();
    this.changed();
  }

  #patchDashboard(patch) { if (this.dashboard) this.#setDashboard({ ...this.dashboard, ...patch }); }

  /** Changes preferences, saves them, and refreshes anything derived from them. */
  set(patch) {
    this.prefs = { ...this.prefs, ...patch };
    if ('favourites' in patch || 'favouriteOrder' in patch) this.#orderPeople();
    void invoke('save_preferences', { preferences: this.prefs }).catch(error => this.#fail(`Couldn't save your settings. ${error}`));
    this.changed();
  }

  #fail(message) { this.error = String(message?.message ?? message); this.changed(); }

  async start() {
    this.platform = await invoke('platform');
    const state = await invoke('load_state');
    this.prefs = normalise(state.preferences);
    if (state.migrated) void invoke('save_preferences', { preferences: this.prefs });
    if (state.cache?.profile) this.#setDashboard(state.cache);
    if (this.stats) this.#increases.observe(this.today, new Stats(this.dashboard.profile.days, this.today).todayCount);
    this.launchAtLogin = await invoke('launch_at_login');
    this.ghInstalled = await invoke('gh_installed');
    listen('tick', () => this.#timer());
    listen('push', () => { this.lastDetectedPush = Date.now(); this.checkAfterLocalActivity(); });
    listen('refresh', () => this.refresh(true));
    listen('check-updates', () => this.checkForUpdates(true));
    listen('preview-celebration', () => this.showCelebration(3, false, true));
    if (this.prefs.detectPushes) invoke('push_listen').catch(error => this.#fail(error));
    this.changed();
    await this.useCLI();
  }

  /** Every 30 seconds, from the native shell. */
  #timer() {
    this.changed(); // Keeps "Updated Nm ago" current.
    const oldDay = this.today;
    this.#tick();
    this.#checkReminder();
    // Stale data retries at most every five minutes, so being offline doesn't poll GitHub constantly.
    const stale = !this.updatedAt || Date.now() - this.updatedAt > 300_000;
    const retryDue = Date.now() - this.#lastAutomaticRefresh > 300_000;
    if (oldDay !== this.today || (stale && retryDue)) {
      this.#lastAutomaticRefresh = Date.now();
      this.refresh();
    }
    if (this.prefs.autoUpdate && native && Date.now() - this.prefs.lastUpdateCheck > 6 * 3600_000) void this.checkForUpdates(false);
  }

  /** Advances `today` only across a day boundary. */
  #tick() {
    const day = dayKey();
    if (day === this.today) return;
    this.today = day;
    this.#personStats.clear();
    this.#rebuildStats();
    this.changed();
  }

  refresh(force = false) {
    this.#tick();
    if (this.loading) return;
    if (!this.#connected) { void this.useCLI(); return; }
    if (!force && this.updatedAt && Date.now() - this.updatedAt < 30_000) return;
    void this.#refreshNow(true, force);
  }

  async #refreshNow(includeHistoryAndPeople = true, force = false) {
    if (!this.#connected || this.loading) return;
    const generation = this.#session;
    const current = () => generation === this.#session;
    this.loading = true;
    this.error = null;
    this.changed();
    try {
      const profile = await github.viewer();
      if (!current()) return;
      this.#tick();
      const previous = this.dashboard?.profile.person.login === profile.person.login ? this.dashboard : null;
      const oldCount = previous ? new Stats(previous.profile.days, this.today).todayCount : null;
      this.#setDashboard({
        profile, history: previous?.history ?? [], historyComplete: previous?.historyComplete ?? false,
        following: previous?.following ?? [], people: previous?.people ?? {}, updatedAt: nowSeconds(),
      });
      this.#saveCache();
      const increase = this.#increases.observe(this.today, this.stats.todayCount);
      if (increase > 0 && this.prefs.visualCelebrations) this.showCelebration(increase, this.stats.isNewRecord);
      if (increase > 0 && oldCount !== null) this.#milestone(this.stats, oldCount);

      if (includeHistoryAndPeople && Date.now() - this.#lastHistoryRefresh > 21_600_000) {
        this.loadingHistory = true;
        this.changed();
        try {
          const history = [];
          for (const year of [...profile.years].sort()) {
            history.push(...await github.history(profile.person.login, year));
            if (!current()) return;
          }
          this.#patchDashboard({ history: new Stats(history, this.today).days, historyComplete: true });
          this.#lastHistoryRefresh = Date.now();
          this.#saveCache();
        } catch (error) {
          if (current()) this.error = `Full history couldn't refresh. ${error.message ?? error}`;
        }
        this.loadingHistory = false;
        this.changed();
      }
      if (includeHistoryAndPeople && Date.now() - this.#lastPeopleRefresh > 300_000) {
        try {
          const following = await github.following();
          if (!current()) return;
          this.#patchDashboard({ following });
          this.#lastPeopleRefresh = Date.now();
          this.#saveCache();
          await this.loadPeople();
        } catch (error) {
          if (current()) { this.peopleError = String(error.message ?? error); this.changed(); }
        }
      }
      if (includeHistoryAndPeople && current()) void this.loadLeaderboard(force);
    } catch (error) {
      if (current()) this.error = String(error.message ?? error);
    } finally {
      if (current()) { this.loading = false; this.changed(); }
    }
  }

  /** Loads the leaderboard only while its widget is on the dashboard; results last five minutes. */
  async loadLeaderboard(force = false) {
    if (!this.#connected || !this.visibleModules.includes('leaderboard') || (this.board.loading && !force)) return;
    const generation = this.#session;
    const update = patch => { if (generation === this.#session) { this.board = { ...this.board, ...patch }; this.changed(); } };
    update({ loading: true, error: null });
    try {
      // A manual refresh reads the CLI's token again, so a newly added scope applies at once.
      if (force) await github.connect();
      const organizations = this.board.organizations && !force ? this.board.organizations : await leaderboard.organizations();
      update({ organizations });
      const organization = organizations.find(o => o.login === this.prefs.leaderboardOrg) ?? organizations[0];
      if (!organization) return update({ result: null, key: null });
      const key = `${organization.login}|${this.prefs.leaderboardPeriod}|${this.today}`;
      if (!force && key === this.board.key && Date.now() - this.board.fetchedAt < 300_000) return;
      if (key !== this.board.key) update({ result: null });
      const result = await leaderboard.standings(organization, this.prefs.leaderboardPeriod);
      update({ result: { ...result, organization }, key, fetchedAt: Date.now() });
    } catch (error) {
      update({ error: String(error.message ?? error) });
    } finally {
      update({ loading: false });
    }
  }

  /** Loads only the visible page of people and favourites, four requests at a time. */
  async loadPeople(logins) {
    if (!this.#connected || this.loadingPeople) return;
    const generation = this.#session;
    this.loadingPeople = true;
    this.peopleError = null;
    const known = new Set(this.orderedPeople.map(p => p.login));
    const wanted = [...new Set([...(logins ?? this.orderedPeople.slice(0, this.peopleLimit).map(p => p.login)),
      ...this.prefs.favourites.filter(login => known.has(login))])];
    try {
      for (let i = 0; i < wanted.length; i += 4) {
        const batch = wanted.slice(i, i + 4);
        const results = await Promise.allSettled(batch.map(login => github.profile(login)));
        if (generation !== this.#session) return;
        const people = { ...this.dashboard.people };
        results.forEach((result, j) => {
          if (result.status === 'fulfilled') people[batch[j]] = result.value;
          else this.peopleError = String(result.reason?.message ?? result.reason);
        });
        this.#patchDashboard({ people });
      }
      this.#saveCache();
    } finally {
      if (generation === this.#session) { this.loadingPeople = false; this.changed(); }
    }
  }

  async toggleFavourite(login) {
    const selected = this.prefs.favourites.includes(login);
    this.set({
      favourites: selected ? this.prefs.favourites.filter(l => l !== login) : [...this.prefs.favourites, login],
      favouriteOrder: this.prefs.favouriteOrder.includes(login) ? this.prefs.favouriteOrder : [...this.prefs.favouriteOrder, login],
    });
    if (!selected && !this.dashboard?.people?.[login]) {
      while (this.loadingPeople) await sleep(150);
      await this.loadPeople([login]);
    }
  }

  moveFavourite(login, by) {
    const order = this.favouritePeople.map(p => p.login);
    const index = order.indexOf(login);
    if (index < 0 || !order[index + by]) return;
    [order[index], order[index + by]] = [order[index + by], order[index]];
    this.set({ favouriteOrder: order });
  }

  moveModule(module, by) {
    const visible = this.visibleModules, index = visible.indexOf(module);
    if (index < 0 || !visible[index + by]) return;
    const order = [...this.prefs.modules];
    const from = order.indexOf(module), to = order.indexOf(visible[index + by]);
    [order[from], order[to]] = [order[to], order[from]];
    this.set({ modules: order });
  }

  setHidden(module, hidden) {
    this.set({ hidden: hidden ? [...this.prefs.hidden, module] : this.prefs.hidden.filter(m => m !== module) });
    if (module === 'leaderboard' && !hidden) void this.loadLeaderboard();
  }

  async useCLI() {
    if (this.loading) return;
    const generation = this.#session;
    this.loading = true;
    this.error = null;
    this.changed();
    try {
      await github.connect();
      // Validate the CLI identity before displaying another account's cache.
      const profile = await github.viewer();
      if (generation !== this.#session) return;
      this.#connected = true;
      if (this.dashboard?.profile.person.login !== profile.person.login) {
        this.#session += 1;
        this.#setDashboard(null);
        this.#increases = new IncreaseTracker();
        this.board = { organizations: null, result: null, loading: false, error: null, key: null, fetchedAt: 0 };
        this.#clearCelebration();
        this.#activity = null;
      }
      this.#lastHistoryRefresh = 0;
      this.#lastPeopleRefresh = 0;
      this.loading = false;
      await this.#refreshNow();
    } catch (error) {
      if (generation === this.#session) this.error = String(error.message ?? error);
    } finally {
      if (generation === this.#session && this.loading) { this.loading = false; this.changed(); }
      this.changed();
    }
  }

  async toggleLaunchAtLogin(enabled) {
    try { this.launchAtLogin = await invoke('set_launch_at_login', { enabled }); }
    catch (error) { this.error = String(error); }
    this.changed();
  }

  async #permission() {
    const notification = plugin('notification');
    if (!notification) return true;
    if (await notification.isPermissionGranted()) return true;
    return (await notification.requestPermission()) === 'granted';
  }

  async enableNotifications(enabled) {
    if (!enabled) return this.set({ notifications: false });
    try { this.set({ notifications: await this.#permission() }); } catch (error) { this.#fail(error); }
  }

  async enableReminder(enabled) {
    if (!enabled) return this.set({ streakReminder: false });
    try { this.set({ streakReminder: await this.#permission() }); } catch (error) { this.#fail(error); }
  }

  #notify(title, body) {
    try { plugin('notification')?.sendNotification({ title, body }); }
    catch { this.#fail('A notification couldn\'t be delivered. Check notification permissions in your system settings.'); }
  }

  showCelebration(count, record, sample = false) {
    clearTimeout(this.#celebrationTimer);
    this.celebration = { count, record, sample };
    const dark = systemDark();
    const colors = { accent: accent(this.prefs, dark), accentSoft: accent(this.prefs, dark, 0.25), gold: gold(dark) };
    void invoke('celebrate', { count, record, sample, style: this.prefs.celebrationStyle, reduced: reduceMotion(), colors });
    if (!reduceMotion()) {
      this.flashing = true;
      setTimeout(() => { this.flashing = false; this.changed(); }, 450);
    }
    this.#celebrationTimer = setTimeout(() => { this.celebration = null; this.changed(); }, 6000);
    this.changed();
  }

  #clearCelebration() { clearTimeout(this.#celebrationTimer); this.celebration = null; }

  async enablePushDetection(enabled) {
    try {
      await invoke('push_configure', { enabled });
      this.set({ detectPushes: enabled });
      if (!enabled) this.#activity = null;
    } catch (error) { this.#fail(error); }
  }

  /** After a confirmed push, check now and then give GitHub's calendar time to catch up. */
  async checkAfterLocalActivity() {
    if (!this.#connected || this.#activity) return;
    const generation = this.#session;
    const run = this.#activity = Symbol('activity');
    try {
      for (const delay of [0, 3, 7, 15, 30, 60, 90]) {
        await sleep(delay * 1000);
        if (generation !== this.#session || this.#activity !== run) return;
        if (this.loading) continue;
        const before = this.stats?.todayCount ?? 0;
        await this.#refreshNow(false);
        if (this.error || (this.stats?.todayCount ?? 0) > before) return;
      }
    } finally {
      if (this.#activity === run) this.#activity = null;
    }
  }

  #checkReminder() {
    const { dashboard, stats, prefs } = this;
    if (!prefs.streakReminder || !this.#connected || this.loading || !dashboard || !stats) return;
    if (dayKey(new Date(this.updatedAt)) !== this.today || Date.now() - this.updatedAt > 600_000) return;
    if (stats.todayCount !== 0 || stats.currentStreak === 0 || new Date().getHours() < prefs.reminderHour) return;
    if (prefs.lastReminderDay === this.today) return;
    this.set({ lastReminderDay: this.today });
    this.#notify(`Keep your ${stats.currentStreak}-day streak going.`, 'No contributions showing yet today. There\'s still time to make something.');
  }

  #milestone(stats, oldCount) {
    if (!this.prefs.notifications || !(oldCount === 0 || (stats.isNewRecord && oldCount <= stats.previousBest))) return;
    this.#notify(stats.isNewRecord ? 'A new personal best!' : 'You\'re on the board.',
      stats.isNewRecord ? `${stats.todayCount} contributions today. Look at you go.` : 'Your first contribution is in. Keep building something good.');
  }

  /** Checks GitHub Releases for a signed update; installs and relaunches only when the user agrees. */
  async checkForUpdates(manual) {
    const updater = plugin('updater'), dialog = plugin('dialog');
    if (!updater || this.checkingUpdates) return;
    this.checkingUpdates = true;
    this.set({ lastUpdateCheck: Date.now() });
    try {
      const update = await updater.check();
      if (!update) {
        if (manual) await dialog.message('You\'re running the latest version of GitGaze.', { title: 'GitGaze is up to date' });
        return;
      }
      const install = await dialog.ask(`GitGaze ${update.version} is available. You have ${update.currentVersion}.`,
        { title: 'A new version of GitGaze is available', okLabel: 'Install and Relaunch', cancelLabel: 'Later' });
      if (!install) return;
      await update.downloadAndInstall();
      await plugin('process').relaunch();
    } catch (error) {
      if (manual) await dialog.message(`The update couldn't be checked or installed. ${error}`, { title: 'Update failed', kind: 'error' });
    } finally {
      this.checkingUpdates = false;
      this.changed();
    }
  }

  /** Cache writes are serialised, so an older snapshot can never overwrite a newer one. */
  #saveCache() {
    const snapshot = JSON.stringify(this.dashboard);
    if (!this.dashboard) return;
    this.#cacheWrite = this.#cacheWrite.then(() => invoke('save_cache', { cache: snapshot }))
      .catch(error => this.#fail(`Couldn't save your offline cache. ${error}`));
  }

  /** Each time the flyout opens: fresh scroll, closed widget backs, and a refresh if stale. */
  presented() {
    this.page = 'dashboard';
    this.peopleLimit = 12;
    this.presentation += 1;
    this.refresh();
    this.changed();
  }
}
