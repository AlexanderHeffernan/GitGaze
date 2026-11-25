// Run against `python3 -m http.server --directory site 8000` (see CONTRIBUTING.md).
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { chromium, webkit, devices } = require('playwright');
const axe = require.resolve('axe-core/axe.min.js');

const url = process.argv[2] || 'http://localhost:8000/';
const readme = readFileSync(join(__dirname, '../README.md'), 'utf8');
const command = readme.match(/^curl -fsSL .*\/install\.sh \| bash$/m)[0];
const archive = readme.match(/https:\/\/[^)]+\/releases\/latest\/download\/GitGaze\.zip/)[0];
const nativeColors = readFileSync(join(__dirname, '../Sources/GitGaze/Components.swift'), 'utf8');
const darkPalettes = [...nativeColors.matchAll(/case \.(\w+): dark \? \(([\d., ]+)\) :/g)];

async function checkCopy(page, action) {
  const copy = page.getByRole('button', { name: 'Copy command' });
  await action(copy);
  await page.getByRole('status').getByText('Command copied.', { exact: true }).waitFor();
}

async function audit(page, label) {
  await page.addScriptTag({ path: axe });
  const violations = await page.evaluate(async () => (await axe.run({
    runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'] },
  })).violations.map(({ id, nodes }) => ({ id, targets: nodes.map(node => node.target) })));
  assert.deepEqual(violations, [], label);
}

async function main() {
  const desktop = await chromium.launch({ executablePath: process.env.CHROME_PATH });
  try {
    const page = await desktop.newPage({ permissions: ['clipboard-read', 'clipboard-write'] });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('response', response => { if (!response.ok()) errors.push(`${response.status()} ${response.url()}`); });
    assert.equal((await page.goto(url)).status(), 200);
    assert.equal(await page.locator('#install-command').textContent(), command);
    assert.equal(await page.getByRole('link', { name: 'Download ZIP' }).getAttribute('href'), archive);
    const menu = page.getByRole('button', { name: /^GitGaze menu/ });
    const popover = page.locator('#popover');
    const grid = page.getByRole('img', { name: 'Sample contribution heatmap, one year' });
    await grid.waitFor();

    for (const width of [320, 390, 540, 541, 768, 780, 781, 1024, 1280, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      const layout = await page.evaluate(() => {
        const bounds = selector => document.querySelector(selector).getBoundingClientRect();
        const copy = bounds('.hero-copy');
        const preview = bounds('.preview');
        return {
          fits: document.documentElement.scrollWidth === innerWidth,
          sideBySide: preview.left >= copy.right && preview.top < copy.bottom,
          stacked: preview.top >= copy.bottom,
          commandFits: document.querySelector('pre').scrollWidth === document.querySelector('pre').clientWidth,
        };
      });
      assert(layout.fits && layout.commandFits && (width <= 780 ? layout.stacked : layout.sideBySide), `${width}px: ${JSON.stringify(layout)}`);
    }
    await audit(page, 'Desktop axe violations');
    await page.keyboard.press('Tab');
    assert.equal(await page.locator(':focus').textContent(), 'Skip to content');
    await page.keyboard.press('Enter');
    assert.equal(await page.locator(':focus').getAttribute('id'), 'main');
    await page.keyboard.press('Tab');
    assert.match(await page.locator(':focus').textContent(), /Install GitGaze/);
    assert.notEqual(await page.locator(':focus').evaluate(el => getComputedStyle(el).outlineStyle), 'none');
    await page.keyboard.press('Enter');
    assert.equal(new URL(page.url()).hash, '#install');
    assert.equal(await page.locator(':focus').getAttribute('id'), 'install');
    await page.keyboard.press('Tab'); // Homebrew link
    await page.keyboard.press('Tab');
    assert.equal(await page.locator(':focus').textContent(), 'Copy command');
    await checkCopy(page, () => page.keyboard.press('Enter'));
    assert.equal(await page.evaluate(() => navigator.clipboard.readText()), command);
    assert.deepEqual(errors, []);
    console.log('Chromium: 10 widths, axe, skip link, visible focus, anchor, and exact keyboard clipboard copy passed');

    await page.reload();
    const violet = page.getByRole('radio', { name: 'Violet' });
    assert(await violet.isChecked());
    await violet.focus();
    assert.equal(await violet.evaluate(input => getComputedStyle(input.parentElement).outlineStyle), 'solid');
    await page.keyboard.press('ArrowRight');
    assert(await page.getByRole('radio', { name: 'Coral' }).isChecked());
    assert.equal(darkPalettes.length, 10);
    assert.equal(await page.getByRole('group', { name: 'Preview palette' }).getByRole('radio').count(), 10);
    for (const [, name, rgb] of darkPalettes) {
      await page.getByRole('radio', { name: name[0].toUpperCase() + name.slice(1), exact: true }).check();
      const expected = `color(srgb ${rgb.split(', ').map(Number).join(' ')})`;
      assert.equal(await grid.locator('[data-level="4"]').first().evaluate(el => getComputedStyle(el).fill), expected);
      assert.equal(await menu.locator('.charge').evaluate(el => getComputedStyle(el, '::after').backgroundColor), expected);
    }
    assert.deepEqual(await popover.boundingBox().then(({ width, height }) => [width, height]), [384, 640]);
    await menu.click();
    assert.equal(await menu.getAttribute('aria-expanded'), 'false');
    assert.equal(await popover.isVisible(), false);
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await menu.press('Enter');
    assert.equal(await popover.evaluate(el => getComputedStyle(el).animationName), 'none');
    await page.getByRole('button', { name: 'Contribution history settings' }).click();
    const before = await grid.locator('rect').count();
    await page.getByRole('radio', { name: '6 months' }).check();
    const shortGrid = page.getByRole('img', { name: 'Sample contribution heatmap, six months' });
    assert((await shortGrid.locator('rect').count()) < before);
    await page.getByRole('radio', { name: 'Year' }).check();
    assert.equal(await grid.locator('rect').count(), before);
    const friend = page.getByRole('button', { name: 'Maya Chen’s full-year contribution graph' });
    await friend.press('Enter');
    assert.equal(await friend.getAttribute('aria-expanded'), 'true');
    assert(await page.getByRole('img', { name: 'Maya Chen’s sample full-year contribution heatmap' }).isVisible());
    assert.equal(await page.getByRole('img', { name: 'Jules Park’s sample full-year contribution heatmap' }).count(), 0);
    await friend.press('Enter');
    assert.equal(await friend.getAttribute('aria-expanded'), 'false');
    await page.keyboard.press('Escape');
    assert.equal(await menu.getAttribute('aria-expanded'), 'false');
    assert(await menu.evaluate(el => document.activeElement === el));
    console.log('Chromium: 10 exact native palette colors, radio focus and arrows, popover, reduced motion, history range and friend graph passed');

    const blocked = await desktop.newPage({ permissions: ['clipboard-read'] });
    await blocked.goto(url);
    await blocked.getByRole('button', { name: 'Copy command' }).click();
    await blocked.getByRole('status').getByText('Couldn’t copy. Select the command and copy it manually.').waitFor();
    const noScript = await desktop.newPage({ javaScriptEnabled: false });
    await noScript.goto(url);
    await noScript.getByRole('link', { name: 'Install GitGaze' }).click();
    assert.equal(new URL(noScript.url()).hash, '#install');
    assert.equal(await noScript.locator('#install-command').textContent(), command);
    assert.equal(await noScript.getByRole('button', { name: 'Copy command' }).count(), 0);
    console.log('Chromium: clipboard denial and no-JavaScript manual install passed');
  } finally {
    await desktop.close();
  }

  const mobile = await webkit.launch();
  try {
    const page = await mobile.newPage(devices['iPhone 14']);
    await page.goto(url);
    assert(await page.evaluate(() => matchMedia('(pointer: coarse)').matches && document.documentElement.scrollWidth === innerWidth));
    await audit(page, 'Mobile axe violations');
    assert(await page.locator('.friend').last().evaluate(row => row.getBoundingClientRect().bottom <= row.closest('.app-body').getBoundingClientRect().bottom));
    const menu = page.getByRole('button', { name: /^GitGaze menu/ });
    await menu.tap();
    assert.equal(await menu.getAttribute('aria-expanded'), 'false');
    await menu.tap();
    await page.getByRole('radio', { name: 'Mint' }).tap();
    assert(await page.getByRole('radio', { name: 'Mint' }).isChecked());
    assert.equal(await page.locator('.streak-bars i').first().evaluate(el => getComputedStyle(el).backgroundColor), 'color(srgb 0.46 0.86 0.73)');
    await page.getByRole('button', { name: 'Contribution history settings' }).tap();
    await page.getByRole('radio', { name: '6 months' }).tap();
    await page.getByRole('img', { name: 'Sample contribution heatmap, six months' }).waitFor();
    await page.getByRole('button', { name: 'Jules Park’s full-year contribution graph' }).tap();
    await page.getByRole('img', { name: 'Jules Park’s sample full-year contribution heatmap' }).waitFor();
    await page.getByRole('link', { name: 'Install GitGaze' }).tap();
    assert.equal(new URL(page.url()).hash, '#install');
    assert(await page.getByRole('radio', { name: 'Mint' }).evaluate(radio => radio.getBoundingClientRect().top >= 0 && radio.getBoundingClientRect().bottom < 110));
    await checkCopy(page, copy => copy.tap());
    console.log('WebKit iPhone 14 emulation: coarse pointer, reflow, axe, sticky palette, popover, range, friend graph, and install copy passed');
  } finally {
    await mobile.close();
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
