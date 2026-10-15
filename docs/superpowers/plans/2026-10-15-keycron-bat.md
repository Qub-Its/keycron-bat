# keycron-bat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS menu bar app that shows the Keychron K3's Bluetooth battery % and notifies below 20%.

**Architecture:** SwiftPM package. `KeycronBatCore` library holds pure logic (report parsing, IOReturn mapping, low-battery policy) plus the one IOKit unit (`BatteryReader`). `KeycronBat` executable is a SwiftUI `MenuBarExtra` app that polls the reader every 5 min and on device connect. A shell script wraps the binary into an ad-hoc signed `.app`.

**Tech Stack:** Swift 6.0 toolchain with `swift-tools-version:5.10` (Swift 5 language mode — avoids strict-concurrency friction with IOKit C callbacks), SwiftUI, IOKit HID, UserNotifications, ServiceManagement, XCTest. macOS 14+.

**Spec:** `docs/superpowers/specs/2026-10-15-keycron-bat-design.md`

## Global Constraints

- Platform: `.macOS(.v14)`; SwiftUI `MenuBarExtra`.
- Bundle id: `dev.qubits.keycronbat`; `LSUIElement = true` (no Dock icon).
- Battery source: HID Usage Page `0x06`, Usage `0x20`, Input element; read with `IOHIDDeviceGetReport(kIOHIDReportTypeInput, reportID)`; 8-byte buffer; `bytes[0] == reportID`, `bytes[1]` = level 0–100.
- `kIOReturnNotPermitted` = `0xE00002E2` → needs Input Monitoring.
- Poll interval 300 s; also refresh on device connect/remove and on "Refresh".
- Low-battery threshold 20 (fixed), re-arm at ≥ 25.
- Menu items: status line, "Grant Input Monitoring…" (only when needed), "Refresh", "Open at Login" toggle, "Quit".
- Label: SF Symbol `keyboard` + `NN%`; disconnected → `—`; needs permission → `!`.
- No third-party dependencies.

## Review Focus

1. Running the bare binary (`swift run`, no bundle) → must not crash; `UNUserNotificationCenter` and `SMAppService` are skipped when `Bundle.main.bundleIdentifier == nil`. Pinned by Task 4 Step 5 smoke run.
2. Keyboard asleep/off while still paired → `GetReport` returns `0xE00002C7` → `.failed` → label `—`, no crash. Pinned by `ReadResultTests.testOtherErrorIsFailed` (Task 2).
3. Level `0` is a valid reading; byte > 100 is garbage → `nil`. Pinned by `BatteryReportTests` (Task 1).
4. App launched while battery already below 20% → notifies exactly once, not every poll. Pinned by `LowBatteryPolicyTests.testStartingBelowThresholdFiresOnce` (Task 3).
5. Other keyboards present (built-in Apple keyboard has no battery element) → reader skips them and still finds the K3; failure to open one device must not hide another's reading. Pinned by `read()` loop structure (Task 2) + manual check in Task 5.

---

## File Structure

```
Package.swift
.gitignore
Sources/KeycronBatCore/BatteryReport.swift      # parse raw report bytes → Int?
Sources/KeycronBatCore/ReadResult.swift         # ReadResult enum + IOReturn mapping
Sources/KeycronBatCore/BatteryReader.swift      # IOKit HID manager, read()
Sources/KeycronBatCore/LowBatteryPolicy.swift   # threshold + hysteresis
Sources/KeycronBat/KeycronBatApp.swift          # @main, MenuBarExtra, label + menu views
Sources/KeycronBat/BatteryMonitor.swift         # timer, state, policy → notifier
Sources/KeycronBat/LowBatteryNotifier.swift     # UNUserNotificationCenter wrapper
Sources/KeycronBat/LoginItem.swift              # SMAppService wrapper
Tests/KeycronBatCoreTests/BatteryReportTests.swift
Tests/KeycronBatCoreTests/ReadResultTests.swift
Tests/KeycronBatCoreTests/LowBatteryPolicyTests.swift
Resources/Info.plist
scripts/build-app.sh
```

---

### Task 1: Package scaffold + BatteryReport parsing

**Files:**
- Create: `Package.swift`, `.gitignore`, `Sources/KeycronBatCore/BatteryReport.swift`
- Test: `Tests/KeycronBatCoreTests/BatteryReportTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public enum BatteryReport { public static func parse(_ bytes: [UInt8], reportID: UInt8 = 3) -> Int? }`

- [ ] **Step 1: Create package files**

`Package.swift`:
```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "KeycronBat",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KeycronBatCore"),
        .testTarget(name: "KeycronBatCoreTests", dependencies: ["KeycronBatCore"]),
    ]
)
```

`.gitignore`:
```
.build/
build/
.swiftpm/
```

- [ ] **Step 2: Write the failing test**

`Tests/KeycronBatCoreTests/BatteryReportTests.swift`:
```swift
import XCTest
@testable import KeycronBatCore

final class BatteryReportTests: XCTestCase {
    func testParsesLevelFromValidReport() {
        XCTAssertEqual(BatteryReport.parse([3, 36]), 36)
    }

    func testIgnoresTrailingBytes() {
        // Real device returns 8 bytes; bytes 2... are junk (BT address).
        XCTAssertEqual(BatteryReport.parse([3, 36, 220, 44, 38, 50, 178, 201]), 36)
    }

    func testZeroIsValid() {
        XCTAssertEqual(BatteryReport.parse([3, 0]), 0)
    }

    func testHundredIsValid() {
        XCTAssertEqual(BatteryReport.parse([3, 100]), 100)
    }

    func testAboveHundredIsNil() {
        XCTAssertNil(BatteryReport.parse([3, 101]))
    }

    func testWrongReportIDIsNil() {
        XCTAssertNil(BatteryReport.parse([4, 36]))
    }

    func testCustomReportID() {
        XCTAssertEqual(BatteryReport.parse([7, 50], reportID: 7), 50)
    }

    func testShortBufferIsNil() {
        XCTAssertNil(BatteryReport.parse([3]))
        XCTAssertNil(BatteryReport.parse([]))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter BatteryReportTests`
Expected: build FAIL — `cannot find 'BatteryReport' in scope` (or "no sources" for target `KeycronBatCore`).

- [ ] **Step 4: Write minimal implementation**

`Sources/KeycronBatCore/BatteryReport.swift`:
```swift
/// Parses the HID input report carrying Battery Strength (Usage Page 0x06, Usage 0x20).
/// Layout: [reportID, level 0...100, ...ignored].
public enum BatteryReport {
    public static func parse(_ bytes: [UInt8], reportID: UInt8 = 3) -> Int? {
        guard bytes.count >= 2, bytes[0] == reportID else { return nil }
        let level = Int(bytes[1])
        return (0...100).contains(level) ? level : nil
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter BatteryReportTests`
Expected: PASS, 8 tests.

- [ ] **Step 6: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "feat: add package scaffold and battery report parser"
```

---

### Task 2: ReadResult mapping + BatteryReader (IOKit)

**Files:**
- Create: `Sources/KeycronBatCore/ReadResult.swift`, `Sources/KeycronBatCore/BatteryReader.swift`
- Test: `Tests/KeycronBatCoreTests/ReadResultTests.swift`

**Interfaces:**
- Consumes: `BatteryReport.parse(_:reportID:)` (Task 1).
- Produces:
  - `public enum ReadResult: Equatable { case level(Int), noDevice, notPermitted, failed }`
  - `public static func ReadResult.fromReport(_ status: IOReturn, bytes: [UInt8], reportID: UInt8) -> ReadResult`
  - `public enum IOReturnCode { public static let success: IOReturn; public static let notPermitted: IOReturn }`
  - `public final class BatteryReader { public init(); public var onDevicesChanged: (() -> Void)?; public func read() -> ReadResult }`

- [ ] **Step 1: Write the failing test**

`Tests/KeycronBatCoreTests/ReadResultTests.swift`:
```swift
import XCTest
import IOKit
@testable import KeycronBatCore

final class ReadResultTests: XCTestCase {
    func testSuccessWithValidBytesIsLevel() {
        XCTAssertEqual(ReadResult.fromReport(IOReturnCode.success, bytes: [3, 36], reportID: 3), .level(36))
    }

    func testNotPermittedMapsToNotPermitted() {
        XCTAssertEqual(ReadResult.fromReport(IOReturnCode.notPermitted, bytes: [], reportID: 3), .notPermitted)
    }

    func testOtherErrorIsFailed() {
        // 0xE00002C7 (kIOReturnUnsupported) seen from a sleeping / non-supporting device.
        let unsupported = IOReturn(bitPattern: 0xE00002C7)
        XCTAssertEqual(ReadResult.fromReport(unsupported, bytes: [0, 0], reportID: 3), .failed)
    }

    func testSuccessWithGarbageIsFailed() {
        XCTAssertEqual(ReadResult.fromReport(IOReturnCode.success, bytes: [3, 200], reportID: 3), .failed)
    }

    func testNotPermittedConstantValue() {
        XCTAssertEqual(UInt32(bitPattern: IOReturnCode.notPermitted), 0xE00002E2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ReadResultTests`
Expected: build FAIL — `cannot find 'ReadResult' in scope`.

- [ ] **Step 3: Implement ReadResult**

`Sources/KeycronBatCore/ReadResult.swift`:
```swift
import IOKit

public enum ReadResult: Equatable {
    case level(Int)
    case noDevice
    case notPermitted
    case failed

    public static func fromReport(_ status: IOReturn, bytes: [UInt8], reportID: UInt8) -> ReadResult {
        if status == IOReturnCode.notPermitted { return .notPermitted }
        guard status == IOReturnCode.success,
              let level = BatteryReport.parse(bytes, reportID: reportID) else { return .failed }
        return .level(level)
    }
}

/// IOKit's kIOReturn* values are C macros Swift does not import.
public enum IOReturnCode {
    public static let success: IOReturn = 0
    /// kIOReturnNotPermitted — opening a keyboard without Input Monitoring permission.
    public static let notPermitted = IOReturn(bitPattern: 0xE00002E2)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ReadResultTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Implement BatteryReader**

`Sources/KeycronBatCore/BatteryReader.swift`:
```swift
import Foundation
import IOKit.hid

/// The only unit that touches IOKit. Finds a keyboard exposing Battery Strength
/// (Usage Page 0x06, Usage 0x20) and reads its input report on demand.
public final class BatteryReader {
    public var onDevicesChanged: (() -> Void)?

    private let manager: IOHIDManager
    private static let options = IOOptionBits(kIOHIDOptionsTypeNone)

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, Self.options)
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            Unmanaged<BatteryReader>.fromOpaque(context).takeUnretainedValue().onDevicesChanged?()
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, callback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, callback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        // Result ignored: without Input Monitoring this fails, but device
        // enumeration and connect/remove callbacks still work.
        _ = IOHIDManagerOpen(manager, Self.options)
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, Self.options)
    }

    public func read() -> ReadResult {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            return .noDevice
        }
        var sawPermissionError = false
        for device in devices {
            let openStatus = IOHIDDeviceOpen(device, Self.options)
            if openStatus == IOReturnCode.notPermitted {
                sawPermissionError = true
                continue
            }
            guard openStatus == IOReturnCode.success else { continue }
            defer { IOHIDDeviceClose(device, Self.options) }

            // Elements are only visible once the device is open.
            guard let reportID = batteryReportID(of: device) else { continue }
            var buffer = [UInt8](repeating: 0, count: 8)
            var length = CFIndex(buffer.count)
            let status = IOHIDDeviceGetReport(device, kIOHIDReportTypeInput, CFIndex(reportID), &buffer, &length)
            return ReadResult.fromReport(status, bytes: Array(buffer.prefix(length)), reportID: UInt8(truncatingIfNeeded: reportID))
        }
        return sawPermissionError ? .notPermitted : .noDevice
    }

    private func batteryReportID(of device: IOHIDDevice) -> UInt32? {
        let matching: [String: Any] = [
            kIOHIDElementUsagePageKey: 0x06, // Generic Device Controls
            kIOHIDElementUsageKey: 0x20,     // Battery Strength
        ]
        let elements = IOHIDDeviceCopyMatchingElements(device, matching as CFDictionary, Self.options) as? [IOHIDElement] ?? []
        return elements
            .first { IOHIDElementGetType($0) == kIOHIDElementTypeInput_Misc }
            .map { IOHIDElementGetReportID($0) }
    }
}
```

- [ ] **Step 6: Build and run all tests**

Run: `swift build && swift test`
Expected: build succeeds with no errors; 13 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/KeycronBatCore Tests/KeycronBatCoreTests/ReadResultTests.swift
git commit -m "feat: add HID battery reader and IOReturn mapping"
```

---

### Task 3: LowBatteryPolicy

**Files:**
- Create: `Sources/KeycronBatCore/LowBatteryPolicy.swift`
- Test: `Tests/KeycronBatCoreTests/LowBatteryPolicyTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public struct LowBatteryPolicy { public init(threshold: Int = 20, rearm: Int = 25); public mutating func update(level: Int) -> Bool }`

- [ ] **Step 1: Write the failing test**

`Tests/KeycronBatCoreTests/LowBatteryPolicyTests.swift`:
```swift
import XCTest
@testable import KeycronBatCore

final class LowBatteryPolicyTests: XCTestCase {
    func testAboveThresholdDoesNotFire() {
        var policy = LowBatteryPolicy()
        XCTAssertFalse(policy.update(level: 50))
        XCTAssertFalse(policy.update(level: 20))
    }

    func testFiresOnceWhenDroppingBelowThreshold() {
        var policy = LowBatteryPolicy()
        XCTAssertFalse(policy.update(level: 30))
        XCTAssertTrue(policy.update(level: 19))
        XCTAssertFalse(policy.update(level: 18))
        XCTAssertFalse(policy.update(level: 5))
    }

    func testStartingBelowThresholdFiresOnce() {
        var policy = LowBatteryPolicy()
        XCTAssertTrue(policy.update(level: 15))
        XCTAssertFalse(policy.update(level: 15))
    }

    func testDoesNotRearmBetweenThresholdAndRearm() {
        var policy = LowBatteryPolicy()
        XCTAssertTrue(policy.update(level: 19))
        XCTAssertFalse(policy.update(level: 24))
        XCTAssertFalse(policy.update(level: 19))
    }

    func testRearmsAtRearmLevel() {
        var policy = LowBatteryPolicy()
        XCTAssertTrue(policy.update(level: 19))
        XCTAssertFalse(policy.update(level: 25))
        XCTAssertTrue(policy.update(level: 19))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LowBatteryPolicyTests`
Expected: build FAIL — `cannot find 'LowBatteryPolicy' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/KeycronBatCore/LowBatteryPolicy.swift`:
```swift
/// Decides when to warn about low battery: once per drop below `threshold`,
/// re-armed only after the level recovers to `rearm` or more.
public struct LowBatteryPolicy {
    public let threshold: Int
    public let rearm: Int
    private var armed = true

    public init(threshold: Int = 20, rearm: Int = 25) {
        self.threshold = threshold
        self.rearm = rearm
    }

    /// Returns true when a notification should be sent for this reading.
    public mutating func update(level: Int) -> Bool {
        if level < threshold {
            guard armed else { return false }
            armed = false
            return true
        }
        if level >= rearm { armed = true }
        return false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS, 18 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/KeycronBatCore/LowBatteryPolicy.swift Tests/KeycronBatCoreTests/LowBatteryPolicyTests.swift
git commit -m "feat: add low battery notification policy"
```

---

### Task 4: Menu bar app (monitor, notifier, login item, UI)

**Files:**
- Modify: `Package.swift` (add executable target)
- Create: `Sources/KeycronBat/KeycronBatApp.swift`, `Sources/KeycronBat/BatteryMonitor.swift`, `Sources/KeycronBat/LowBatteryNotifier.swift`, `Sources/KeycronBat/LoginItem.swift`

**Interfaces:**
- Consumes: `BatteryReader()`, `.onDevicesChanged`, `.read() -> ReadResult` (Task 2); `LowBatteryPolicy.update(level:) -> Bool` (Task 3).
- Produces: executable product `KeycronBat` (used by Task 5's script).

UI glue over IOKit/AppKit; no unit tests (spec: manual verification). Logic it relies on is already tested in Tasks 1–3.

- [ ] **Step 1: Add executable target**

Replace the `targets:` array in `Package.swift` with:
```swift
    targets: [
        .target(name: "KeycronBatCore"),
        .executableTarget(name: "KeycronBat", dependencies: ["KeycronBatCore"]),
        .testTarget(name: "KeycronBatCoreTests", dependencies: ["KeycronBatCore"]),
    ]
```

- [ ] **Step 2: Notifier and login item**

`Sources/KeycronBat/LowBatteryNotifier.swift`:
```swift
import Foundation
import UserNotifications

final class LowBatteryNotifier {
    /// UNUserNotificationCenter crashes when the process has no bundle (e.g. `swift run`).
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(level: Int) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "Keychron battery low"
        content.body = "Battery at \(level)%. Plug in your keyboard."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "low-battery", content: content, trigger: nil))
    }
}
```

`Sources/KeycronBat/LoginItem.swift`:
```swift
import Foundation
import ServiceManagement

@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    /// SMAppService needs a real .app bundle.
    var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("KeycronBat: login item update failed: \(error)")
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
```

- [ ] **Step 3: Battery monitor**

`Sources/KeycronBat/BatteryMonitor.swift`:
```swift
import Foundation
import KeycronBatCore

@MainActor
final class BatteryMonitor: ObservableObject {
    enum State: Equatable {
        case level(Int)
        case disconnected
        case needsPermission
    }

    @Published private(set) var state: State = .disconnected

    private let reader = BatteryReader()
    private let notifier = LowBatteryNotifier()
    private var policy = LowBatteryPolicy()
    private var timer: Timer?

    init() {
        notifier.requestAuthorization()
        reader.onDevicesChanged = { [weak self] in
            // Give a freshly connected Bluetooth link a moment before querying it.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self?.refresh()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        switch reader.read() {
        case .level(let level):
            state = .level(level)
            if policy.update(level: level) {
                notifier.notify(level: level)
            }
        case .notPermitted:
            state = .needsPermission
        case .noDevice, .failed:
            state = .disconnected
        }
    }
}
```

- [ ] **Step 4: App entry and views**

`Sources/KeycronBat/KeycronBatApp.swift`:
```swift
import AppKit
import SwiftUI

@main
struct KeycronBatApp: App {
    @StateObject private var monitor = BatteryMonitor()
    @StateObject private var loginItem = LoginItem()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor, loginItem: loginItem)
        } label: {
            MenuBarLabel(state: monitor.state)
        }
    }
}

struct MenuBarLabel: View {
    let state: BatteryMonitor.State

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "keyboard")
            Text(text)
        }
    }

    private var text: String {
        switch state {
        case .level(let level): "\(level)%"
        case .disconnected: "—"
        case .needsPermission: "!"
        }
    }
}

struct MenuContent: View {
    @ObservedObject var monitor: BatteryMonitor
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        Text(statusLine)
        if monitor.state == .needsPermission {
            Button("Grant Input Monitoring…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            }
        }
        Divider()
        Button("Refresh") { monitor.refresh() }
        if loginItem.isAvailable {
            Toggle("Open at Login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))
        }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        switch monitor.state {
        case .level(let level): "Keychron battery: \(level)%"
        case .disconnected: "Keyboard not connected"
        case .needsPermission: "Input Monitoring permission required"
        }
    }
}
```

- [ ] **Step 5: Build, test, smoke run without bundle (Review Focus #1)**

Run:
```bash
swift build && swift test
swift build --product KeycronBat
( "$(swift build --show-bin-path)/KeycronBat" & PID=$!; sleep 5; kill -0 $PID && echo ALIVE; kill $PID )
```
Expected: build OK, 18 tests PASS, prints `ALIVE` (process did not crash without a bundle). A menu bar item may appear briefly; that is fine.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/KeycronBat
git commit -m "feat: add menu bar app with battery monitor and alerts"
```

---

### Task 5: .app packaging + manual verification

**Files:**
- Create: `Resources/Info.plist`, `scripts/build-app.sh`

**Interfaces:**
- Consumes: executable product `KeycronBat` (Task 4).
- Produces: `build/KeycronBat.app` (ad-hoc signed).

- [ ] **Step 1: Info.plist**

`Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>KeycronBat</string>
    <key>CFBundleIdentifier</key>
    <string>dev.qubits.keycronbat</string>
    <key>CFBundleName</key>
    <string>KeycronBat</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Build script**

`scripts/build-app.sh`:
```bash
#!/usr/bin/env bash
# Builds build/KeycronBat.app (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product KeycronBat
BIN="$(swift build -c release --show-bin-path)/KeycronBat"

APP=build/KeycronBat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/KeycronBat"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"
```

Run: `chmod +x scripts/build-app.sh && scripts/build-app.sh && plutil -lint build/KeycronBat.app/Contents/Info.plist && codesign -dv build/KeycronBat.app 2>&1 | grep -E 'Identifier|Signature'`
Expected: `Built build/KeycronBat.app`, `OK` from plutil, `Identifier=dev.qubits.keycronbat`, `Signature=adhoc`.

- [ ] **Step 3: Commit**

```bash
git add Resources/Info.plist scripts/build-app.sh
git commit -m "build: add app bundle script and Info.plist"
```

- [ ] **Step 4: Manual verification (human — the implementer stops here and reports)**

Agent cannot grant privacy permissions. Hand these to the user:
1. `open build/KeycronBat.app` → label shows `⌨ !` (no permission yet). Menu shows "Grant Input Monitoring…".
2. Click it, enable **KeycronBat** in Input Monitoring, Quit and reopen the app.
3. Label shows `⌨ NN%`, matching the scratchpad `probe2` value (± a point). Confirms the built-in keyboard is skipped (Review Focus #5).
4. Turn K3 off → within ~2 s label `—`. Turn on → `NN%` within a few seconds.
5. Toggle "Open at Login" on, Quit, reopen → toggle still on. Check it in System Settings → General → Login Items.
6. If the label shows only the icon (no text), report it; fallback is `Text("⌨ \(level)%")` as the sole label view.
