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
