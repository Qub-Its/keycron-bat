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
