// The Stoke mark: a flame made of contribution squares, with a face. One definition draws the app
// icon, the header, the website and its favicon, tinted with the current palette's accent.

// Each digit is a square's intensity, from 1 (a faint flicker at the tips) to 4 (the hot base),
// like a contribution graph. "." is empty.
const full = {
  rows: [
    '.......1.....',
    '......22.....',
    '......232....',
    '.....2332....',
    '..1..33431.1.',
    '..2.334432.2.',
    '.23333444332.',
    '.33344444433.',
    '2334444444332',
    '3344444444433',
    '3444444444443',
    '3444444444443',
    '.34444444443.',
    '..344444443..',
    '....33333....',
  ],
  cell: 10, gap: 2, radius: 2.6, alphas: [0, 0.3, 0.52, 0.76, 1],
  // Googly eyes glancing up and to the right, and a small grin, on the hottest squares.
  eyes: { y: 108, apart: 19, white: 17, pupil: 8.5, look: [4.5, -3.5], glint: 2.5, ring: 0 },
  mouth: { y: 138, width: 11, depth: 10, stroke: 5.5 },
};

// Below 48 pixels, fewer and larger squares, each still a crisp square at 1x and 2x: one unit
// is one pixel at 19 pixels wide. The face keeps its eyes, ringed so they read on light menus.
const compact = {
  rows: [
    '..3..',
    '.34.2',
    '34443',
    '44444',
    '44444',
    '.444.',
  ],
  cell: 3, gap: 1, radius: 0.7, alphas: [0, 0.45, 0.62, 0.82, 1],
  eyes: { y: 13.5, apart: 3.2, white: 2.9, pupil: 1.5, look: [0.9, -0.9], glint: 0, ring: 0.8 },
  mouth: null,
};

const size = design => {
  const pitch = design.cell + design.gap;
  return [design.rows[0].length * pitch - design.gap, design.rows.length * pitch - design.gap];
};

const hex = channels => `#${channels.map(v => Math.round(v * 255).toString(16).padStart(2, '0')).join('')}`;

/** The squares and face as SVG elements, in the design's own coordinate space. */
function body(design, color, face) {
  const pitch = design.cell + design.gap;
  const [width] = size(design);
  let out = '';
  design.rows.forEach((row, y) => [...row].forEach((level, x) => {
    if (level === '.') return;
    out += `<rect class="sq" data-level="${level}" x="${x * pitch}" y="${y * pitch}" width="${design.cell}" height="${design.cell}" rx="${design.radius}" fill="${color}" fill-opacity="${design.alphas[level]}"/>`;
  }));
  if (!face) return out;
  const { y, apart, white, pupil, look: [dx, dy], glint, ring } = design.eyes;
  const eye = cx => `<circle cx="${cx}" cy="${y}" r="${white}" fill="#fff"${ring ? ` stroke="${color}" stroke-width="${ring}"` : ''}/>`
    + `<g class="pupil"><circle cx="${cx + dx}" cy="${y + dy}" r="${pupil}" fill="#0d1117"/>`
    + (glint ? `<circle cx="${cx + dx * 1.6}" cy="${y + dy * 1.75}" r="${glint}" fill="#fff"/>` : '') + '</g>';
  const middle = width / 2;
  out += `<g class="eyes">${eye(middle - apart)}${eye(middle + apart)}</g>`;
  if (design.mouth) {
    const m = design.mouth;
    out += `<path class="mouth" d="M${middle - m.width} ${m.y} Q${middle} ${m.y + m.depth} ${middle + m.width} ${m.y}" fill="none" stroke="#0d1117" stroke-width="${m.stroke}" stroke-linecap="round"/>`;
  }
  return out;
}

/**
 * The mark as an SVG document, `size` pixels wide. `accent` is an [r, g, b] triple from 0 to 1, or
 * a CSS colour such as `currentColor`. Small sizes use the compact drawing unless `compact` says
 * otherwise. With `tile`, it sits on a rounded square of that colour (the app icon); otherwise the
 * background shows through.
 */
export function markSVG(accent, { size: pixels = 64, face = true, tile = null, compact: small = pixels < 48 } = {}) {
  const color = typeof accent === 'string' ? accent : hex(accent);
  const design = small ? compact : full;
  const [width, height] = size(design);
  if (!tile) {
    const pad = small ? 0 : 2;
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${-pad} ${-pad} ${width + pad * 2} ${height + pad * 2}" width="${pixels}" height="${+(pixels * (height + pad * 2) / (width + pad * 2)).toFixed(2)}" overflow="visible" aria-hidden="true">${body(design, color, face)}</svg>`;
  }
  // App icon: the flame centred on a rounded square, inset so it reads at every size.
  const side = 180, scale = 126 / height, x = (side - width * scale) / 2, y = (side - height * scale) / 2 + 2;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${side} ${side}" width="${pixels}" height="${pixels}" aria-hidden="true">`
    + `<rect width="${side}" height="${side}" rx="40" fill="${tile}"/>`
    + `<g transform="translate(${x.toFixed(2)} ${y.toFixed(2)}) scale(${+scale.toFixed(4)})">${body(design, color, face)}</g></svg>`;
}
