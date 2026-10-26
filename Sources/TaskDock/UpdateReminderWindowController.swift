import AppKit
import SwiftUI

@MainActor
final class UpdateReminderWindowController: NSWindowController {
    init(currentVersion: String, newVersion: String,
         onUpdate: @escaping () -> Void, onLater: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 190),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "TaskDock 更新提醒"
        window.contentView = NSHostingView(rootView: UpdateReminderView(
            currentVersion: currentVersion,
            newVersion: newVersion,
            onUpdate: onUpdate,
            onLater: onLater
        ))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}

private struct UpdateReminderView: View {
    let currentVersion: String
    let newVersion: String
    let onUpdate: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("TaskDock \(newVersion) 已发布", systemImage: "arrow.up.circle.fill")
                .font(.headline)
            Text("当前版本为 \(currentVersion)。现在更新即可使用新版 TaskDock。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("暂不更新", action: onLater)
                Button("下载并更新", action: onUpdate)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420, height: 190)
    }
}
