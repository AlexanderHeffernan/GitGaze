# GitGaze

[![Check & Release](https://github.com/AlexanderHeffernan/GitGaze/actions/workflows/check.yml/badge.svg)](https://github.com/AlexanderHeffernan/GitGaze/actions/workflows/check.yml)
[![Latest release](https://img.shields.io/github/v/release/AlexanderHeffernan/GitGaze)](https://github.com/AlexanderHeffernan/GitGaze/releases/latest)

**Your GitHub momentum, in your menu bar or system tray.**

GitGaze is a small macOS menu-bar and Windows tray app for keeping your contribution streak alive, chasing your personal bests, and seeing what the people you follow are building. It counts GitHub contributions—not just commits—including private activity available to your account.

One codebase builds both apps: the dashboard is a bundled web UI, and a small [Tauri](https://tauri.app/) shell in Rust provides the tray item, notifications, launch at login, push detection, and signed updates. No subscriptions, analytics, or backend.

## Features

- **Six menu-bar styles.** A record dial, charge capsule, activity waveform, contribution mosaic, faceted prism, or activity ribbon. Each shows today's count, with an optional streak. On Windows the tray shows a compact dial and count.
- **A dashboard you arrange.** Add, remove, and reorder eight widgets: Today, Your streak, Contribution history, Favourite people, Weekly momentum, Personal bests, People you follow, and Year in perspective. Widget settings flip into place.
- **Your people, at a glance.** Order favourites, see their daily/weekly/monthly/yearly contributions, and expand their graphs with a click.
- **Compare your years.** Compare cumulative contributions with a previous year, either to the same calendar date or the full year's total.
- **Celebrations that mean something.** Fireworks, Supernova, and Meteor shower particles form the actual contribution increase. Celebrations happen only after GitHub confirms new activity—not just because a push succeeded.
- **Make it yours.** Ten palettes, custom light/dark accent colours, and automatic, light, or dark appearance. Respects reduced motion.
- **Optional streak reminders, milestone notifications, and launch at login.** No arbitrary daily target.
- **Faster updates after a push.** Optional user-wide Git integration, without choosing folders or adding repository hooks. Cached activity stays available offline.

## Get started

GitGaze reads your [GitHub CLI](https://cli.github.com/) session, so install it and sign in first: `gh auth login --hostname github.com`.

### macOS

Requires **macOS 14+**; release builds are universal (Apple Silicon and Intel). Install GitHub CLI with `brew install gh`, then use the per-user installer, which verifies the release checksum before replacing an existing copy:

```sh
curl -fsSL https://raw.githubusercontent.com/AlexanderHeffernan/GitGaze/main/install.sh | bash
```

Or [download GitGaze.zip](https://github.com/AlexanderHeffernan/GitGaze/releases/latest/download/GitGaze.zip), unzip it, and move **GitGaze.app** into Applications. The installer uses `~/Applications`, requires no administrator access, and does not clear macOS quarantine.

**Apple signing status:** without configured Developer ID credentials, releases are ad-hoc signed and not notarised. macOS may block a browser-downloaded first installation. Use System Settings → Privacy & Security → Open Anyway only if you trust the release, or build from source.

### Windows

Requires **Windows 10 or 11** (x64 or ARM64) and the Edge WebView2 runtime, which Windows 11 includes and the installer fetches if missing. Install GitHub CLI with `winget install GitHub.cli`, then run in PowerShell:

```powershell
irm https://raw.githubusercontent.com/AlexanderHeffernan/GitGaze/main/install.ps1 | iex
```

Or download the installer for [x64](https://github.com/AlexanderHeffernan/GitGaze/releases/latest/download/GitGaze-windows-x64-setup.exe) or [ARM64](https://github.com/AlexanderHeffernan/GitGaze/releases/latest/download/GitGaze-windows-arm64-setup.exe). It installs for the current user without administrator access. GitGaze appears in the notification area; Windows may hide new icons in the overflow until you pin it. The installer isn't code-signed yet, so SmartScreen may ask you to confirm.

### Updates

GitGaze checks for new releases about every six hours. Use **Settings → Updates → Check now**, or right-click the tray item and select **Check for Updates…**. Updates install in place and relaunch only when you agree. Every update is Ed25519-signed and verified against the key built into the app before it installs. Installs of 1.0.x receive this version through their existing Sparkle updater, which keeps their preferences and offline history.

GitGaze reads your existing CLI session automatically. It **does not log you into or out of GitHub CLI**, change your CLI credentials, or store your token. To change accounts, run `gh auth switch` and relaunch GitGaze. The app uses the CLI session's existing permissions; it does not request additional scopes or write to repositories. GitHub Enterprise hosts are not currently supported.

## How contributions are counted

GitHub's GraphQL `contributionCalendar` is the source of truth. GitGaze doesn't sum push events, read local repositories, or scrape profile pages. Private activity is subject to GitHub's visibility and organisation policies; restricted counts are not added to the calendar a second time.

“Today” selects the current local calendar date from GitHub's existing date buckets. Historical contributions are not shifted into your local timezone. **Exact parity with the website is not guaranteed:** authenticated API calendars and web-profile graphs can differ in totals or day assignments. GitGaze preserves the supported API result rather than inventing adjustments. GitHub may also take time to process new contributions.

Streaks and records are calculated from that API calendar:

- An empty today keeps a streak ending yesterday alive; an earlier gap breaks it. GitHub does not supply an official streak field.
- A new record must beat, not tie, the prior best. Records are labelled as partial history until older contribution years have loaded.
- Weeks start Monday. Week/month/year totals use calendar boundaries, not rolling windows. Same-date yearly comparisons align by month/day, including leap years.
- Followed profiles show only the contribution information visible to your session. This is not a feed of repository activity or private code.

Activity refreshes on opening if older than 30 seconds, approximately every five minutes while running, and manually. Full contribution history refreshes on startup and every six hours. API failures retain saved activity instead of replacing it with zeros.

## Automatic push detection

Enable **Settings → General → Detect pushes automatically** to opt in. GitGaze adds a `trace2.eventTarget` value to your **user-wide Git configuration**, pointing to a private Unix datagram socket on macOS or a per-user named pipe on Windows. Git's built-in [Trace2](https://git-scm.com/docs/api-trace2) events let it notice successful `git push` completion across repositories. There are no hooks, folder permissions, root permissions, process polling, or network interception.

A successful push starts an immediate profile refresh and bounded retries over roughly three minutes. Local commits, fetches, and failed pushes don't trigger detection. A successful push to another host, an up-to-date push, or a dry-run push may trigger a harmless refresh; **only a GitHub-confirmed increase celebrates**.

This covers Git processes using your user configuration—not other machines, website changes, clients with independent Git implementations, or configuration overrides. GitHub processing may outlast the retry burst; normal background refresh remains the fallback. The app must be running.

Raw trace events can contain command arguments and local paths. GitGaze processes events in memory, retaining only bounded push session identifiers until completion; it does not save raw traces or repository metadata. The macOS socket directory is owner-only. Existing unrelated tracing targets are never overwritten. Turning detection off removes only this app's exact setting.

### Uninstalling

First disable push detection and launch at login in Settings, then quit GitGaze. On macOS, remove its app bundle; on Windows, uninstall it from Settings → Apps. If needed, remove just its Git integration manually:

```sh
# macOS
git config --global --fixed-value --unset-all trace2.eventTarget \
  "af_unix:dgram:$HOME/Library/Caches/GitBar/push.sock"
# Windows (PowerShell)
git config --global --fixed-value --unset-all trace2.eventTarget "\\.\pipe\gitgaze-push-$env:USERNAME"
```

The `GitBar` paths and `app.gitbar.mac` identifier are intentional: they predate the current name and remain stable so existing preferences, offline history, and Git integration survive upgrades.

## Privacy and local data

Authenticated API requests go directly to `api.github.com`; profile pictures load from GitHub's avatar URLs. Update checks and downloads go to the public GitHub release URLs without your CLI token. There is no analytics, telemetry, advertising, external account system, or app backend.

| Data | macOS | Windows |
| --- | --- | --- |
| GitHub token | Read from `gh auth token --hostname github.com` into memory; never written by GitGaze | Same |
| Contribution and profile cache | `~/Library/Application Support/GitBar/dashboard.json` (owner-only) | `%APPDATA%\GitGaze\dashboard.json` |
| Layout, favourites, and appearance | `~/Library/Application Support/GitBar/preferences.json` | `%APPDATA%\GitGaze\preferences.json` |
| Optional push listener | `~/Library/Caches/GitBar/` socket (owner-only); no trace log | Per-user named pipe; no trace log |

The cache contains contribution counts and profile data, not tokens, source code, or repository names. Notifications and launch at login are opt-in. Streak reminders require notification permission, a recently refreshed empty day, an active streak, and the app running. In-app celebrations are independent of notification permission.

## Development

Requires Node.js 20+, a stable Rust toolchain, and the [Tauri prerequisites](https://tauri.app/start/prerequisites/) for your platform (Xcode Command Line Tools on macOS; WebView2 and the MSVC build tools on Windows).

```sh
npm ci
npm test                 # contribution maths and UI logic
npm run dev              # run the app with live UI reloading
npm run build            # build GitGaze.app or the Windows installer
npm run preview          # the UI in a browser with sample data, at http://localhost:5175
```

`ui/` is the whole interface (plain ES modules, no build step) and `src-tauri/` is the native shell. GitHub Actions tests and builds the universal macOS app and both Windows installers, including launch and real `git push` detection checks on each platform. Successful pushes to `main` then publish a versioned release with signed updates for that exact commit. See [CONTRIBUTING.md](CONTRIBUTING.md) and [release setup](docs/RELEASING.md).

## License

[MIT](LICENSE) © Alexander Heffernan. Not affiliated with GitHub. GitHub is a trademark of its respective owner.
