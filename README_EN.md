# Quota Orbit — Mac public beta

[Download 1.3.0-beta.1 for Apple silicon](https://github.com/koi-lee/codex-limit-meter/releases/download/v1.3.0-beta.1/Quota-Orbit-1.3.0-beta.1-arm64.dmg) · [中文](README.md)

Requires Apple silicon and macOS 13 or later. The Developer ID signed and Apple-notarized beta is distributed outside the Mac App Store; the App Store edition is not available yet.

Install Codex CLI and sign in with a ChatGPT account before viewing personal quota. This beta does not bundle the CLI helper. Open the DMG, drag Quota Orbit into Applications, then launch it there. Quit an existing copy before replacing it and keep the previous installer for rollback. Enable notifications in the app if desired.

The desktop companion displays personal quota and public reset announcements. An announcement does not guarantee that your account has received a reset. Beta software may contain issues; include the OS version and a screenshot when reporting a problem, never credentials.

The corresponding AGPL-3.0 source is the `v1.3.0-beta.1` tag. Verify the installer with the Release SHA256SUMS.txt. Server, website, browser extension and developer credentials are not included. Legacy v1.1.3 and earlier tags retain their MIT license and are discontinued.

## Local build

With Xcode Command Line Tools and Swift 5.9+, run `swift test --disable-sandbox` then `./build-local.sh`. This produces an ad-hoc signed local app using a separate bundle ID. Set CODEX_BUILD_DIR to a fresh output path for another build.

`build-release.sh` builds the arm64 distribution app; release signing requires the developer's authorized Developer ID. Signing alone is not notarization. The release process notarizes and staples the app and DMG separately before upload.

See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
