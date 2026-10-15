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
