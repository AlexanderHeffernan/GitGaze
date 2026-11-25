// Dark appearances of all ten built-in palettes, from Sources/GitGaze/Components.swift.
const colors = {
  Violet: '.69 .61 1', Coral: '1 .57 .49', Ice: '.42 .81 .97', Graphite: '.83 .85 .91',
  Mint: '.46 .86 .73', Rose: '1 .56 .74', Amber: '1 .75 .35', Cobalt: '.46 .63 1',
  Orchid: '.86 .56 1', Lagoon: '.30 .85 .86',
};

const preview = document.querySelector('.preview');
const menu = preview.querySelector('.menu-item');
const popover = document.querySelector('#popover');
const palettes = document.querySelector('#palettes');
const paletteName = document.querySelector('#palette-name');
const swatches = palettes.querySelector('.swatches');
const history = document.querySelector('#history-options');
const heatmap = document.querySelector('#heatmap');

for (const [name, rgb] of Object.entries(colors)) {
  const label = document.createElement('label');
  label.className = 'swatch';
  label.title = name;
  label.style.setProperty('--swatch', `color(srgb ${rgb})`);
  const input = document.createElement('input');
  input.type = 'radio';
  input.name = 'palette';
  input.value = name;
  input.checked = name === 'Violet';
  input.setAttribute('aria-label', name);
  const dot = document.createElement('span');
  dot.setAttribute('aria-hidden', 'true');
  label.append(input, dot);
  swatches.append(label);
}

function showPopover(open) {
  menu.setAttribute('aria-expanded', open);
  popover.hidden = !open;
}

menu.addEventListener('click', () => showPopover(popover.hidden));
preview.addEventListener('keydown', event => {
  if (event.key === 'Escape' && !popover.hidden) {
    showPopover(false);
    menu.focus();
  }
});
palettes.addEventListener('change', event => {
  const name = event.target.value;
  document.documentElement.style.setProperty('--accent', `color(srgb ${colors[name]})`);
  paletteName.textContent = name;
  if (popover.hidden) showPopover(true);
});

function drawHeatmap(weeks, target = heatmap, seed = 0, miniature = false) {
  const short = weeks === 26;
  const namespace = 'http://www.w3.org/2000/svg';
  const cells = document.createDocumentFragment();
  const step = short && !miniature ? 12.2 : 6;
  const size = short && !miniature ? 9 : 4.6;
  const row = short && !miniature ? 10.6 : 6.1;
  if (!miniature) [short ? '2026-06' : '2025-11', 'Today'].forEach((label, i) => {
    const text = document.createElementNS(namespace, 'text');
    text.setAttribute('x', i ? 319 : 0);
    text.setAttribute('text-anchor', i ? 'end' : 'start');
    text.setAttribute('y', short ? 86 : 56);
    text.textContent = label;
    cells.append(text);
  });
  // Fixed synthetic pattern. Short history is the same grid’s final 26 weeks.
  for (let week = 0; week < weeks; week++) {
    for (let day = 0; day < 7; day++) {
      if (week === weeks - 1 && day > 2) continue;
      const index = (53 - weeks + week) * 7 + day + seed;
      const score = ((Math.imul(index + 47, 0x45d9f3b) ^ Math.imul(index + 97, 0x119de1f3)) >>> 21) % 23;
      const level = week >= weeks - 2 ? Math.max(1, score % 5) : score < 10 ? 0 : 1 + score % 4;
      const cell = document.createElementNS(namespace, 'rect');
      cell.setAttribute('x', week * step);
      cell.setAttribute('y', day * row);
      cell.setAttribute('width', size);
      cell.setAttribute('height', size);
      cell.setAttribute('rx', short ? 1.8 : .85);
      cell.dataset.level = level;
      cells.append(cell);
    }
  }
  if (target === heatmap) {
    heatmap.setAttribute('viewBox', `0 0 320 ${short ? 88 : 59}`);
    heatmap.setAttribute('aria-label', `Sample contribution heatmap, ${short ? 'six months' : 'one year'}`);
    heatmap.classList.toggle('six-months', short);
  }
  target.replaceChildren(cells);
}

const historyToggle = document.querySelector('#history-toggle');
historyToggle.addEventListener('click', () => {
  history.hidden = !history.hidden;
  historyToggle.setAttribute('aria-expanded', !history.hidden);
});
history.addEventListener('change', event => drawHeatmap(Number(event.target.value)));

document.querySelectorAll('.friend-toggle').forEach((button, index) => {
  const full = document.getElementById(button.getAttribute('aria-controls'));
  const seed = 501 * (index + 1);
  drawHeatmap(26, button.querySelector('svg'), seed, true);
  drawHeatmap(53, full, seed);
  button.hidden = false;
  button.addEventListener('click', () => {
    const open = button.getAttribute('aria-expanded') !== 'true';
    button.setAttribute('aria-expanded', open);
    full.toggleAttribute('hidden', !open);
    if (open) full.scrollIntoView({ block: 'nearest' });
  });
});

drawHeatmap(53);
menu.disabled = false;
historyToggle.hidden = false;
palettes.hidden = false;
