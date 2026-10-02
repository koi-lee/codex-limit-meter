# Codex Meter

A macOS desktop companion and menu bar app for Codex usage and public reset announcements.

[中文](README.md) · [Quota Orbit](https://www.starshoreai.com/quota-orbit/)

## What does it look like?

A reading companion sits on your Mac desktop. Open its orbit panel to see your remaining Codex quota and when it recovers. This is a standalone macOS app.

### Remaining quota and recovery time

![Desktop companion with remaining quota and recovery time, using sample data](docs/images/desktop-quota.jpg)

Click the character to open the panel and switch between quota, messages and changes. Quota is also available from the menu bar.

### Public reset messages

![Reset message panel and details in demo mode](docs/images/desktop-messages.jpg)

Open message details to follow public reset announcements. Public announcements are separate from your personal quota and do not confirm that your account has received a reset.

### Local quota changes

![Quota history showing two sample changes](docs/images/desktop-changes.jpg)

View quota changes in the current session. Recording starts over when the recovery cycle changes.

> These are real screenshots of the client's demo mode, with Chinese UI. Quota, messages and times are sample data; demo reminders do not send system notifications. To read real quota with the source build, install and sign in to the Codex CLI on your Mac.

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
