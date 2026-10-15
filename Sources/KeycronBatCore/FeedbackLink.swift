import Foundation

public enum FeedbackLink {
    public static let newIssueURL = "https://github.com/Qub-Its/keycron-bat/issues/new"

    public static func url(appVersion: String, osVersion: String, status: String) -> URL {
        let body = """
        **What happened?**


        **What did you expect?**


        ---
        App version: \(appVersion)
        macOS: \(osVersion)
        Status: \(status)
        """
        var components = URLComponents(string: newIssueURL)!
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url!
    }
}
