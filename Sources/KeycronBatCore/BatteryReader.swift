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
        var sawReadFailure = false
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
            let result = ReadResult.fromReport(status, bytes: Array(buffer.prefix(max(0, length))), reportID: UInt8(truncatingIfNeeded: reportID))
            switch result {
            case .level: return result
            case .notPermitted: sawPermissionError = true
            default: sawReadFailure = true
            }
        }
        if sawPermissionError { return .notPermitted }
        return sawReadFailure ? .failed : .noDevice
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
