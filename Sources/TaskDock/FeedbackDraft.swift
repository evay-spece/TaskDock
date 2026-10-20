import Foundation

/// Local draft support. Actual feedback is submitted in the published Tencent form.
enum FeedbackDraft {
    static let formURLInfoKey = "TaskDockFeedbackFormURL"

    static var configuredFormURL: URL? {
        formURL(from: Bundle.main.object(forInfoDictionaryKey: formURLInfoKey) as? String)
    }

    /// Only accept HTTPS Tencent Questionnaire respondent links, never an editor or login URL.
    static func formURL(from value: String?) -> URL? {
        guard let value,
              let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "wj.qq.com",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              components.path.hasPrefix("/s2/") || components.path.hasPrefix("/s/"),
              components.path.split(separator: "/").count >= 2 else { return nil }
        return components.url
    }

    static func environment(version: String, build: String, systemVersion: String) -> String {
        "TaskDock：\(version)（\(build)）\nmacOS：\(systemVersion)"
    }

    static func copyText(title: String, details: String, environment: String) -> String {
        let parts = [title, details].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return (parts + [environment]).joined(separator: "\n\n")
    }
}
