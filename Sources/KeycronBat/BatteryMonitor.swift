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
