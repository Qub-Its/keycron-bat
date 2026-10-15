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
