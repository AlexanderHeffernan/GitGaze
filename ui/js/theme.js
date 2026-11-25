// Palettes and the few fixed colours, each with a light and dark value.

export const palettes = {
  violet: [[0.43, 0.29, 0.79], [0.69, 0.61, 1]],
  coral: [[0.77, 0.25, 0.21], [1, 0.57, 0.49]],
  ice: [[0.06, 0.43, 0.64], [0.42, 0.81, 0.97]],
  graphite: [[0.29, 0.33, 0.42], [0.83, 0.85, 0.91]],
  mint: [[0.08, 0.47, 0.36], [0.46, 0.86, 0.73]],
  rose: [[0.75, 0.19, 0.43], [1, 0.56, 0.74]],
  amber: [[0.64, 0.36, 0.03], [1, 0.75, 0.35]],
  cobalt: [[0.18, 0.36, 0.83], [0.46, 0.63, 1]],
  orchid: [[0.59, 0.23, 0.75], [0.86, 0.56, 1]],
  lagoon: [[0.04, 0.45, 0.48], [0.3, 0.85, 0.86]],
};

export const title = name => name[0].toUpperCase() + name.slice(1);

/** `#RRGGBB`/`RRGGBB` to [r, g, b] fractions, or null when invalid. */
export function parseHex(hex) {
  const value = String(hex ?? '').replace(/[#\s]/g, '');
  if (!/^[0-9a-f]{6}$/i.test(value)) return null;
  return [0, 2, 4].map(i => parseInt(value.slice(i, i + 2), 16) / 255);
}

const css = ([r, g, b], alpha = 1) =>
  alpha === 1 ? `rgb(${Math.round(r * 255)} ${Math.round(g * 255)} ${Math.round(b * 255)})`
    : `rgb(${Math.round(r * 255)} ${Math.round(g * 255)} ${Math.round(b * 255)} / ${alpha})`;

export function accentRGB(prefs, dark) {
  if (prefs.palette === 'custom') return parseHex(dark ? prefs.customDark : prefs.customLight) ?? [0.69, 0.32, 0.87];
  return (palettes[prefs.palette] ?? palettes.violet)[dark ? 1 : 0];
}

export const accent = (prefs, dark, alpha) => css(accentRGB(prefs, dark), alpha);
export const gold = (dark, alpha) => css(dark ? [1, 0.78, 0.44] : [0.65, 0.36, 0.08], alpha);
export const background = dark => css(dark ? [0.085, 0.087, 0.11] : [0.975, 0.973, 0.986]);
/** The system label colour: near-black or near-white. */
export const primary = (dark, alpha = 0.85) => (dark ? `rgb(255 255 255 / ${alpha})` : `rgb(0 0 0 / ${alpha})`);

export const systemDark = () => matchMedia('(prefers-color-scheme: dark)').matches;
export const reduceMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
