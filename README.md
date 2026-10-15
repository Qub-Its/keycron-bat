# keycron-bat

Menu bar app for macOS that shows the **battery level of a Keychron K3** (and other Bluetooth keyboards that report HID Battery Strength) — something macOS does not display natively for these keyboards.

```
⌨ 36%
```

## Why

The Keychron K3 connects over **Bluetooth Classic** (HID, not BLE), so it has no GATT Battery Service and macOS never shows its battery in Control Center or `ioreg`. The keyboard does, however, expose a standard HID *Battery Strength* element (Usage Page `0x06`, Usage `0x20`) in input report ID 3. keycron-bat reads that report directly through IOKit.

## Features

- Keyboard icon + battery % in the menu bar (`—` when disconnected, `!` when permission is missing)
- Refreshes every 5 minutes, on connect/disconnect, and on demand
- Notification when battery drops below 20% (once per discharge; re-arms at 25%)
- Open at Login toggle
- Report an Issue… menu item (opens a prefilled GitHub issue)
- No Dock icon, no dependencies

## Requirements

- macOS 14 Sonoma or later
- Swift 5.10+ toolchain (Xcode or Command Line Tools)
- **Input Monitoring** permission (required by macOS to open a keyboard HID device)

## Build & install

```bash
scripts/build-app.sh            # builds build/KeycronBat.app
cp -R build/KeycronBat.app /Applications/
open /Applications/KeycronBat.app
```

On first launch the menu shows **Grant Input Monitoring…** — enable *KeycronBat* in System Settings → Privacy & Security → Input Monitoring, then quit and reopen the app.

### Code signing

macOS ties the Input Monitoring grant to the app's signature. The build script signs with, in order:

1. `SIGN_IDENTITY` if set (e.g. `SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh`)
2. the first **Apple Development** certificate in your keychain (free with any Apple ID via Xcode → Settings → Accounts)
3. ad-hoc (`-`) as a fallback

With a certificate, the permission survives rebuilds. With ad-hoc signing every build looks like a new app: if the menu shows `!` even though KeycronBat is enabled in Input Monitoring, run `tccutil reset ListenEvent dev.qubits.keycronbat` and grant it again.

## Development

```bash
swift test      # unit tests (report parsing, IOReturn mapping, low-battery policy)
swift run       # run without a bundle (notifications / login item disabled)
```

Layout:

| Path | Purpose |
|---|---|
| `Sources/KeycronBatCore/` | Pure logic + the IOKit `BatteryReader` |
| `Sources/KeycronBat/` | SwiftUI `MenuBarExtra` app |
| `Resources/Info.plist` | Bundle metadata (`LSUIElement`) |
| `scripts/build-app.sh` | Release build → `.app` bundle |
| `docs/superpowers/` | Design spec and implementation plan |

## Compatibility

Tested with Keychron K3 (firmware 1.0.6, Bluetooth). Any keyboard that exposes HID Usage `0x06/0x20` as an input report should work.

## License

MIT
