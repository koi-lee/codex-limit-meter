# Codex Meter

A macOS desktop companion and menu bar app for Codex usage and public reset announcements.

[中文](README.md) · [Quota Orbit](https://www.starshoreai.com/quota-orbit/)

## Source release

This repository contains the macOS client, tests and bundled character resources under AGPL-3.0. The website, server, browser extension and developer credentials are excluded. Legacy v1.1.3 and earlier tags retain their MIT license and are no longer maintained.

This release includes source only, with no notarized installer or claim of App Store availability.

## Build locally

Requires macOS 13+, Swift 5.9+ and Xcode Command Line Tools. Validated on Apple Silicon; Intel has not been tested on hardware.

```sh
swift test --disable-sandbox
./build-local.sh
open "dist/Codex Meter Open Source.app"
```

The script creates an ad-hoc signed app with a separate bundle identifier and never installs over your existing app. Use a fresh `CODEX_BUILD_DIR` when rebuilding. Install and sign in to the Codex CLI yourself; the App Store CLI helper is not bundled. Notifications are opt-in.

Credentials and personal usage stay on your Mac. Public reset messages are announcements or third-party transcripts, not confirmation that every account received a reset. Network access and the upstream Codex response determine availability.

## License

Current client project code uses GNU AGPL v3.0; see LICENSE. Earlier MIT grants remain valid; see LICENSE-MIT-legacy. Third-party notices remain applicable. This is an independent project, not an official OpenAI product.
