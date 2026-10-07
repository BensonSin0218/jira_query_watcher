---
name: release-macos
description: Run the complete signed macOS release workflow and publish the current committed version to GitHub Releases.
argument-hint: "[RUN_TESTS=0]"
triggers:
  - user
allowed-tools:
  - read
  - exec
permissions:
  allow:
    - Read(pubspec.yaml)
    - Read(scripts/release_macos.sh)
    - Exec(./scripts/release_macos.sh)
    - Exec(RUN_TESTS=0 ./scripts/release_macos.sh)
---

Run the repository's complete macOS release workflow by executing:

```sh
./scripts/release_macos.sh
```

Use the script from the repository root. The script reads the version and build number from `pubspec.yaml`, requires a clean `main` branch synchronized with `origin/main`, runs the configured tests, builds a universal macOS app, signs Developer ID nested components with Hardened Runtime, submits the app to Apple notarization using the configured Keychain profile, staples the ticket, signs the update archive with Sparkle EdDSA, regenerates `appcast.xml`, commits and pushes the appcast, creates the GitHub Release, and verifies the public download URLs.

Do not run this skill autonomously. It has external side effects: Apple notarization, a git push, and GitHub Release creation. If the script stops, report the exact failing step and do not bypass its preflight checks. Never request or print private keys, app-specific passwords, API keys, or Keychain secrets.

The expected local prerequisites are a valid `Developer ID Application` identity, a configured `notarytool` Keychain profile named `jira-query-watcher-notary`, Sparkle's `ed25519` Keychain signing key, and authenticated GitHub CLI. The script supports environment overrides documented in `scripts/release_macos.sh`, including `FLUTTER_VERSION`, `NOTARY_PROFILE`, `SIGNING_IDENTITY`, `SPARKLE_ACCOUNT`, `REPO_SLUG`, `DOWNLOAD_URL_PREFIX`, and `RUN_TESTS=0` when the user explicitly requests skipping tests.

After successful execution, report the version, GitHub Release URL, archive URL, appcast URL, notarization result, Gatekeeper result, test result, and any generated commit hash.
