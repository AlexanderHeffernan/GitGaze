// Draws the menu-bar label (macOS) or tray icon (Windows) into a canvas. The same drawing appears
// as the style previews in Settings. Six styles; each shows today's count and an optional streak.

import { accent, gold, primary } from './theme.js';

export const menuStyles = {
  orbit: 'Progress toward next daily best', charge: 'Progress toward next daily best', pulse: 'Last seven days of activity',
  mosaic: 'Last four weeks of activity', prism: 'Progress toward next daily best', ribbon: 'Last seven active days',
};

const ROUNDED = 'ui-rounded, "SF Pro Rounded", -apple-system, system-ui, "Segoe UI Variable Text", "Segoe UI", sans-serif';
const SYSTEM = '-apple-system, system-ui, "Segoe UI Variable Text", "Segoe UI", sans-serif';
const HEIGHT = 22;

/** The figures a label draws; compare `key()` to skip redundant renders. */
export function figures(store, style = store.prefs.menuStyle, showStreak = store.prefs.menuStreak) {
  const s = store.stats;
  return {
    style, showStreak,
    connected: Boolean(store.dashboard),
    stale: Boolean(store.error),
    count: s?.todayCount ?? 0,
    streak: s?.currentStreak ?? 0,
    progress: s?.progress ?? 0,
    record: Boolean(s?.isNewRecord),
    recent: s ? s.recent(28) : Array(28).fill(0),
    hasStats: Boolean(s),
  };
}

function text(ctx, value, size, weight, family, color) {
  ctx.font = `${weight} ${size}px ${family}`;
  return { width: ctx.measureText(value).width, draw: (x, h) => { ctx.font = `${weight} ${size}px ${family}`; ctx.fillStyle = color; ctx.textBaseline = 'middle'; ctx.fillText(value, x, h / 2 + 0.5); } };
}

function roundRect(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); ctx.fill(); }

/** The 16-tick record dial at menu-bar scale. */
function dial(ctx, cx, cy, diameter, f, colors) {
  const steps = 16, lit = f.count > 0 ? Math.max(1, Math.ceil(Math.min(1, f.progress) * steps)) : 0;
  for (let i = 0; i < steps; i++) {
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate((i / steps) * Math.PI * 2);
    ctx.fillStyle = i < lit ? (f.record ? colors.gold : colors.accent) : colors.primary(0.36);
    roundRect(ctx, -0.65, -diameter / 2 + 1, 1.3, 3, 0.65);
    ctx.restore();
  }
}

function mini(ctx, x, y, w, h, f, colors) {
  const tint = f.record ? colors.gold : colors.accent;
  const tintA = f.record ? colors.goldA : colors.accentA;
  if (f.style === 'prism') {
    const p = [[w / 2, 0], [w, h / 2], [w / 2, h], [0, h / 2]];
    for (let i = 0; i < 4; i++) {
      ctx.beginPath();
      ctx.moveTo(x + w / 2, y + h / 2); ctx.lineTo(x + p[i][0], y + p[i][1]); ctx.lineTo(x + p[(i + 1) % 4][0], y + p[(i + 1) % 4][1]);
      ctx.closePath();
      const lit = f.count > 0 && i / 4 < f.progress;
      ctx.fillStyle = lit ? tintA(1 - i * 0.16) : colors.primary(0.18 + i * 0.05);
      ctx.fill();
    }
  } else if (f.style === 'pulse') {
    const values = f.recent.slice(-7), maximum = Math.max(1, ...values);
    ctx.beginPath();
    values.forEach((v, i) => { const px = x + (i / 6) * w, py = y + 16 - (v / maximum) * 12; i ? ctx.lineTo(px, py) : ctx.moveTo(px, py); });
    ctx.lineCap = ctx.lineJoin = 'round';
    ctx.strokeStyle = tintA(0.18); ctx.lineWidth = 4; ctx.stroke();
    ctx.strokeStyle = tint; ctx.lineWidth = 1.2; ctx.stroke();
  } else {
    const mosaic = f.style === 'mosaic', values = f.recent.slice(mosaic ? -28 : -7);
    values.forEach((v, i) => {
      ctx.fillStyle = v > 0 ? tintA(0.4 + Math.min(0.6, v / 20)) : colors.primary(0.22);
      if (mosaic) roundRect(ctx, x + Math.floor(i / 7) * 3, y + (i % 7) * 2.6, 2, 1.8, 0.6);
      else roundRect(ctx, x + (i * w) / 7, y, w / 7 - 1, 3, 0.6);
    });
  }
}

/**
 * Renders the macOS label. Returns its size in points; the canvas is `scale`× that.
 * `dark` selects colours for the surface it sits on (the menu bar, or the Settings page).
 */
export function drawLabel(canvas, f, { prefs, dark, scale = 2, celebrating = false }) {
  const ctx = canvas.getContext('2d');
  const colors = {
    accent: accent(prefs, dark), accentA: a => accent(prefs, dark, a), gold: gold(dark), goldA: a => gold(dark, a),
    primary: (a = 0.85) => primary(dark, a), secondary: dark ? 'rgb(255 255 255 / 0.55)' : 'rgb(0 0 0 / 0.5)',
  };
  const count = f.connected ? String(f.count) : '–';
  const parts = []; // { width, draw(x, height) }
  const streak = f.showStreak && f.hasStats;
  if (f.style === 'charge') {
    const number = text(ctx, count, 11, 600, ROUNDED, colors.primary());
    const days = streak ? text(ctx, `${f.streak}d`, 9, 500, SYSTEM, colors.secondary) : null;
    const inner = number.width + (days ? 5 + 0.5 + 5 + days.width : 0);
    const width = inner + 22;
    parts.push({
      width, draw: (x, h) => {
        const top = (h - 19) / 2, outline = () => {
          ctx.beginPath();
          ctx.moveTo(x + 7, top + 0.5); ctx.lineTo(x + width - 0.5, top + 0.5);
          ctx.lineTo(x + width - 7, top + 18.5); ctx.lineTo(x + 0.5, top + 18.5); ctx.closePath();
        };
        outline(); ctx.fillStyle = colors.accentA(0.08); ctx.fill();
        outline(); ctx.strokeStyle = colors.accentA(0.55); ctx.lineWidth = 0.8; ctx.stroke();
        ctx.save(); ctx.translate(0, top); number.draw(x + 11, 19);
        if (days) {
          ctx.fillStyle = colors.primary(0.22); ctx.fillRect(x + 11 + number.width + 5, 5, 0.5, 9);
          days.draw(x + 11 + number.width + 10.5, 19);
        }
        ctx.restore();
        ctx.fillStyle = f.record ? colors.gold : colors.accent;
        roundRect(ctx, x + 7, top + 17, Math.max(0, (width - 18) * f.progress), 1.5, 0.75);
      },
    });
  } else if (f.style === 'ribbon') {
    const number = text(ctx, count, 12, 600, ROUNDED, colors.primary());
    const days = streak ? text(ctx, `${f.streak}d`, 9, 400, SYSTEM, colors.secondary) : null;
    const top = number.width + (days ? 4 + days.width : 0), bar = streak ? 38 : 25;
    const width = Math.max(top, bar);
    parts.push({
      width, draw: (x, h) => {
        const y = (h - (15 + 2 + 3)) / 2;
        ctx.save(); ctx.translate(x + (width - top) / 2, y); number.draw(0, 15); days?.draw(number.width + 4, 15); ctx.restore();
        mini(ctx, x + (width - bar) / 2, y + 17, bar, 3, f, colors);
      },
    });
  } else {
    if (f.style === 'orbit') parts.push({ width: 19, draw: (x, h) => dial(ctx, x + 9.5, h / 2, 19, f, colors) });
    else {
      const w = f.style === 'pulse' ? 29 : f.style === 'mosaic' ? 12 : 20;
      parts.push({ width: w, draw: (x, h) => mini(ctx, x, (h - 19) / 2, w, 19, f, colors) });
    }
    parts.push(text(ctx, count, 12, 600, ROUNDED, colors.primary()));
    if (streak) {
      const value = text(ctx, String(f.streak), 10, 500, SYSTEM, colors.primary());
      parts.push({
        width: 1 + 8 + 2 + value.width, draw: (x, h) => {
          ctx.save(); ctx.translate(x + 1, h / 2 - 4.5); ctx.scale(8 / 24, 8 / 24);
          ctx.fillStyle = colors.accent;
          ctx.fill(new Path2D('M15.914 4a1.5 1.5 0 00-2.474-1.561l-9 9A1.5 1.5 0 005.5 14h4.002a.5.5 0 01.471.666L8.086 20a1.5 1.5 0 002.475 1.56l9-9A1.5 1.5 0 0018.5 10h-3.997a.5.5 0 01-.472-.667z'));
          ctx.restore();
          value.draw(x + 11, h);
        },
      });
    }
  }
  if (f.stale) parts.push({ width: 3, draw: (x, h) => { ctx.fillStyle = colors.gold; ctx.beginPath(); ctx.arc(x + 1.5, h / 2, 1.5, 0, Math.PI * 2); ctx.fill(); } });

  const width = Math.ceil(parts.reduce((sum, part) => sum + part.width, 0) + 5 * (parts.length - 1));
  canvas.width = width * scale;
  canvas.height = HEIGHT * scale;
  ctx.setTransform(scale, 0, 0, scale, 0, 0);
  ctx.clearRect(0, 0, width, HEIGHT);
  if (celebrating) ctx.filter = 'brightness(1.25)';
  let x = 0;
  for (const part of parts) { part.draw(x, HEIGHT); x += part.width + 5; }
  ctx.filter = 'none';
  return { width, height: HEIGHT };
}

/** Windows tray icons are small squares: the record dial around today's count. */
export function drawTrayIcon(canvas, f, { prefs, dark }) {
  const size = 32, ctx = canvas.getContext('2d');
  canvas.width = canvas.height = size;
  ctx.clearRect(0, 0, size, size);
  const colors = { accent: accent(prefs, true), gold: gold(true), primary: a => primary(dark, a) };
  const steps = 16, lit = f.count > 0 ? Math.max(1, Math.ceil(Math.min(1, f.progress) * steps)) : 0;
  for (let i = 0; i < steps; i++) {
    ctx.save(); ctx.translate(16, 16); ctx.rotate((i / steps) * Math.PI * 2);
    ctx.fillStyle = i < lit ? (f.record ? colors.gold : colors.accent) : colors.primary(0.35);
    roundRect(ctx, -1.4, -15.5, 2.8, 6, 1.4);
    ctx.restore();
  }
  const count = f.connected ? (f.count > 99 ? '99+' : String(f.count)) : '–';
  ctx.font = `700 ${count.length > 2 ? 10 : count.length > 1 ? 13 : 15}px ${SYSTEM}`;
  ctx.fillStyle = dark ? '#fff' : '#111';
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillText(count, 16, 17);
  if (f.stale) { ctx.fillStyle = colors.gold; ctx.beginPath(); ctx.arc(27, 27, 3.5, 0, Math.PI * 2); ctx.fill(); }
  return { width: size, height: size };
}

export function tooltip(store) {
  if (!store.dashboard) return 'GitGaze · Connect GitHub CLI';
  return `GitGaze · ${store.stats?.todayCount ?? 0} contributions today · ${store.stats?.currentStreak ?? 0}-day streak · ${menuStyles[store.prefs.menuStyle] ?? menuStyles.charge}`;
}
