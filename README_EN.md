# Codex Limit Meter

[中文](README.md) | [English](README_EN.md)

> A floating macOS widget that monitors the Codex rate-limit windows currently available to your account.

Codex Limit Meter reads official quota data from the local Codex App Server and displays it in a compact desktop window. It supports dragging, color warnings, plan labels, and Chinese/English switching.

The app identifies short-term and weekly limits by their actual window duration instead of relying on their field order. If Codex temporarily removes a limit, that row is hidden automatically. When the limit returns, the row appears again without requiring an app update or configuration change.

![Codex Limit Meter](docs/screenshot.png)

Weekly limit only:

![Codex Limit Meter showing only the weekly limit](docs/screenshot-weekly-only.png)

## Requirements

- macOS 13.0 or later
- Codex CLI installed and available through the `codex` command
- Signed in to Codex with a ChatGPT account rather than API-key-only authentication

## Installation

### Option 1: Install from DMG

1. Download `CodexLimitMeter.dmg` from [Releases](../../releases).
2. Open the DMG and drag `CodexLimitMeter` into the Applications folder.
3. Open Finder → Applications and launch `CodexLimitMeter.app`.
4. If macOS blocks the app because the developer cannot be verified, choose one of these options:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/CodexLimitMeter.app"
   ```

   Or open **System Settings → Privacy & Security** and select **Open Anyway**.

Only remove the quarantine attribute when you downloaded the app from a source you trust.

### Option 2: Build from source

```bash
git clone https://github.com/koi-lee/codex-limit-meter.git
cd codex-limit-meter
chmod +x build.sh
./build.sh
open dist/CodexLimitMeter.app
```

To create a distributable DMG:

```bash
./build.sh --dmg
```

## Usage

After launch:

1. The app appears in the Dock and menu bar.
2. A floating quota window appears on the desktop and can be dragged anywhere.
3. The app connects to the Codex App Server and loads quota data within a few seconds.
4. `Synced` at the bottom indicates that live data was received successfully.

| Action | Description |
|---|---|
| Drag the window | Drag the dark background to move the widget |
| Refresh button | Refresh quota data immediately |
| Menu bar icon | Show the window, refresh data, change language, or quit |
| Language | Menu bar icon → Switch to English / Switch to 中文 |
| `⌘Q` | Quit the app |

Progress colors are based on the remaining quota: green above 40%, orange from 20% to 40%, and red below 20%.

## How it works

Codex Limit Meter starts the local `codex app-server` process and communicates with it over JSON-RPC:

- `account/rateLimits/read` loads the current quota snapshot.
- `account/rateLimits/updated` receives live, partial updates.
- Partial updates are merged into the latest complete snapshot.
- Windows are classified using `windowDurationMins`, so a weekly-only response is never displayed as a 168-hour short-term limit.

The App Server process is terminated automatically when Codex Limit Meter exits.

## FAQ

### Why is the five-hour limit missing?

Codex did not return a five-hour quota window for the current account. For example, OpenAI may temporarily remove that restriction for some plans. The app only displays limits that currently exist. If the five-hour window returns, its row appears automatically.

### Why does the widget say “Update failed”?

Check that:

1. The `codex` command is available.
2. Codex is signed in.
3. You are using ChatGPT-managed authentication rather than API-key-only authentication.

### Why does macOS say the developer cannot be verified?

Current releases use ad-hoc signing and are not distributed through the Mac App Store. Install the app only from a source you trust, then use the quarantine command or **Open Anyway** procedure described above.

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for implementation details and contribution guidance.
