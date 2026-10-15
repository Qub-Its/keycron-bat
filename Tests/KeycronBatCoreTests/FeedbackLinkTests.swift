import XCTest
@testable import KeycronBatCore

final class FeedbackLinkTests: XCTestCase {
    private func makeURL() -> URL {
        FeedbackLink.url(appVersion: "0.2.0", osVersion: "15.1", status: "36%")
    }

    func testTargetsNewIssuePage() {
        let url = makeURL()
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/Qub-Its/keycron-bat/issues/new")
    }

    func testBodyContainsDiagnostics() {
        let items = URLComponents(url: makeURL(), resolvingAgainstBaseURL: false)?.queryItems
        let body = items?.first { $0.name == "body" }?.value ?? ""
        XCTAssertTrue(body.contains("App version: 0.2.0"))
        XCTAssertTrue(body.contains("macOS: 15.1"))
        XCTAssertTrue(body.contains("Status: 36%"))
    }

    func testURLIsFullyEncoded() {
        let s = makeURL().absoluteString
        XCTAssertFalse(s.contains(" "))
        XCTAssertFalse(s.contains("\n"))
        XCTAssertTrue(s.contains("36%25"))
    }

    func testNoTitleItem() {
        let items = URLComponents(url: makeURL(), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertNil(items?.first { $0.name == "title" })
    }
}
