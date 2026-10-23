# Releasing GitGaze

## Automatic releases

Every push to this repository's `main` runs `Check & Release`:

1. Debug/release Swift tests, release-contract tests, app packaging, and native launch smoke checks run on Apple Silicon and Intel with Swift 6.2.4. A separate `--listener-smoke-test` process exercises the real Git socket listener without starting the dashboard, updater, or Metal rendering (which is unavailable on some hosted Intel runners); it does not change Git configuration.
2. After both succeed, the **same checked-out commit** builds a universal macOS 14+ app.
3. The release version starts at `CFBundleShortVersionString` in `Info.plist`. Later pushes increment the latest reachable stable tag's patch version. To select a higher major/minor version, raise the plist version. A rerun reuses the tag for its commit instead of inventing another version.
4. Both bundled version fields are stamped in the build output; CI never commits generated version changes to `main`.
5. Sparkle generates an Ed25519-signed archive and signed appcast. A separate CryptoKit verifier checks both against the app's embedded public key. Missing/wrong keys fail the release.
6. CI uploads `GitGaze.zip`, `appcast.xml`, and `SHA256SUMS` to a draft release, then publishes it with generated release notes. The tag targets `GITHUB_SHA`, not whichever commit happens to be the current branch head.

Main-branch runs are serialised so a slower old build cannot publish over a newer one. GitHub concurrency can replace intermediate pending runs during a burst of pushes. Pull requests only validate; they cannot read release secrets or publish. Already-published versions are not replaced by reruns; incomplete draft uploads can be retried.

The update feed is the latest release's `appcast.xml`. Archive URLs inside it point to **versioned release assets**, never `latest`, so an update cannot change beneath an in-progress download. Sparkle verifies signatures before extraction, performs replacement/relaunch, and handles permission prompts. The GitHub CLI token is never used for updates.

## Required: Sparkle signing key

The public key in `Info.plist` has a matching private key created in this Mac's login Keychain with Sparkle account **GitGaze**. It is not stored in this repository. Back up the private key securely; losing it can strand existing ad-hoc-signed installations. Do not generate a new key on every CI run.

Configure a GitHub Actions repository secret named **`SPARKLE_PRIVATE_KEY`** with Sparkle's exported base64 private key. Export it locally with the pinned Sparkle tool, transfer it directly to GitHub, and remove the temporary export. Do not paste it into issues, chat, source, or logs:

```sh
swift package resolve
umask 077
KEY_DIR="$(mktemp -d)"
KEY_FILE="$KEY_DIR/sparkle.key"
trap 'rm -f "$KEY_FILE"; rmdir "$KEY_DIR"' EXIT
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account GitGaze -x "$KEY_FILE"
gh secret set SPARKLE_PRIVATE_KEY --repo AlexanderHeffernan/GitGaze < "$KEY_FILE"
```

This command changes the repository's Actions secrets; run it only as an authorised maintainer. Keep a separate secure backup, not a file inside the checkout. Local packaging can use the Keychain directly without exporting anything:

```sh
./scripts/package-release.sh 1.0.0
```

This creates assets under `.build/distribution/` but **does not publish**. `SPARKLE_PRIVATE_KEY` can be supplied as an environment secret in CI; the signing tool receives it through stdin, never a command argument. `scripts/verify-update.swift` needs only the public key and independently rejects tampered archives/feeds and wrong signing keys.

## Optional: Developer ID and notarisation

Sparkle's update signatures and Apple's code signatures solve different problems. The former authenticate updates to an installed app. Developer ID and notarisation provide Apple's first-install/Gatekeeper trust. Without the Apple configuration below, the workflow deliberately publishes **ad-hoc-signed, non-notarised** apps; do not describe those as notarised.

To enable Apple signing, supply these GitHub Actions secrets:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64 export of a Developer ID Application certificate **and private key** in `.p12` form |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password protecting that `.p12` export |
| `APPLE_ID` | Apple Developer account email |
| `APPLE_APP_PASSWORD` | App-specific password for notarisation |
| `APPLE_TEAM_ID` | Apple Developer team ID |

Then set the repository **variable** `MACOS_SIGNING_ENABLED` to `true`. With signing enabled, missing credentials fail closed rather than falling back to ad-hoc signing. CI imports the identity into a temporary keychain, signs Sparkle's nested helpers/framework and the app inside-out with hardened runtime, submits the archive to Apple's notary service, staples the accepted ticket, assesses the app with `spctl`, then recreates/signs the final ZIP and appcast. Temporary Apple credentials are removed in an `always()` cleanup step.

Apple signing requires a real Developer ID certificate; it cannot be manufactured by CI. Verify the notarised distribution on a separate Mac before advertising a frictionless first installation.

## Installation and recovery

- Browser download: unzip `GitGaze.zip`, move the app to Applications, then open it.
- Per-user installer: `install.sh` verifies SHA-256 and bundle signatures before touching an existing app, stages on the destination volume, and restores the previous copy if replacement fails. It does not use sudo, clear quarantine, or delete preferences/history. Its checksum authenticates neither the initial publisher nor a compromised repository; first-install trust depends on HTTPS/the trusted script and, when configured, Apple signing.
- If a release appears between the installer's ZIP and checksum downloads, verification fails safely. Rerun the installer.
- Existing early GitBar/GitGlaze builds need one manual GitGaze installation to gain the updater. Keep the stable bundle identity/data paths. Quit old copies before launching the new name.
- For a faulty release, publish a fixed **higher** version. Do not replace published ZIPs or appcasts or move their tags: clients may already have cached or downloaded them.
- If publishing failed, inspect the failed Actions job and rerun it after fixing credentials/service access. A draft release is not offered to installed users.

## Verification boundaries

`--smoke-test` runs the actual packaged application and dynamically loads its embedded framework, but skips reading credentials/cache, push detection, background network work, and updater startup. It is not a complete installed-update test. Before a public rollout, additionally exercise an older installed build → new release, signature rejection, cancelled download, denied permission, and successful relaunch. Do not treat packaging tests as proof of Apple notarisation or first-install behaviour.
