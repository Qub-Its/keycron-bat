import AppKit
import KeycronBatCore
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
        Button("Report an Issue…") {
            NSWorkspace.shared.open(FeedbackLink.url(
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                status: feedbackStatus
            ))
        }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var feedbackStatus: String {
        switch monitor.state {
        case .level(let level): "\(level)%"
        case .disconnected: "disconnected"
        case .needsPermission: "needs permission"
        }
    }

    private var statusLine: String {
        switch monitor.state {
        case .level(let level): "Keychron battery: \(level)%"
        case .disconnected: "Keyboard not connected"
        case .needsPermission: "Input Monitoring permission required"
        }
    }
}
