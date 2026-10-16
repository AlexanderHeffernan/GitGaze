# GitGlaze

**Your GitHub momentum, in your Mac's menu bar.**

GitGlaze is a native macOS app for keeping your contribution streak alive, chasing your personal bests, and seeing what the people you follow are building. It counts GitHub contributions—not just commits—including private activity available to your account.

Built with SwiftUI and AppKit. No subscriptions, analytics, backend, or package dependencies.

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

Currently distributed as source. Requires **macOS 14+**, **Xcode 16+ with Swift 6 selected**, and [GitHub CLI](https://cli.github.com/) installed through Homebrew.

```sh
brew install gh
gh auth login --hostname github.com
swift test
./scripts/build.sh --install
open "$HOME/Applications/GitGlaze.app"
```

Run the commands from this checkout. The build script creates `.build/GitGlaze.app`, ad-hoc signs it, and installs it in `~/Applications` when passed `--install`. Run the app bundle rather than `swift run`: notifications and login items depend on the bundle identity. Open `Package.swift` in Xcode for development.

GitGlaze reads your existing CLI session automatically. It **does not log you into or out of GitHub CLI**, change your CLI credentials, or store your token. To change accounts, run `gh auth switch` and relaunch GitGlaze. The app uses the CLI session's existing permissions; it does not request additional scopes or write to repositories. GitHub Enterprise hosts are not currently supported.

Builds are not Developer ID-signed or notarised. Distributing a downloadable app requires your own signing identity, Apple notarisation, and testing on a separate Mac; the build script supports `CODESIGN_IDENTITY`. There is no automatic release or deployment workflow.

## How contributions are counted

GitHub's GraphQL `contributionCalendar` is the source of truth. GitGlaze doesn't sum push events, read local repositories, or scrape profile pages. Private activity is subject to GitHub's visibility and organisation policies; restricted counts are not added to the calendar a second time.

“Today” selects the current Mac calendar date from GitHub's existing date buckets. Historical contributions are not shifted into your local timezone. **Exact parity with the website is not guaranteed:** authenticated API calendars and web-profile graphs can differ in totals or day assignments. GitGlaze preserves the supported API result rather than inventing adjustments. GitHub may also take time to process new contributions.

Streaks and records are calculated from that API calendar:

- An empty today keeps a streak ending yesterday alive; an earlier gap breaks it. GitHub does not supply an official streak field.
- A new record must beat, not tie, the prior best. Records are labelled as partial history until older contribution years have loaded.
- Weeks start Monday. Week/month/year totals use calendar boundaries, not rolling windows. Same-date yearly comparisons align by month/day, including leap years.
- Followed profiles show only the contribution information visible to your session. This is not a feed of repository activity or private code.

Activity refreshes on opening if older than 30 seconds, approximately every five minutes while running, and manually. Full contribution history refreshes on startup and every six hours. API failures retain saved activity instead of replacing it with zeros.

## Automatic push detection

Enable **Settings → General → Detect pushes automatically** to opt in. GitGlaze adds a `trace2.eventTarget` value to your **user-wide Git configuration**, pointing to a private Unix datagram socket. Git's built-in [Trace2](https://git-scm.com/docs/api-trace2) events let it notice successful `git push` completion across repositories. There are no hooks, folder permissions, root permissions, process polling, or network interception.

A successful push starts an immediate profile refresh and bounded retries over roughly three minutes. Local commits, fetches, and failed pushes don't trigger detection. A successful push to another host, an up-to-date push, or a dry-run push may trigger a harmless refresh; **only a GitHub-confirmed increase celebrates**.

This covers Git processes using your user configuration—not other machines, website changes, clients with independent Git implementations, or configuration overrides. GitHub processing may outlast the retry burst; normal background refresh remains the fallback. The app must be running.

Raw trace events can contain command arguments and local paths. GitGlaze processes events in memory, retaining only bounded push session identifiers until completion; it does not save raw traces or repository metadata. The socket directory is owner-only. Existing unrelated tracing targets are never overwritten. Turning detection off removes only this app's exact setting.

### Uninstalling

First disable push detection and launch at login in Settings, then quit GitGlaze and remove `~/Applications/GitGlaze.app`. If needed, remove just its Git integration manually:

```sh
git config --global --fixed-value --unset-all trace2.eventTarget \
  "af_unix:dgram:$HOME/Library/Caches/GitBar/push.sock"
```

The `GitBar` path is intentional: it and the bundle identifier predate the GitGlaze name and remain stable so existing preferences, offline history, and Git integration survive upgrades. If updating from an early GitBar build, quit that app before launching GitGlaze; do not run both together.

## Privacy and local data

Authenticated API requests go directly to `api.github.com`; profile pictures load from GitHub's avatar URLs. There is no analytics, telemetry, advertising, external account system, or app backend.

| Data | Location / handling |
| --- | --- |
| GitHub token | Read from `gh auth token --hostname github.com`; kept in memory, never cached by GitGlaze |
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

GitHub Actions runs debug/release tests and builds the app on macOS. No credentials are needed for these checks. See [CONTRIBUTING.md](CONTRIBUTING.md) for the module layout, native UI review workflow, and privacy precautions.

## License

[MIT](LICENSE) © Alexander Heffernan. Not affiliated with GitHub. GitHub is a trademark of its respective owner.
