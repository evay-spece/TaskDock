import Foundation
import AppKit

@main
struct DockBadgeSelfTest {
    static func main() {
        precondition(DockBadgeService.normalizedBadge("2") == "2")
        precondition(DockBadgeService.normalizedBadge(" 42 ") == "42")
        precondition(DockBadgeService.normalizedBadge("100") == "99+")
        precondition(DockBadgeService.normalizedBadge("9+") == "9+")
        precondition(DockBadgeService.normalizedBadge("0") == nil)
        precondition(DockBadgeService.normalizedBadge("new") == nil)
        precondition(DockBadgeService.normalizedBadge("42 unread") == nil)

        let reminder = FavoriteApp(
            id: "com.apple.reminders",
            bundleIdentifier: "com.apple.reminders",
            applicationName: "提醒事项",
            bundlePath: "/System/Applications/Reminders.app"
        )
        precondition(DockBadgeService.matches(
            reminder,
            tileURL: URL(fileURLWithPath: "/System/Applications/Reminders.app"),
            tileBundleIdentifier: nil,
            tileTitle: "提醒事项"
        ))
        precondition(DockBadgeService.matches(
            reminder,
            tileURL: URL(fileURLWithPath: "/Applications/Reminders.app"),
            tileBundleIdentifier: "com.apple.reminders",
            tileTitle: "Reminders"
        ))
        precondition(!DockBadgeService.matches(
            reminder,
            tileURL: URL(fileURLWithPath: "/Applications/Mail.app"),
            tileBundleIdentifier: "com.apple.mail",
            tileTitle: "邮件"
        ))
        if CommandLine.arguments.contains("--live"),
           let dockPID = NSRunningApplication.runningApplications(
               withBundleIdentifier: "com.apple.dock"
           ).first?.processIdentifier {
            print("LIVE_DOCK_BADGES \(DockBadgeService.badges(for: [reminder], dockPID: dockPID))")
        }
        print("DOCK_BADGE_OK")
    }
}
