// The Stoke mark: a flame made of contribution squares, with a face. One definition draws the app
// icon, the header, the website and its favicon, tinted with the current palette's accent.

// Each digit is a square's intensity, from 1 (a faint flicker at the tips) to 4 (the hot base),
// like a contribution graph. "." is empty.
const flame = [
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
];
const columns = flame[0].length, rows = flame.length;
// Square opacity per intensity, over whatever sits behind the mark.
const alphas = [0, 0.3, 0.52, 0.76, 1];

const CELL = 10, GAP = 2, PITCH = CELL + GAP;
const WIDTH = columns * PITCH - GAP, HEIGHT = rows * PITCH - GAP;

const hex = channels => `#${channels.map(v => Math.round(v * 255).toString(16).padStart(2, '0')).join('')}`;

/** The squares and face as SVG elements, in a WIDTH × HEIGHT coordinate space. */
function body(accent, face) {
  const color = typeof accent === 'string' ? accent : hex(accent);
  const squares = [];
  flame.forEach((row, y) => [...row].forEach((level, x) => {
    if (level === '.') return;
    squares.push(`<rect x="${x * PITCH}" y="${y * PITCH}" width="${CELL}" height="${CELL}" rx="2.6" fill="${color}" fill-opacity="${alphas[level]}"/>`);
  }));
  if (!face) return squares.join('');
  // Googly eyes glancing up and to the right, and a small grin, on the hottest squares.
  const eye = (cx, cy) => `<circle cx="${cx}" cy="${cy}" r="17" fill="#fff"/><circle cx="${cx + 4.5}" cy="${cy - 3.5}" r="8.5" fill="#0d1117"/><circle cx="${cx + 7.2}" cy="${cy - 6.4}" r="2.5" fill="#fff"/>`;
  const middle = WIDTH / 2, eyes = 9 * PITCH;
  return squares.join('') + eye(middle - 19, eyes) + eye(middle + 19, eyes)
    + `<path d="M${middle - 11} ${eyes + 30} Q${middle} ${eyes + 40} ${middle + 11} ${eyes + 30}" fill="none" stroke="#0d1117" stroke-width="5.5" stroke-linecap="round"/>`;
}

/**
 * The mark as an SVG document. `accent` is an [r, g, b] triple from 0 to 1, or a CSS colour such as
 * `currentColor`. With `tile`, it sits
 * on a rounded square of that colour (the app icon); otherwise the background shows through.
 */
export function markSVG(accent, { size = 64, face = true, tile = null } = {}) {
  if (!tile) {
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="-2 -2 ${WIDTH + 4} ${HEIGHT + 4}" width="${size}" height="${size * (HEIGHT + 4) / (WIDTH + 4)}" aria-hidden="true">${body(accent, face)}</svg>`;
  }
  // App icon: the flame centred on a rounded square, inset so it reads at every size.
  const side = 180, scale = 126 / HEIGHT, x = (side - WIDTH * scale) / 2, y = (side - HEIGHT * scale) / 2 + 2;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${side} ${side}" width="${size}" height="${size}" aria-hidden="true">`
    + `<rect width="${side}" height="${side}" rx="40" fill="${tile}"/>`
    + `<g transform="translate(${x.toFixed(2)} ${y.toFixed(2)}) scale(${scale})">${body(accent, face)}</g></svg>`;
}
