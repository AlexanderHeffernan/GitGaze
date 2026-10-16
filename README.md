# GitGaze

[![Check & Release](https://github.com/AlexanderHeffernan/GitGaze/actions/workflows/check.yml/badge.svg)](https://github.com/AlexanderHeffernan/GitGaze/actions/workflows/check.yml)
[![Latest release](https://img.shields.io/github/v/release/AlexanderHeffernan/GitGaze)](https://github.com/AlexanderHeffernan/GitGaze/releases/latest)

**Your GitHub momentum, in your Mac's menu bar.**

GitGaze is a native macOS app for keeping your contribution streak alive, chasing your personal bests, and seeing what the people you follow are building. It counts GitHub contributions—not just commits—including private activity available to your account.

Built with SwiftUI and AppKit, with [Sparkle](https://sparkle-project.org/) for verified in-app updates. No subscriptions, analytics, or backend.

## Features

- **Six menu-bar styles.** A record dial, charge capsule, activity waveform, contribution mosaic, faceted prism, or activity ribbon. Each shows today's count, with an optional streak.
- **A dashboard you arrange.** Add, remove, and reorder eight widgets: Today, Your streak, Contribution history, Favourite people, Weekly momentum, Personal bests, People you follow, and Year in perspective. Widget settings flip into place.
- **Your people, at a glance.** Order favourites, see their daily/weekly/monthly/yearly contributions, and expand their graphs with a click.
- **Compare your years.** Compare cumulative contributions with a previous year, either to the same calendar date or the full year's total.
- **Celebrations that mean something.** Fireworks, Supernova, and Meteor shower particles form the actual contribution increase. Celebrations happen only after GitHub confirms new activity—not just because a push succeeded.
- **Make it yours.** Ten palettes, custom light/dark accent colours, and automatic, light, or dark appearance. Respects Reduce Motion.
- **Optional streak reminders, milestone notifications, and launch at login.** No arbitrary daily target.
- **Faster updates after a push.** Optional user-wide Git integration, without choosing folders or adding repository hooks. Cached activity stays available offline.

## Get started

Requires **macOS 14+** and [GitHub CLI](https://cli.github.com/). Release builds are universal: Apple Silicon and Intel.

1. Install GitHub CLI (`brew install gh`) and sign in with `gh auth login --hostname github.com`.
2. [Download GitGaze.zip](https://github.com/AlexanderHeffernan/GitGaze/releases/latest/download/GitGaze.zip), unzip it, and move **GitGaze.app** into Applications.
3. Open GitGaze. Your active CLI account connects automatically.

Or use the per-user installer, which verifies the release checksum before replacing an existing copy:

```sh
curl -fsSL https://raw.githubusercontent.com/AlexanderHeffernan/GitGaze/main/install.sh | bash
```

The installer uses `~/Applications`, requires no administrator access, and does not clear macOS quarantine. Inspect [install.sh](install.sh) before running if you prefer. Release downloads become available after the first successful automated release.

**Apple signing status:** without configured Developer ID credentials, releases are ad-hoc signed and not notarised. macOS may block a browser-downloaded first installation. Use System Settings → Privacy & Security → Open Anyway only if you trust the release, or build from source. Cryptographic Sparkle update signatures do **not** replace Apple notarisation. See [release setup](docs/RELEASING.md) for the optional Developer ID/notarisation pipeline.

### Updates

GitGaze checks for new releases about every six hours. Use **Settings → Updates → Check now**, or right-click the menu-bar item and select **Check for Updates…**. Sparkle handles downloading, verifying, installing in place, and relaunching; automatic checks can be disabled. Updates are not silently installed by default.

Both the update feed and archive are Ed25519-signed, and archives are verified **before extraction**. No downloaded shell script runs with administrator privileges. Sparkle handles authorisation if a system-wide installation needs it; the per-user installer avoids that requirement. Checksums provide download integrity for the initial installer, while the installed app's embedded public key authenticates subsequent updates.

### Build from source

Requires **Xcode 16+ with Swift 6 selected**. From this checkout:

```sh
brew install gh
gh auth login --hostname github.com
swift test
./scripts/build.sh --install
open "$HOME/Applications/GitGaze.app"
```

The build script creates `.build/GitGaze.app`, ad-hoc signs it, and installs it in `~/Applications` when passed `--install`. Use `--universal` to build both architectures. Run the app bundle rather than `swift run`: notifications and login items depend on the bundle identity. Open `Package.swift` in Xcode for development. Sparkle is pinned in `Package.resolved` and its framework is embedded by the build script.

GitGaze reads your existing CLI session automatically. It **does not log you into or out of GitHub CLI**, change your CLI credentials, or store your token. To change accounts, run `gh auth switch` and relaunch GitGaze. The app uses the CLI session's existing permissions; it does not request additional scopes or write to repositories. GitHub Enterprise hosts are not currently supported.

## How contributions are counted

GitHub's GraphQL `contributionCalendar` is the source of truth. GitGaze doesn't sum push events, read local repositories, or scrape profile pages. Private activity is subject to GitHub's visibility and organisation policies; restricted counts are not added to the calendar a second time.

“Today” selects the current Mac calendar date from GitHub's existing date buckets. Historical contributions are not shifted into your local timezone. **Exact parity with the website is not guaranteed:** authenticated API calendars and web-profile graphs can differ in totals or day assignments. GitGaze preserves the supported API result rather than inventing adjustments. GitHub may also take time to process new contributions.

Streaks and records are calculated from that API calendar:

- An empty today keeps a streak ending yesterday alive; an earlier gap breaks it. GitHub does not supply an official streak field.
- A new record must beat, not tie, the prior best. Records are labelled as partial history until older contribution years have loaded.
- Weeks start Monday. Week/month/year totals use calendar boundaries, not rolling windows. Same-date yearly comparisons align by month/day, including leap years.
- Followed profiles show only the contribution information visible to your session. This is not a feed of repository activity or private code.

Activity refreshes on opening if older than 30 seconds, approximately every five minutes while running, and manually. Full contribution history refreshes on startup and every six hours. API failures retain saved activity instead of replacing it with zeros.

## Automatic push detection

Enable **Settings → General → Detect pushes automatically** to opt in. GitGaze adds a `trace2.eventTarget` value to your **user-wide Git configuration**, pointing to a private Unix datagram socket. Git's built-in [Trace2](https://git-scm.com/docs/api-trace2) events let it notice successful `git push` completion across repositories. There are no hooks, folder permissions, root permissions, process polling, or network interception.

A successful push starts an immediate profile refresh and bounded retries over roughly three minutes. Local commits, fetches, and failed pushes don't trigger detection. A successful push to another host, an up-to-date push, or a dry-run push may trigger a harmless refresh; **only a GitHub-confirmed increase celebrates**.

This covers Git processes using your user configuration—not other machines, website changes, clients with independent Git implementations, or configuration overrides. GitHub processing may outlast the retry burst; normal background refresh remains the fallback. The app must be running.

Raw trace events can contain command arguments and local paths. GitGaze processes events in memory, retaining only bounded push session identifiers until completion; it does not save raw traces or repository metadata. The socket directory is owner-only. Existing unrelated tracing targets are never overwritten. Turning detection off removes only this app's exact setting.

### Uninstalling

First disable push detection and launch at login in Settings, then quit GitGaze and remove its app bundle. If needed, remove just its Git integration manually:

```sh
git config --global --fixed-value --unset-all trace2.eventTarget \
  "af_unix:dgram:$HOME/Library/Caches/GitBar/push.sock"
```

The `GitBar` path is intentional: it and the bundle identifier predate the current name and remain stable so existing preferences, offline history, and Git integration survive upgrades. If updating from an early GitBar/GitGlaze build, quit that app before launching GitGaze; do not run both together. Early builds without Sparkle need one manual installation; later releases update in place.

## Privacy and local data

Authenticated API requests go directly to `api.github.com`; profile pictures load from GitHub's avatar URLs. Update checks and downloads go to the public GitHub release URLs without your CLI token. Sparkle system profiling is disabled. There is no analytics, telemetry, advertising, external account system, or app backend.

| Data | Location / handling |
| --- | --- |
| GitHub token | Read from `gh auth token --hostname github.com`; kept in memory, never cached by GitGaze |
| Contribution and profile cache | `~/Library/Application Support/GitBar/dashboard.json`, owner-only file permissions |
| Layout, favourites, and appearance | Local preferences under `app.gitbar.mac` |
| Optional push listener | `~/Library/Caches/GitBar/`, owner-only directory and socket; no trace log |

The cache contains contribution counts and profile data, not tokens, source code, or repository names. Early-build Keychain entries, if any, are not used or deleted. Notifications and launch at login are opt-in. Streak reminders require notification permission, a recently refreshed empty day, an active streak, and the app running; they do not wake your Mac. In-app celebrations are independent of notification permission.

## Development

```sh
swift test
swift test -c release
./scripts/build.sh
CONFIGURATION=debug ./scripts/build.sh
```

GitHub Actions runs debug/release tests, release-contract tests, packaging, and launch checks on Apple Silicon and Intel. Successful pushes to `main` then produce a versioned universal app, signed appcast, checksums, and generated release notes for that exact commit. Publishing is restricted to this repository's `main`, never pull requests. See [CONTRIBUTING.md](CONTRIBUTING.md) and [release setup](docs/RELEASING.md).

## License

[MIT](LICENSE) © Alexander Heffernan. Not affiliated with GitHub. GitHub is a trademark of its respective owner.
