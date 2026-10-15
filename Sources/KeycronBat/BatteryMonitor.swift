import AppKit
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
    private var pendingRefresh: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init() {
        notifier.requestAuthorization()
        reader.onDevicesChanged = { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        // The timer doesn't fire during sleep; re-read as soon as the Mac wakes.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    /// Give a freshly connected (or just-woken) Bluetooth link a moment before
    /// querying it. Debounced: a burst of events yields a single refresh.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
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
