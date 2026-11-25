// The demo embeds the real app UI (app/ is the app's ui/ folder), which answers with sample data
// in a browser. The menu-bar label, tray icon and celebrations use the app's own drawing code.

import { drawLabel, drawTrayIcon, figures, menuStyles } from './app/js/status.js';
import { palettes, title } from './app/js/theme.js';

const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const stage = $('#stage');
const popover = $('#popover');
const burst = $('#burst');
const burstDemo = $('#burst-demo');
const rgb = values => values.map(v => Math.round(v * 255)).join(' ');

const detected = /Win/.test(navigator.platform) || /Windows/.test(navigator.userAgent) ? 'windows' : /Mac|iPhone|iPad/.test(navigator.platform) ? 'macos' : null;
let platform = detected ?? 'macos';
let scheme = 'dark';
let palette = 'violet';
let store = null;

// ----- Copy that follows the visitor's platform -----

if (detected) {
  const mac = detected === 'macos';
  $$('[data-os-name]').forEach(el => { el.textContent = mac ? 'macOS, and Windows too' : 'Windows, and macOS too'; });
  $$('[data-bar-name]').forEach(el => { el.textContent = mac ? 'menu bar' : 'system tray'; });
  $('[data-download] span').textContent = `Get GitGaze for ${mac ? 'Mac' : 'Windows'}`;
}

function clock() {
  const now = new Date();
  const mac = `${now.toLocaleDateString(undefined, { weekday: 'short' })} ${now.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}`;
  $$('.menubar [data-clock]').forEach(el => { el.textContent = mac; });
  $$('.tray [data-clock]').forEach(el => { el.textContent = now.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' }); });
  $$('[data-date]').forEach(el => { el.textContent = now.toLocaleDateString(); });
}
clock();
setInterval(clock, 15000);

// ----- Accent -----

function setAccent(prefs) {
  const value = prefs.palette === 'custom' ? null : palettes[prefs.palette]?.[1];
  if (value) document.documentElement.style.setProperty('--accent-rgb', rgb(value));
  palette = prefs.palette;
  $$('#swatches button').forEach(b => b.setAttribute('aria-checked', String(b.dataset.palette === palette)));
}

for (const [name, [, dark]] of Object.entries(palettes)) {
  const button = document.createElement('button');
  button.type = 'button';
  button.setAttribute('role', 'radio');
  button.dataset.palette = name;
  button.title = title(name);
  button.setAttribute('aria-label', title(name));
  button.style.setProperty('--swatch', `rgb(${rgb(dark)})`);
  button.addEventListener('click', () => { store ? store.set({ palette: name }) : setAccent({ palette: name }); });
  $('#swatches').append(button);
}
setAccent({ palette });

// ----- The embedded app -----

function connect() {
  const win = popover.contentWindow;
  if (!win?.gitgaze) { setTimeout(connect, 50); return; }
  store = win.gitgaze;
  store.set({ palette, appearance: scheme });
  store.subscribe(render);
  render();
}
popover.addEventListener('load', connect);

// The app asks its native shell to show celebrations; in a browser it posts them here instead.
addEventListener('message', ({ data, origin }) => {
  if (origin !== location.origin || data?.gitgaze !== 'celebrate') return;
  celebrate(burst, { ...data.args, fromBelow: platform === 'windows' }, anchorX);
});

function celebrate(frame, args, anchor) {
  const emit = frame.contentWindow?.gitgazeEmit;
  if (emit) emit('celebrate', { ...args, ...args.colors, anchor });
}

let anchorX = 220;
let lastKey = '';
function render() {
  if (!store) return;
  setAccent(store.prefs);
  const f = figures(store);
  const key = JSON.stringify([f, store.prefs.palette, store.prefs.customDark, store.prefs.customLight, scheme, platform, store.flashing]);
  if (key !== lastKey) {
    lastKey = key;
    const dark = scheme === 'dark';
    if (platform === 'macos') {
      const canvas = $('#menu-label');
      const size = drawLabel(canvas, f, { prefs: store.prefs, dark, scale: 2, celebrating: store.flashing });
      canvas.style.width = `${size.width}px`;
      canvas.style.height = `${size.height}px`;
    } else {
      const canvas = $('#tray-icon');
      drawTrayIcon(canvas, f, { prefs: store.prefs, dark });
      canvas.style.width = canvas.style.height = '20px';
    }
    drawStyles();
  }
  place();
}

/** Hangs the popover under the label, or above the tray icon, as the native shell does. */
function place() {
  const box = stage.getBoundingClientRect();
  const width = stage.clientWidth, zoom = box.width / stage.offsetWidth || 1;
  const item = (platform === 'macos' ? $('#menu-item') : $('#tray-item')).getBoundingClientRect();
  // Positions are relative to the stage's padding box, inside its border.
  const center = (item.left + item.width / 2 - box.left) / zoom - stage.clientLeft;
  const left = Math.max(8, Math.min(width - 392, center - 192));
  stage.style.setProperty('--pop-x', `${left}px`);
  const burstLeft = Math.max(0, Math.min(width - 440, center - 220));
  stage.style.setProperty('--burst-x', `${burstLeft}px`);
  anchorX = center - burstLeft;
  const doc = popover.contentDocument?.documentElement;
  if (doc) doc.style.setProperty('--arrow-x', `${center - left}px`);
}

/**
 * Scales the desktop so it fits the column on phones and, beside the copy, fits the window's
 * height together with its controls, so the whole demo shows without scrolling.
 * It scales with a transform, not CSS zoom: Safari draws zoomed iframes at the wrong size,
 * leaving white boxes where the app and the celebration overlay should be.
 */
function fit() {
  const demo = stage.parentElement, height = 692;
  // Measure the column without the last fit's fixed width, which would stretch it.
  Object.assign(stage.style, { transform: '', width: '', maxWidth: '', marginInline: '', marginBottom: '' });
  let zoom = Math.min(1, demo.clientWidth / 420);
  if (matchMedia('(min-width: 981px)').matches) {
    const hero = $('.hero'), style = getComputedStyle(hero);
    const top = hero.getBoundingClientRect().top + scrollY + parseFloat(style.paddingTop);
    const below = $('.controls').offsetHeight + parseFloat(getComputedStyle(demo).rowGap) + parseFloat(style.paddingBottom);
    zoom = Math.min(zoom, Math.max(0.6, (innerHeight - top - below) / height));
  }
  const scaled = zoom < 1, width = Math.min(560, demo.clientWidth / zoom);
  // Negative margins shrink the stage's footprint to its scaled size.
  Object.assign(stage.style, {
    transform: scaled ? `scale(${zoom.toFixed(3)})` : '', transformOrigin: 'top center',
    width: scaled ? `${width}px` : '', maxWidth: scaled ? 'none' : '',
    marginInline: scaled ? `${(width * zoom - width) / 2}px` : '',
    marginBottom: scaled ? `${height * zoom - height}px` : '',
  });
  place();
}
addEventListener('resize', fit);
fit();

// ----- Demo controls -----

function setPlatform(next) {
  platform = next;
  stage.dataset.platform = next;
  $$('.controls [data-platform]').forEach(b => b.setAttribute('aria-checked', String(b.dataset.platform === next)));
  store = null;
  lastKey = '';
  popover.height = next === 'macos' ? 651 : 640;
  popover.src = `./app/index.html?platform=${next}`;
}
$$('.controls [data-platform]').forEach(b => b.addEventListener('click', () => { if (b.dataset.platform !== platform) setPlatform(b.dataset.platform); }));

$('#scheme').addEventListener('click', () => {
  scheme = scheme === 'dark' ? 'light' : 'dark';
  stage.dataset.scheme = scheme;
  $('#scheme').setAttribute('aria-label', `Switch to ${scheme === 'dark' ? 'light' : 'dark'} appearance`);
  store?.set({ appearance: scheme });
  lastKey = '';
  render();
});

$('#celebrate').addEventListener('click', () => store?.showCelebration(3, false, true));

if (platform !== 'macos') setPlatform(platform);
else if (popover.contentDocument?.readyState === 'complete') connect();

// ----- Feature tiles -----

function drawStyles() {
  const host = $('#styles');
  if (!store) return;
  if (!host.children.length) {
    for (const style of Object.keys(menuStyles)) {
      host.insertAdjacentHTML('beforeend', `<div class="style"><div class="bar"><canvas data-style="${style}"></canvas></div><b>${title(style)}</b><span>${menuStyles[style]}</span></div>`);
    }
  }
  for (const canvas of host.querySelectorAll('canvas')) {
    const size = drawLabel(canvas, figures(store, canvas.dataset.style, true), { prefs: store.prefs, dark: true, scale: 2 });
    canvas.style.width = `${size.width}px`;
    canvas.style.height = `${size.height}px`;
  }
}

let burstStyle = 'fireworks';
function playBurst() {
  const colors = { accent: `rgb(${getComputedStyle(document.documentElement).getPropertyValue('--accent-rgb')})`, accentSoft: `rgb(${getComputedStyle(document.documentElement).getPropertyValue('--accent-rgb')} / 0.25)`, gold: 'rgb(255 199 112)' };
  celebrate(burstDemo, { count: 3 + Math.floor(Math.random() * 5), record: false, style: burstStyle, reduced: matchMedia('(prefers-reduced-motion: reduce)').matches, colors }, 220);
}
$$('.burst-picks button').forEach(b => b.addEventListener('click', () => {
  burstStyle = b.dataset.style;
  $$('.burst-picks button').forEach(x => x.setAttribute('aria-checked', String(x === b)));
  playBurst();
}));
let burstTimer = null;
new IntersectionObserver(([entry]) => {
  clearInterval(burstTimer);
  if (entry.isIntersecting) { playBurst(); burstTimer = setInterval(playBurst, 5200); }
}, { threshold: 0.5 }).observe(burstDemo);

// ----- Install -----

function showInstall(which) {
  $$('[data-install]').forEach(b => b.setAttribute('aria-checked', String(b.dataset.install === which)));
  $$('.installer').forEach(el => { el.hidden = el.dataset.for !== which; });
}
$$('[data-install]').forEach(b => b.addEventListener('click', () => showInstall(b.dataset.install)));
showInstall(detected ?? 'macos');

$$('.copy').forEach(button => {
  if (!navigator.clipboard?.writeText) { button.hidden = true; return; }
  button.addEventListener('click', async () => {
    const status = $('#copy-status');
    try {
      await navigator.clipboard.writeText($(`#${button.dataset.copy}`).textContent);
      button.setAttribute('data-copied', '');
      status.textContent = 'Copied. Paste it into your terminal.';
      setTimeout(() => button.removeAttribute('data-copied'), 1800);
    } catch {
      status.textContent = 'Couldn’t copy. Select the command and copy it yourself.';
    }
  });
});
