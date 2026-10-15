# keycron-bat — Design

Date: 2026-10-15
Status: Approved (conversation), pending written-spec review

## Goal

Personal macOS menu bar app that shows the battery level of a Keychron K3
keyboard connected over Bluetooth, and warns when it gets low. macOS does not
show this natively for the K3.

## Background (verified)

- K3 connects via Bluetooth Classic (HID ACL), not BLE: no GATT Battery
  Service, no `BatteryPercent` in `ioreg`.
- Identifies as VID `0x05AC`, PID `0x024F`, firmware 1.0.6.
- HID report descriptor declares Usage Page `0x06` (Generic Device Controls),
  Usage `0x20` (Battery Strength), Input, Report ID 3, 8 bits, 0–100.
- `IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, 3, buf, &len)` returns
  `[0x03, level]`. Observed value 36, user confirmed plausible. Buffer must be
  2 bytes; a larger buffer returns trailing junk (the BT address).
- Report ID `0xFF` (Apple-style battery usages 0x24–0x26) returns
  `0xe00002c7` — not used.
- `IOHIDDeviceOpen` on a keyboard requires the **Input Monitoring** privacy
  permission; without it returns `0xe00002e2` (kIOReturnNotPermitted).

## Scope (v1)

In:
- Menu bar item: keyboard SF Symbol + percentage, e.g. `⌨ 36%`.
- Disconnected / unreadable: grey keyboard symbol + `—`.
- Polling every 5 minutes, plus immediately on device connect and on "Refresh".
- Local notification when level drops below 20% (fixed threshold).
- Menu: current level line, "Refresh", "Open at Login" toggle, "Quit".
- Missing permission: menu shows "Grant Input Monitoring…" which opens
  System Settings → Privacy & Security → Input Monitoring.
- No Dock icon (`LSUIElement = true`).

Out (YAGNI): configurable threshold, widgets, multiple keyboards UI, history,
charging detection, notarization/distribution.

## Approach

Polling via `IOHIDManager` (chosen over input-report callback, whose emission
by the firmware is unverified). Device matched by presence of a Battery
Strength element (`0x06/0x20`) on a keyboard device (`0x01/0x06`), not by
product name — works for any keyboard exposing the standard usage.

## Architecture

Swift Package (SwiftPM), macOS 14+, SwiftUI `MenuBarExtra`. Two targets:

- `KeycronBatCore` (library, no UI) — testable logic.
- `KeycronBat` (executable) — SwiftUI app.

### Units

**`BatteryReport` (Core)** — pure parsing.
- `static func parse(_ bytes: [UInt8]) -> Int?`
- Returns `bytes[1]` if `bytes.count >= 2`, `bytes[0] == 3`, and value in
  0...100; else `nil`.

**`BatteryReader` (Core)** — only unit touching IOKit.
- Owns an `IOHIDManager` matching keyboards (`UsagePage 0x01, Usage 0x06`).
- Registers matching/removal callbacks on the main run loop; exposes
  `onDevicesChanged: () -> Void`.
- `func read() -> ReadResult` where
  `enum ReadResult { case level(Int), noDevice, notPermitted, failed }`.
- `read()` picks the first device with a `0x06/0x20` input element, opens it,
  calls `IOHIDDeviceGetReport` with that element's report ID and a 2-byte
  buffer, passes bytes to `BatteryReport.parse`.
- `kIOReturnNotPermitted` from open/get → `.notPermitted`.

**`LowBatteryPolicy` (Core)** — pure threshold/hysteresis state.
- `threshold = 20`, `rearm = 25`.
- `mutating func update(level: Int) -> Bool` returns `true` exactly once when
  level goes below threshold; re-arms only after level ≥ rearm.

**`BatteryMonitor` (App)** — `@MainActor ObservableObject`.
- Published: `state: State` where
  `enum State { case level(Int), disconnected, needsPermission }`.
- Timer every 300 s, `refresh()` also called on `onDevicesChanged` and from
  the menu. Maps `ReadResult` → `State` (`.failed`/`.noDevice` →
  `.disconnected`).
- On `.level`, feeds `LowBatteryPolicy`; on `true`, calls notifier.

**`LowBatteryNotifier` (App)** — wraps `UNUserNotificationCenter`; requests
authorization at launch; posts "Keychron battery low: N%".

**`LoginItem` (App)** — wraps `SMAppService.mainApp` register/unregister/status.

**`KeycronBatApp` (App)** — `MenuBarExtra` with label
`Image(systemName: "keyboard")` + text; menu items per Scope.

### Packaging

`scripts/build-app.sh`:
1. `swift build -c release`
2. Assemble `build/KeycronBat.app/Contents/{MacOS,Info.plist}` with
   `LSUIElement=true`, bundle id `dev.qubits.keycronbat`.
3. `codesign --force --sign - build/KeycronBat.app` (ad-hoc).

A stable bundle path + id is needed so Input Monitoring and Login Item
permissions stick. Re-signing ad-hoc after rebuilds may require re-granting
Input Monitoring; acceptable for personal use.

## Data flow

```
IOHIDManager (connect/remove) ─┐
Timer 300s ────────────────────┼─> BatteryMonitor.refresh()
Menu "Refresh" ────────────────┘        │
                                         ├─> BatteryReader.read() ─> BatteryReport.parse
                                         ├─> state (UI label/menu)
                                         └─> LowBatteryPolicy ─> LowBatteryNotifier
```

## Error handling

- No device / read failure → `disconnected` (grey `—`), retry next tick.
- Not permitted → `needsPermission`, menu shows grant item; re-check on
  each refresh.
- Notification authorization denied → silently skip notifications.

## Testing

- Unit (XCTest, `KeycronBatCore`): `BatteryReport.parse` (valid, wrong ID,
  short buffer, >100) and `LowBatteryPolicy` (single fire, hysteresis re-arm,
  starting below threshold fires once).
- Manual: build app, grant Input Monitoring, verify label matches probe value;
  turn keyboard off → `—`; on → value within seconds; Open at Login toggle
  persists across relaunch.
