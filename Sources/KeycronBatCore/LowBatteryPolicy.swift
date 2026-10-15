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
