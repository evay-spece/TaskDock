import Foundation

enum TaskDockLicenseResources {
    static func url(name: String, ext: String) -> URL? {
        let filename = "\(name).\(ext)"
        var roots: [URL] = []
        if let resourceURL = Bundle.main.resourceURL { roots.append(resourceURL) }
        if let executableURL = Bundle.main.executableURL {
            roots.append(executableURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources"))
        }
        for root in roots {
            for candidate in [root.appendingPathComponent(filename), root.appendingPathComponent("Resources").appendingPathComponent(filename)] {
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        // Running under SwiftPM places copied resources beside the debug executable.
        if let executableURL = Bundle.main.executableURL {
            let sibling = executableURL.deletingLastPathComponent().appendingPathComponent("TaskDock_TaskDock.bundle/Resources").appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: sibling.path) { return sibling }
        }
        return nil
    }
}
