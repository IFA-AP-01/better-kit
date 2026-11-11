# Development

## Requirements

- Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Rust (`rustup target add aarch64-apple-darwin`).
- An Apple Developer team. The fan helper is a launchd daemon and only runs when the app and helper are signed by the same team.

## Setup

```bash
cp Config/Environment.example.xcconfig Config/Environment.xcconfig   # fill in the team ID
git clone https://github.com/uvie-project/uvie-rs Vendor/uvie-rs
./scripts/build.sh --install
```

- `scripts/build.sh [Debug|Release] [--install]` regenerates the project, builds into `.build/app` (hidden from Spotlight and Launchpad), and with `--install` replaces `/Applications/BetterKit.app`. The helper must run from `/Applications`, so test fan control and login items from the installed copy.
- `scripts/build-uvie.sh` runs as a pre-build phase and builds `Vendor/lib/libuvie.a` once. Set `FORCE_UVIE=1` to rebuild it.
- `BetterKit.xcodeproj` is generated; edit `project.yml` instead.

## Layout

| Path | Contents |
| --- | --- |
| `App/BetterKitApp.swift` | App entry, `AppDelegate`, windows (main, onboarding). |
| `App/Engine/` | `AppModel` (owns the feature models), `AppSettings` (JSON in UserDefaults `settings.v1`), permissions, login item, shared `EventTap`, Sparkle `UpdateCoordinator`, `WhatsNewTracker`. |
| `App/Features/Scroll/` | `SmoothScroller`: event tap on discrete wheel events, Mos-style buffer consumed exponentially each `CVDisplayLink` frame, with a velocity low-pass for a soft start and an inertial tail. |
| `App/Features/Display/` | `VirtualDisplayManager` (`CGVirtualDisplay` + mirroring for HiDPI), `DDC` (`IOAVService` brightness/contrast), `DisplayInfo`. |
| `App/Features/Vietnamese/` | `VietKeyTap` (keyboard event tap, backspace + Unicode replacement), `UvieEngine` (C API wrapper). |
| `App/Features/Fan/` | `FanModel` (SMC readings, presets, curve), `FanHelperClient` (`SMAppService.daemon` + XPC). |
| `App/Menu/` | `StatusMenuController`: menu-bar item, menu rebuilt on open. |
| `App/Views/` | SwiftUI settings panes, onboarding, grant drag panel. |
| `Helper/` | `BetterKitHelper`, the root daemon that writes SMC fan keys. It restores automatic fans when the app disconnects and then exits. |
| `Shared/` | SMC access, XPC protocol, code-signing requirement, bridging headers, `uvie.h`. |

Events that BetterKit posts carry `eventSourceUserData = 0x4245544B` so its own taps skip them.

## Debugging

```bash
/usr/bin/log stream --predicate 'subsystem == "dev.ifateam.betterkit"' --level debug
```

Use `/usr/bin/log`: in zsh, `log` is a builtin and prints nothing.

- **Accessibility resets**: the grant is tied to the signing identity. Debug and Release both sign with Developer ID so the grant survives switching builds. After any identity change, run `tccutil reset Accessibility dev.ifateam.betterkit` and grant again.
- **Helper still running old code**: the helper exits when the app disconnects and launchd starts the new binary on the next request. To force it, quit BetterKit and run `sudo launchctl bootout system/dev.ifateam.betterkit.helper`.
- **Fan mode on M4**: `F0Md` only accepts manual mode a few seconds after `Ftst=1`; the helper retries for up to 10 s.

## Release

```bash
./scripts/release.sh                 # archive, Developer ID export, notarize + staple app and DMG
./scripts/release.sh --no-notarize   # local test DMG
./scripts/release.sh --sparkle https://updates.example.com/betterkit/releases/
```

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Start `RELEASE_NOTES.md` with `# BetterKit <version>`. The app shows it as What's New after updating.
3. Run `scripts/release.sh`. The DMG goes to `build/release/<version>-<build>/`; the exported app stays in `.build/export/`. Nothing is uploaded.
4. To ship updates, set `BETTERKIT_SU_FEED_URL` and `BETTERKIT_SU_PUBLIC_ED_KEY` (from Sparkle's `generate_keys --account betterkit`), rebuild, run with `--sparkle`, and upload the zip and then `appcast.xml` from `build/sparkle-releases/`.

The notary key (`Config/AuthKey_*.p8`) and `Config/Environment.xcconfig` are gitignored; never commit them.
