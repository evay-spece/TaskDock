import Foundation

/// Presentation only: raw AX titles remain available for identifying windows.
enum WindowDisplayTitle {
    static func noteTitle(from body: String) -> String? {
        let firstLine = body.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstLine.isEmpty ? nil : firstLine
    }

    static func resolve(rawTitle: String, applicationName: String,
                        bundleIdentifier: String?, selectedNoteTitle: String? = nil) -> String {
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if bundleIdentifier == "com.apple.Notes" {
            if let selectedNoteTitle, !selectedNoteTitle.isEmpty { return selectedNoteTitle }
            // Collection windows append the note count. Keep just the collection name.
            title = title.replacingOccurrences(
                of: #"\s*(?:[-–—·]\s*)?\d+\s*(?:个备忘录|条备忘录|notes?)\s*$"#,
                with: "", options: [.regularExpression, .caseInsensitive])
        } else if bundleIdentifier == "com.microsoft.edgemac" {
            // Strip only Edge's trailing performance annotation, never arbitrary page text.
            title = title.replacingOccurrences(
                of: #"\s*[-–—|·]\s*(?:内存使用量高|内存使用量|内存占用高|High memory usage|Memory usage)(?:\s*[:：\-–—]\s*|\s+)?(?:\d+(?:[.,]\d+)?\s*[KMGT]i?B)?\s*(?:\.{3}|…)?(?:\s*[-–—]\s*Microsoft Edge)?\s*$"#,
                with: "", options: [.regularExpression, .caseInsensitive])
        }
        return title.isEmpty ? applicationName : title
    }
}
