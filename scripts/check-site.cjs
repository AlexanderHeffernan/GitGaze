// Run against `python3 -m http.server --directory site 8000` (see CONTRIBUTING.md).
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { chromium, webkit, devices } = require('playwright');
const axe = require.resolve('axe-core/axe.min.js');

const url = process.argv[2] || 'http://localhost:8000/';
const readme = readFileSync(join(__dirname, '../README.md'), 'utf8');
const commands = {
  macos: readme.match(/^curl -fsSL .*\/install\.sh \| bash$/m)[0],
  windows: readme.match(/^irm .*\/install\.ps1 \| iex$/m)[0],
};

async function audit(page, label) {
  await page.addScriptTag({ path: axe });
  const { version, violations } = await page.evaluate(async () => {
    const { violations } = await axe.run({ runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'] } });
    return { version: axe.version, violations: violations.map(({ id, nodes }) => ({ id, targets: nodes.map(node => node.target) })) };
  });
  assert.deepEqual(violations, [], `${label} (axe ${version})`);
}

/** Resolves once the embedded app has started and drawn its menu-bar label or tray icon. */
const appReady = page => page.waitForFunction(() => {
  const store = document.querySelector('#popover').contentWindow.gitgaze;
  const canvas = document.querySelector(document.querySelector('#stage').dataset.platform === 'macos' ? '#menu-label' : '#tray-icon');
  return store?.stats && canvas.width > 0;
});

async function main() {
  const desktop = await chromium.launch({ executablePath: process.env.CHROME_PATH });
  try {
    const page = await desktop.newPage({ permissions: ['clipboard-read', 'clipboard-write'], userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/537.36 Chrome/140 Safari/537.36' });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('response', response => { if (!response.ok()) errors.push(`${response.status()} ${response.url()}`); });
    assert.equal((await page.goto(url)).status(), 200);
    for (const [platform, command] of Object.entries(commands)) assert.equal(await page.locator(`#cmd-${platform}`).textContent(), command);
    await appReady(page);

    for (const width of [320, 390, 768, 980, 981, 1280, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      await page.evaluate(() => new Promise(resolve => requestAnimationFrame(resolve))); // Let the demo refit.
      const fits = await page.evaluate(() => document.documentElement.scrollWidth === innerWidth);
      assert(fits, `${width}px overflows horizontally`);
    }
    await audit(page, 'Desktop axe violations');

    // Palettes change the real app's preferences and the page accent together.
    await page.getByRole('radio', { name: 'Mint' }).click();
    assert.equal(await page.evaluate(() => document.querySelector('#popover').contentWindow.gitgaze.prefs.palette), 'mint');
    assert.equal(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--accent-rgb').trim()), '117 219 186');
    // ...and so does choosing a palette inside the app's own Settings.
    await page.evaluate(() => document.querySelector('#popover').contentWindow.gitgaze.set({ palette: 'coral' }));
    await page.waitForFunction(() => document.querySelector('[data-palette="coral"]').getAttribute('aria-checked') === 'true');

    // The popover hangs from the menu-bar item, and celebrations reach the overlay.
    const arrow = await page.evaluate(() => {
      const item = document.querySelector('#menu-item').getBoundingClientRect();
      const frame = document.querySelector('#popover').getBoundingClientRect();
      return Math.abs(item.left + item.width / 2 - frame.left - parseFloat(document.querySelector('#popover').contentDocument.documentElement.style.getPropertyValue('--arrow-x')));
    });
    assert(arrow < 1, `arrow is ${arrow}px off the menu-bar item`);
    await page.getByRole('button', { name: 'Play a celebration' }).click();
    await page.waitForFunction(() => !document.querySelector('#burst').contentDocument.querySelector('canvas').hidden && document.querySelector('#burst').contentDocument.querySelector('canvas').width > 0);

    await page.getByRole('radio', { name: 'Windows' }).first().click();
    await appReady(page);
    assert.equal(await page.evaluate(() => document.querySelector('#popover').contentWindow.gitgaze.platform), 'windows');
    assert(await page.locator('.taskbar').isVisible());

    await page.getByRole('radio', { name: 'Windows' }).last().click();
    await page.getByRole('button', { name: 'Copy Windows install command' }).click();
    assert.equal(await page.evaluate(() => navigator.clipboard.readText()), commands.windows);
    assert.deepEqual(errors, []);
    console.log('Chromium: reflow, axe, live app palettes, popover placement, celebration, Windows demo and copy passed');

    const noScript = await desktop.newPage({ javaScriptEnabled: false });
    await noScript.goto(url);
    assert.equal(await noScript.locator('#cmd-macos').isVisible(), true);
    console.log('Chromium: no-JavaScript install instructions passed');
  } finally {
    await desktop.close();
  }

  const mobile = await webkit.launch();
  try {
    const page = await mobile.newPage(devices['iPhone 14']);
    await page.goto(url);
    await appReady(page);
    assert(await page.evaluate(() => document.documentElement.scrollWidth === innerWidth));
    const frame = await page.locator('#popover').boundingBox();
    assert(frame.x >= 0 && frame.x + frame.width <= 390, `popover is outside the screen: ${JSON.stringify(frame)}`);
    await audit(page, 'Mobile axe violations');
    console.log('WebKit iPhone 14 emulation: reflow, scaled demo and axe passed');
  } finally {
    await mobile.close();
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
