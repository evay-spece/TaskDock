// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TaskDock",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "TaskDock", targets: ["TaskDock"]), .executable(name: "TaskDockBrowserHost", targets: ["TaskDockBrowserHost"])],
    targets: [
        .target(name: "TaskDockBrowserProtocol", path: "Sources/TaskDockBrowserProtocol"),
        .executableTarget(name: "TaskDockBrowserHost", dependencies: ["TaskDockBrowserProtocol"], path: "Sources/TaskDockBrowserHost"),
        .target(name: "TaskDockPreferences", path: "Sources/TaskDockPreferences"),
        .executableTarget(name: "TaskDock", dependencies: ["TaskDockPreferences", "TaskDockBrowserProtocol"], path: "Sources/TaskDock", resources: [.copy("Resources")])
    ]
)
