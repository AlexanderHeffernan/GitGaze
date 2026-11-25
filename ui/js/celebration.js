// Celebration overlay shown under the tray item when GitHub confirms new contributions.
// Three styles; the sparks gather into the actual increase ("+3"), then dissolve.
// Rendering is a pure function of elapsed time, so it stays smooth without particle state.

import { listen } from './bridge.js';

const canvas = document.getElementById('canvas');
const plain = document.getElementById('plain');
const ctx = canvas.getContext('2d');
const W = 440, H = 340;
let run = 0;

/** Samples the real glyph outlines of "+N" once, not per frame. */
function letterParticles(text) {
  const off = document.createElement('canvas'), c = off.getContext('2d');
  const font = '700 62px ui-monospace, "SF Mono", -apple-system, system-ui, "Segoe UI", sans-serif';
  c.font = font;
  const width = Math.ceil(c.measureText(text).width) + 8, height = 80;
  off.width = width; off.height = height;
  c.font = font; c.textBaseline = 'middle'; c.fillStyle = '#fff';
  c.fillText(text, 4, height / 2);
  const data = c.getImageData(0, 0, width, height).data;
  let minX = width, maxX = 0, minY = height, maxY = 0;
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) if (data[(y * width + x) * 4 + 3] > 128) {
    minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y);
  }
  const scale = Math.min(1, 230 / Math.max(1, maxX - minX)), step = 2.4 / scale, points = [];
  const midX = (minX + maxX) / 2, midY = (minY + maxY) / 2;
  for (let y = minY; y <= maxY; y += step) for (let x = minX; x <= maxX; x += step) {
    if (data[(Math.round(y) * width + Math.round(x)) * 4 + 3] > 128) points.push([(x - midX) * scale, (y - midY) * scale]);
  }
  return points;
}

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
function edgeOpacity(x, y, inset) {
  const p = clamp((Math.min(x, y, W - x, H - y) - inset) / 48, 0, 1);
  return p * p * (3 - 2 * p);
}

function dot(x, y, r, color, alpha) {
  ctx.globalAlpha = Math.max(0, alpha);
  ctx.fillStyle = color;
  ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
}

function fireworks(t, center, c) {
  if (t < 0.7) {
    const p = Math.min(1, t / 0.7);
    for (let ember = 0; ember < 12; ember++) {
      const y = -10 + (center.y + 10) * (1 - (1 - Math.max(0, p - ember * 0.013)) ** 3);
      dot(center.x, y, Math.max(0.6, 3.6 - ember * 0.23), ember === 0 ? '#fff' : c.accent, 1 - ember / 13);
    }
  }
  [0.65, 0.94, 1.2].forEach((start, burst) => {
    const age = t - start;
    if (age <= 0 || age >= 2.4) return;
    const ox = center.x + [0, -75, 72][burst], oy = center.y + [0, 30, 16][burst];
    const spread = 1 - (1 - Math.min(1, age / 1.8)) ** 3;
    const fade = clamp((2.4 - age) / 0.9, 0, 1);
    const halo = ctx.createRadialGradient(ox, oy, 0, ox, oy, 48);
    halo.addColorStop(0, 'rgb(255 255 255 / 0.65)'); halo.addColorStop(0.5, c.accentSoft); halo.addColorStop(1, 'transparent');
    ctx.globalAlpha = Math.max(0, 1 - age / 0.65); ctx.fillStyle = halo; ctx.fillRect(ox - 48, oy - 48, 96, 96);
    ctx.globalAlpha = Math.max(0, 1 - age / 0.7) * 0.25; ctx.strokeStyle = c.accent; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.arc(ox, oy, age * 135, 0, Math.PI * 2); ctx.stroke();
    for (let i = 0; i < 96; i++) {
      const angle = (i * Math.PI * 2) / 96 + (i % 7) * 0.019;
      const distance = (40 + ((i * 29) % 78)) * (burst === 0 ? 1 : 0.72);
      const x = ox + Math.cos(angle) * distance * spread, y = oy + Math.sin(angle) * distance * spread + age * age * 31;
      const color = i % 7 === 0 ? '#fff' : i % 4 === 0 ? c.gold : c.accent;
      if (i % 3 === 0) {
        ctx.globalAlpha = fade * 0.9; ctx.strokeStyle = color; ctx.lineWidth = 1.4; ctx.lineCap = 'round';
        const tail = 15 * (1 - age / 3);
        ctx.beginPath(); ctx.moveTo(x - Math.cos(angle) * tail, y - Math.sin(angle) * tail); ctx.lineTo(x, y); ctx.stroke();
      }
      dot(x, y, 3, color, fade * 0.18);
      ctx.save(); ctx.globalAlpha = fade; ctx.translate(x, y); ctx.rotate(angle + age * (i % 2 === 0 ? 2 : -2));
      ctx.fillStyle = color; ctx.fillRect(-1, -1, i % 4 === 0 ? 5 : 2, 2); ctx.restore();
    }
  });
}

function alternate(t, style, c) {
  const center = { x: W / 2, y: 145 }, fade = clamp((3.7 - t) / 1.2, 0, 1);
  if (style === 'nova') {
    const radius = t < 0.65 ? 150 * (1 - t / 0.65) ** 2 : 135 * (1 - Math.exp(-(t - 0.65) * 2.5));
    for (let i = 0; i < 84; i++) {
      const angle = (i * Math.PI * 2) / 84 + t * 0.3, orbit = radius + Math.sin(i * 2.1) * 14;
      const x = center.x + Math.cos(angle) * orbit, y = center.y + Math.sin(angle) * orbit * 0.8;
      const color = i % 4 === 0 ? c.gold : c.accent;
      dot(x, y, 4, color, fade * 0.25);
      dot(x, y, 1.4, i % 5 === 0 ? '#fff' : color, fade);
    }
    const flash = Math.max(0, 1 - Math.abs(t - 0.7) / 0.35);
    const glow = ctx.createRadialGradient(center.x, center.y, 0, center.x, center.y, 100);
    glow.addColorStop(0, 'rgb(255 255 255 / 0.65)'); glow.addColorStop(0.5, c.accentSoft); glow.addColorStop(1, 'transparent');
    ctx.globalAlpha = flash; ctx.fillStyle = glow; ctx.fillRect(center.x - 100, center.y - 100, 200, 200);
  } else {
    for (let i = 0; i < 48; i++) {
      const age = t - (i % 12) * 0.075;
      if (age <= 0) continue;
      const x = ((i * 67) % 440) + 160 - age * 130, y = ((i * 37) % 180) - 150 + age * 135, length = 14 + (i % 5) * 5;
      const color = i % 4 === 0 ? c.gold : c.accent;
      const visibility = fade * edgeOpacity(x, y, 44);
      ctx.lineCap = 'round';
      ctx.globalAlpha = visibility * 0.3; ctx.strokeStyle = color; ctx.lineWidth = 5;
      ctx.beginPath(); ctx.moveTo(x + length, y - length); ctx.lineTo(x, y); ctx.stroke();
      const trail = ctx.createLinearGradient(x + length, y - length, x, y);
      trail.addColorStop(0, 'transparent'); trail.addColorStop(0.5, color); trail.addColorStop(1, '#fff');
      ctx.globalAlpha = visibility * 0.85; ctx.strokeStyle = trail; ctx.lineWidth = 1.6;
      ctx.beginPath(); ctx.moveTo(x + length, y - length); ctx.lineTo(x, y); ctx.stroke();
    }
  }
}

function number(t, glyph, center, style, c) {
  const tint = c.record ? c.gold : c.accent, fade = clamp((4.5 - t) / 0.8, 0, 1);
  glyph.forEach(([px, py], i) => {
    const age = t - 0.65 - (i % 9) * 0.018;
    if (age <= 0) return;
    const angle = i * 2.39996, gather = clamp((age - 0.25) / 1.05, 0, 1), eased = gather * gather * (3 - 2 * gather);
    const radius = 65 + (i % 83);
    let ox, oy;
    if (style === 'meteors') { ox = px + 160 + (i % 7) * 9; oy = py - 160 - (i % 11) * 6; }
    else { const spread = style === 'nova' ? 1 : Math.min(1, age / 0.25); ox = Math.cos(angle) * radius * spread; oy = Math.sin(angle) * radius * spread; }
    const dissolve = Math.max(0, t - 3.5);
    const x = center.x + ox * (1 - eased) + px * eased + Math.cos(angle) * dissolve * dissolve * 30;
    const y = center.y + oy * (1 - eased) + py * eased + Math.sin(angle) * dissolve * dissolve * 30;
    const opacity = Math.min(1, age * 5) * fade * edgeOpacity(x, y, 12);
    dot(x, y, 3.3, tint, opacity * 0.22);
    dot(x, y, 0.95, i % 5 === 0 ? '#fff' : tint, opacity * (0.82 + 0.18 * Math.sin(t * 5 + i)));
  });
}

/** Fades every edge, so nothing is clipped by the window boundary. */
function mask() {
  ctx.globalAlpha = 1;
  ctx.globalCompositeOperation = 'destination-in';
  const across = ctx.createLinearGradient(0, 0, W, 0);
  across.addColorStop(0, 'transparent'); across.addColorStop(0.12, '#000'); across.addColorStop(0.88, '#000'); across.addColorStop(1, 'transparent');
  ctx.fillStyle = across; ctx.fillRect(0, 0, W, H);
  const down = ctx.createLinearGradient(0, 0, 0, H);
  down.addColorStop(0, 'transparent'); down.addColorStop(0.12, '#000'); down.addColorStop(0.86, '#000'); down.addColorStop(1, 'transparent');
  ctx.fillStyle = down; ctx.fillRect(0, 0, W, H);
  ctx.globalCompositeOperation = 'source-over';
}

listen('celebrate', ({ count, record, style, anchor, reduced, accent, accentSoft, gold }) => {
  const id = ++run;
  const colors = { accent, accentSoft, gold, record };
  if (reduced) {
    canvas.hidden = true;
    plain.hidden = false;
    plain.textContent = `+${count}`;
    plain.style.color = record ? gold : accent;
    return;
  }
  canvas.hidden = false;
  plain.hidden = true;
  const scale = devicePixelRatio || 2;
  canvas.width = W * scale; canvas.height = H * scale;
  const glyph = letterParticles(`+${count}`);
  const center = { x: clamp(anchor, 170, W - 170), y: 145 };
  const started = performance.now();
  const frame = now => {
    if (id !== run) return;
    const t = (now - started) / 1000;
    ctx.setTransform(scale, 0, 0, scale, 0, 0);
    ctx.clearRect(0, 0, W, H);
    if (t < 4.7) {
      if (style === 'fireworks') fireworks(t, center, colors); else alternate(t, style, colors);
      number(t, glyph, center, style, colors);
      mask();
      requestAnimationFrame(frame);
    }
  };
  requestAnimationFrame(frame);
});
