import XCTest
@testable import KeycronBatCore

final class LowBatteryPolicyTests: XCTestCase {
    func testAboveThresholdDoesNotFire() {
        var policy = LowBatteryPolicy()
        XCTAssertFalse(policy.update(level: 50))
        XCTAssertFalse(policy.update(level: 20))
    }

    func testFiresOnceWhenDroppingBelowThreshold() {
        var policy = LowBatteryPolicy()
        XCTAssertFalse(policy.update(level: 30))
        XCTAssertTrue(policy.update(level: 19))
        XCTAssertFalse(policy.update(level: 18))
        XCTAssertFalse(policy.update(level: 5))
    }

    func testStartingBelowThresholdFiresOnce() {
        var policy = LowBatteryPolicy()
        XCTAssertTrue(policy.update(level: 15))
        XCTAssertFalse(policy.update(level: 15))
    }

    func testDoesNotRearmBetweenThresholdAndRearm() {
        var policy = LowBatteryPolicy()
        XCTAssertTrue(policy.update(level: 19))
        XCTAssertFalse(policy.update(level: 24))
        XCTAssertFalse(policy.update(level: 19))
    }

    func testRearmsAtRearmLevel() {
        var policy = LowBatteryPolicy()
        XCTAssertTrue(policy.update(level: 19))
        XCTAssertFalse(policy.update(level: 25))
        XCTAssertTrue(policy.update(level: 19))
    }
}
