// Stoke, the flame made of contribution squares, comes alive on the site: it flickers, watches the
// pointer, blinks, hops when poked or when the demo celebrates, and lights the squares around it.
// With reduced motion, everything stays still and only the speech bubble changes.

import { markSVG } from './app/js/mark.js';

const $$ = selector => [...document.querySelectorAll(selector)];
const still = matchMedia('(prefers-reduced-motion: reduce)');
const random = (min, max) => min + Math.random() * (max - min);

// Every mark on the page, tinted by the current accent through `currentColor`.
for (const el of $$('[data-mark]')) {
  el.innerHTML = markSVG('currentColor', { size: Number(el.dataset.mark) });
  // Each square flickers on its own beat; the faint tips flicker most, like a flame's edge.
  for (const square of el.querySelectorAll('.sq')) {
    const level = Number(square.dataset.level);
    square.style.setProperty('--beat', `${random(1.1, 2.4).toFixed(2)}s`);
    square.style.setProperty('--delay', `${-random(0, 3).toFixed(2)}s`);
    square.style.setProperty('--low', String([0, 0.25, 0.45, 0.7, 0.88][level]));
  }
}

const mascot = document.querySelector('[data-mascot]');
const bubble = document.querySelector('[data-bubble]');

// ----- Eyes: follow the pointer, and blink now and then -----

const pupils = mascot ? [...mascot.querySelectorAll('.pupil')] : [];
let look = null;
addEventListener('pointermove', event => {
  if (!mascot || still.matches) return;
  look = [event.clientX, event.clientY];
  requestAnimationFrame(aim);
}, { passive: true });

function aim() {
  if (!look) return;
  const box = mascot.getBoundingClientRect();
  const dx = look[0] - (box.left + box.width / 2), dy = look[1] - (box.top + box.height * 0.6);
  const distance = Math.hypot(dx, dy) || 1, reach = Math.min(1, distance / 260);
  // Pupils start glancing up and right (the drawing's resting look), so aim relative to that.
  const x = (dx / distance) * 5 * reach - 4.5, y = (dy / distance) * 5 * reach + 3.5;
  for (const pupil of pupils) pupil.style.transform = `translate(${x.toFixed(2)}px, ${y.toFixed(2)}px)`;
}

function blink() {
  if (mascot && !still.matches && !document.hidden) {
    mascot.classList.add('blink');
    setTimeout(() => mascot.classList.remove('blink'), 140);
  }
  setTimeout(blink, random(2600, 6200));
}
setTimeout(blink, 2200);

// ----- Speech bubble: little things the app would tell you -----

const lines = ['+3 today', '12-day streak', '2 to beat your best', 'You’re #2 this week', 'Keep it burning'];
let line = 0;
function say(text) {
  if (!bubble) return;
  bubble.classList.remove('show');
  setTimeout(() => { bubble.textContent = text; bubble.classList.add('show'); }, 180);
}
if (bubble) {
  setTimeout(() => say(lines[0]), 900);
  setInterval(() => { if (!document.hidden) say(lines[(line = (line + 1) % lines.length)]); }, 4200);
}

// ----- Hop: when poked, or when the demo celebrates -----

/** Hops and throws a handful of contribution squares into the air. */
export function cheer(count = 6) {
  if (!mascot || still.matches) return;
  mascot.classList.remove('hop');
  void mascot.offsetWidth; // Restart the animation.
  mascot.classList.add('hop');
  const box = mascot.getBoundingClientRect();
  for (let i = 0; i < count; i++) {
    const spark = document.createElement('span');
    spark.className = 'spark';
    const size = random(5, 10);
    Object.assign(spark.style, {
      left: `${box.left + box.width * random(0.25, 0.75)}px`, top: `${box.top + scrollY + box.height * 0.3}px`,
      width: `${size}px`, height: `${size}px`, opacity: String(random(0.5, 1)),
    });
    spark.style.setProperty('--x', `${random(-70, 70).toFixed(0)}px`);
    spark.style.setProperty('--y', `${random(-130, -60).toFixed(0)}px`);
    spark.style.setProperty('--spin', `${random(-200, 200).toFixed(0)}deg`);
    document.body.append(spark);
    spark.addEventListener('animationend', () => spark.remove());
  }
}
mascot?.addEventListener('click', () => { cheer(9); say(['Stoked!', 'Hot streak!', '+1 today'][Math.floor(Math.random() * 3)]); });

// ----- The commit field: squares behind the hero light up around the pointer -----

const field = document.querySelector('[data-field]');
if (field) {
  const context = field.getContext('2d');
  const PITCH = 16, CELL = 11;
  const lit = new Map(); // "column,row" → brightness from 0 to 1
  let frame = 0, visible = true, pointer = null, ratio = 1;

  const resize = () => {
    ratio = Math.min(2, devicePixelRatio || 1);
    field.width = field.clientWidth * ratio;
    field.height = field.clientHeight * ratio;
    schedule();
  };
  const schedule = () => { if (!frame && visible && !still.matches) frame = requestAnimationFrame(draw); };
  const light = (column, row, amount) => {
    const key = `${column},${row}`;
    lit.set(key, Math.min(1, Math.max(lit.get(key) ?? 0, amount)));
  };

  function draw() {
    frame = 0;
    const accent = getComputedStyle(document.documentElement).getPropertyValue('--accent-rgb').trim().split(/\s+/).join(',');
    if (pointer) {
      const [px, py] = pointer, column = Math.floor(px / PITCH), row = Math.floor(py / PITCH);
      for (let dc = -3; dc <= 3; dc++) for (let dr = -3; dr <= 3; dr++) {
        const distance = Math.hypot(dc, dr);
        if (distance <= 3.2) light(column + dc, row + dr, (1 - distance / 3.4) * 0.55);
      }
    }
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    context.clearRect(0, 0, field.clientWidth, field.clientHeight);
    for (const [key, amount] of lit) {
      const [column, row] = key.split(',').map(Number);
      context.fillStyle = `rgba(${accent},${(amount * 0.42).toFixed(3)})`;
      context.beginPath();
      context.roundRect(column * PITCH + (PITCH - CELL) / 2, row * PITCH + (PITCH - CELL) / 2, CELL, CELL, 2.5);
      context.fill();
      const next = amount - 0.022;
      if (next <= 0) lit.delete(key); else lit.set(key, next);
    }
    if (lit.size || pointer) schedule();
  }

  // Now and then a "commit" lands somewhere in the field.
  setInterval(() => {
    if (document.hidden || !visible || still.matches) return;
    light(Math.floor(random(0, field.clientWidth / PITCH)), Math.floor(random(0, field.clientHeight / PITCH)), random(0.5, 1));
    schedule();
  }, 380);

  const hero = field.parentElement;
  hero.addEventListener('pointermove', event => {
    if (event.pointerType !== 'mouse') return;
    const box = field.getBoundingClientRect();
    pointer = [event.clientX - box.left, event.clientY - box.top];
    schedule();
  }, { passive: true });
  hero.addEventListener('pointerleave', () => { pointer = null; });
  new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; schedule(); }).observe(field);
  new ResizeObserver(resize).observe(field);
}

// ----- The streak: squares fill in as it scrolls into view, then Stoke hops at the end -----

const streak = document.querySelector('[data-streak]');
if (streak) {
  const days = Number(streak.dataset.streak);
  const levels = Array.from({ length: days }, (_, i) => 1 + Math.min(3, Math.floor((i / days) * 4 + Math.random() * 0.8)));
  streak.insertAdjacentHTML('afterbegin', levels.map((level, i) => `<i style="--i:${i}" data-level="${level}"></i>`).join(''));
  const tail = streak.querySelector('.streak-mascot');
  new IntersectionObserver(([entry], observer) => {
    if (!entry.isIntersecting) return;
    streak.classList.add('on');
    observer.disconnect();
    setTimeout(() => tail?.classList.add('hop'), still.matches ? 0 : days * 45 + 200);
  }, { threshold: 0.6 }).observe(streak);
}
