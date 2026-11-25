# Contributing to Stoke

Small, private, and motivating is the goal. Bug fixes, accessibility improvements, and focused additions are welcome. Discuss substantial product changes in an issue before building them.

## Project layout

One codebase builds the macOS menu-bar app and the Windows tray app.

- `ui/`: the entire interface and app behaviour, as plain ES modules with no build step. `js/store.js` owns refresh, caching, preferences, reminders, and celebrations; `js/app.js` renders the flyout with [Preact](https://preactjs.com/) and htm (vendored in `ui/vendor/`); `js/status.js` draws the menu-bar label and tray icon; `js/stats.js` is the contribution maths.
- `src-tauri/`: the native shell in Rust. It owns the tray item and flyout window, the GitHub CLI token and GraphQL requests (the token never reaches the UI), storage, launch at login, Git push detection, and the updater.
- `tests/`: Node tests for the contribution maths. `src-tauri` has Rust unit tests for push-event parsing; `scripts/test_release.py` covers release versions and signing.
- `scripts/`: release packaging and signing, and the browser preview server.
- The `app.gitbar.mac` identifier and `GitBar` data/socket paths are deliberate compatibility identifiers; do not casually rename them.

## Before submitting a change

```sh
npm ci
npm test
cargo test --manifest-path src-tauri/Cargo.toml
python3 -m unittest discover -s scripts -p 'test_*.py'
npm run build
```

Keep changes focused and use the shared controls so widgets and Settings stay consistent. Add regression coverage for observable behaviour rather than implementation details. Contribution counts must continue to come from GitHub's API calendar; a successful push is only a refresh hint. Do not add repository write access just to display activity.

For visual changes, check light and dark appearance and states such as empty activity, loading, and reduced motion. `npm run preview` serves the UI with deterministic sample data at <http://localhost:5175/?platform=macos> (or `?platform=windows`), which is quick for layout work; then check the real app with `npm run dev`. Running the built app again while it is open shows the flyout, and `Stoke --celebrate` previews a celebration.

## Marketing site

`site/` is the complete static site; `site/app` links to `ui/`, so the hero demo runs the real app UI with its sample data. There is no build step. To preview it from the checkout:

```sh
python3 -m http.server --directory site 8000
```

Open port 8000 on localhost. In a separate terminal, run the browser checks (Node.js and npm required):

```sh
tools=$(mktemp -d)
npm install --prefix "$tools" playwright@1.58.2 axe-core@4.14.1
"$tools/node_modules/.bin/playwright" install chromium webkit
NODE_PATH="$tools/node_modules" node scripts/check-site.cjs
```

On Linux, add `--with-deps` to the Playwright install command if browser libraries are missing. The check covers responsive reflow, automated accessibility in Chromium and touch-emulated WebKit, the live demo (palettes, popover placement, celebrations, the Windows variant), clipboard copy, and no-JavaScript install instructions.

Merged changes to `main` go live at <https://gitgaze.alexheffernan.dev> within about a minute; see [deploy/site/README.md](deploy/site/README.md).

## Protect private information

- Never commit tokens, signing identities, `.env` files, local caches, or raw Git traces.
- Review screenshots before sharing: graphs, usernames, avatars, and private contribution totals may identify you or people you follow. `npm run dev` uses your real account; the preview uses sample data.
- Use synthetic contribution data in tests. Do not copy an authenticated API response into a fixture without sanitising it.
- Bug reports should include your OS version and Stoke version, reproducible steps, and redacted errors—not credentials or complete personal cache files.
- Report security concerns privately to the repository maintainer rather than disclosing usable credentials or exploits in a public issue.

## Distribution

macOS builds are ad-hoc signed and Windows installers are unsigned, so Gatekeeper and SmartScreen may warn on first install. Successful `main` pushes publish signed updates automatically after CI passes; see [RELEASING.md](docs/RELEASING.md). Never casually replace the update signing key: every existing installation trusts it.
