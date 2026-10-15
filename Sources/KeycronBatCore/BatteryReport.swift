/// Parses the HID input report carrying Battery Strength (Usage Page 0x06, Usage 0x20).
/// Layout: [reportID, level 0...100, ...ignored].
public enum BatteryReport {
    public static func parse(_ bytes: [UInt8], reportID: UInt8 = 3) -> Int? {
        guard bytes.count >= 2, bytes[0] == reportID else { return nil }
        let level = Int(bytes[1])
        return (0...100).contains(level) ? level : nil
    }
}
