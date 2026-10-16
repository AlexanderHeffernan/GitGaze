# Contributing to GitGlaze

Small, native, private, and motivating is the goal. Bug fixes, accessibility improvements, and focused additions are welcome. Discuss substantial product changes in an issue before building them.

## Project layout

- `Sources/GitGlaze/`: AppKit menu-bar lifecycle, SwiftUI components and widgets, preferences, CLI authentication, and local push detection.
- `Sources/GitGlazeCore/`: contribution calculations, GitHub GraphQL reads, and Trace2 push-event parsing.
- `Tests/GitGlazeCoreTests/`: public-behaviour tests for calendars, streaks, records, yearly comparisons, celebrations, and push events.
- `scripts/`: app packaging, generated icon, and debug-only native UI review.
- `Info.plist`: app metadata. The legacy `app.gitbar.mac` identity and `GitBar` data/socket paths are deliberate compatibility identifiers; do not casually rename them.

Use Xcode 16+ with Swift 6 selected on macOS 14+. There are no third-party package dependencies.

## Before submitting a change

```sh
swift test
swift test -c release
./scripts/build.sh
```

Keep changes focused and use shared controls so widgets and Settings stay consistent. Add regression coverage for observable behaviour rather than implementation details. Contribution counts must continue to come from GitHub's API calendar; a successful push is only a refresh hint. Do not add repository write access just to display activity.

For visual changes, inspect the native rendered UI in light and dark appearance, and relevant states such as empty activity, loading, and Reduce Motion. The debug review workflow can help:

```sh
./scripts/review.sh
```

**This is a local, interactive review—not a headless CI test.** It requires an authenticated GitHub CLI session, a graphical macOS session, and Screen Recording permission for the invoking terminal. It restarts the app, renders real signed-in contribution data, briefly changes and restores preferences, captures widget and celebration animations, and checks popover reset and preference persistence. If push detection is already enabled, it also disables/re-enables that integration and tests local pushes to two disposable repositories. It does not enable push detection for the first time or push anything to GitHub. `ffmpeg` is optional for converting frame captures to videos/GIFs.

Artifacts and temporary frame captures go under `.amp/in/`, which is ignored. The review renderer is excluded from release builds. Do not run it during other app use; if interrupted, review your preferences before continuing.

## Protect private information

- Never commit tokens, signing identities, `.env` files, local caches, or raw Git traces.
- Review screenshots before sharing: graphs, usernames, avatars, and private contribution totals may identify you or people you follow. The review script uses your real account, not anonymised demo data.
- Use synthetic contribution data in tests. Do not copy an authenticated API response into a fixture without sanitising it.
- Bug reports should include macOS/Xcode versions, reproducible steps, and redacted errors—not credentials or complete personal cache files.
- Report security concerns privately to the repository maintainer rather than disclosing usable credentials or exploits in a public issue.

## Distribution

The default build is ad-hoc signed for local development. Building successfully is not proof that a downloadable app will pass Gatekeeper. A release needs Developer ID signing, notarisation, and first-run checks on another Mac, including CLI connection, optional login items, and notification permission. CI does not publish releases.
