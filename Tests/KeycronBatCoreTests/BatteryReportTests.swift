import XCTest
@testable import KeycronBatCore

final class BatteryReportTests: XCTestCase {
    func testParsesLevelFromValidReport() {
        XCTAssertEqual(BatteryReport.parse([3, 36]), 36)
    }

    func testIgnoresTrailingBytes() {
        // Real device returns 8 bytes; bytes 2... are junk (BT address).
        XCTAssertEqual(BatteryReport.parse([3, 36, 220, 44, 38, 50, 178, 201]), 36)
    }

    func testZeroIsValid() {
        XCTAssertEqual(BatteryReport.parse([3, 0]), 0)
    }

    func testHundredIsValid() {
        XCTAssertEqual(BatteryReport.parse([3, 100]), 100)
    }

    func testAboveHundredIsNil() {
        XCTAssertNil(BatteryReport.parse([3, 101]))
    }

    func testWrongReportIDIsNil() {
        XCTAssertNil(BatteryReport.parse([4, 36]))
    }

    func testCustomReportID() {
        XCTAssertEqual(BatteryReport.parse([7, 50], reportID: 7), 50)
    }

    func testShortBufferIsNil() {
        XCTAssertNil(BatteryReport.parse([3]))
        XCTAssertNil(BatteryReport.parse([]))
    }
}
