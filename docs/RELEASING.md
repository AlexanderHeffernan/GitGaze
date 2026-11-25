# Releasing GitGaze

## Automatic releases

Every push to this repository's `main` runs `Check & Release`:

1. On macOS, Windows x64, and Windows ARM64 runners: UI and contribution tests, release-signing tests, and Rust tests run; then the app is built for that platform. Each build runs a launch smoke test and a real `git push` to a local bare repository, which the packaged app's push listener must detect.
2. After all three succeed, one job assembles and signs the release for the **same commit**.
3. The release version starts at `version` in `src-tauri/tauri.conf.json`. Later pushes increment the latest reachable stable tag's patch version. To select a higher major/minor version, raise the config version. A rerun reuses the tag for its commit. CI never commits version changes.
4. `scripts/package-release.sh` produces and verifies:
   - `GitGaze.zip` and a signed `appcast.xml`: the Sparkle feed that existing 1.0.x installs already watch. Sparkle's own `generate_appcast` signs both, and an independent check verifies the archive signature against the app's public key.
   - `GitGaze.app.tar.gz` and `GitGaze-windows-{x64,arm64}-setup.exe`, listed in `latest.json` with signatures for GitGaze's built-in updater.
   - `SHA256SUMS` for the installers.
5. CI uploads everything to a draft release with generated notes, then publishes it.

Main-branch runs are serialised so a slower old build cannot publish over a newer one. Pull requests only validate; they cannot read release secrets or publish. Published versions are never replaced; incomplete drafts can be retried.

Both feeds are read from the latest release (`releases/latest/download/…`). Archive URLs inside them point to **versioned** release assets, so an update cannot change beneath an in-progress download.

## One signing key: `SPARKLE_PRIVATE_KEY`

GitGaze has always trusted one Ed25519 public key (`SUPublicEDKey`, kept in `src-tauri/Info.plist`). The same key now signs every update path:

- Sparkle (1.0.x installs) verifies `GitGaze.zip` and the appcast with it directly.
- The built-in updater (1.1 and later) verifies minisign-format signatures. `scripts/sign_update.py` produces them from the same key, and `tauri.conf.json`'s updater `pubkey` is derived from `SUPublicEDKey` (`python3 scripts/sign_update.py pubkey`). Signatures record the version, and the app rejects a signature whose version doesn't match the update.

The private key is the GitHub Actions secret **`SPARKLE_PRIVATE_KEY`** (Sparkle's exported base64 key). The signer refuses to run if it doesn't match the public key. It is never printed or written to disk. Back the key up securely: losing it strands every existing installation. Do not generate a new key.

## Platform signing

macOS releases are ad-hoc signed and not notarised; Windows installers are not Authenticode-signed. The update signature above authenticates updates either way, but first installs may show Gatekeeper or SmartScreen warnings. Adding Developer ID notarisation or a Windows code-signing certificate later only needs the corresponding Tauri environment variables in the build job.

## Installation and recovery

- macOS: `install.sh` verifies SHA-256 and the bundle signature before touching an existing app, stages on the destination volume, and restores the previous copy if replacement fails. It does not use sudo, clear quarantine, or delete preferences/history.
- Windows: `install.ps1` downloads the installer for the machine's architecture, checks it against `SHA256SUMS`, and installs silently for the current user.
- For a faulty release, publish a fixed **higher** version. Do not replace published assets or move tags: clients may already have cached or downloaded them.
- If publishing failed, inspect the failed Actions job and rerun it after fixing the cause. A draft release is not offered to installed users.
