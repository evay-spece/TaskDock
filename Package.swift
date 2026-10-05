// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TaskDock",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "TaskDock", targets: ["TaskDock"])],
    targets: [
        .target(name: "TaskDockPreferences", path: "Sources/TaskDockPreferences"),
        .executableTarget(name: "TaskDock", dependencies: ["TaskDockPreferences"], path: "Sources/TaskDock")
    ]
)
