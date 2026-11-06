import AppKit
import SwiftUI

@MainActor
final class UpdateReminderWindowController: NSWindowController {
    init(currentVersion: String, newVersion: String, releaseNotes: String = "",
         onUpdate: @escaping () -> Void, onLater: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "TaskDock 更新提醒"
        window.contentView = NSHostingView(rootView: UpdateReminderView(
            currentVersion: currentVersion,
            newVersion: newVersion,
            releaseNotes: releaseNotes,
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
    let releaseNotes: String
    let onUpdate: () -> Void
    let onLater: () -> Void

    private var visibleReleaseNotes: [String] {
        releaseNotes.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "`*_ "))
            let lowercased = trimmed.lowercased()
            if lowercased.hasPrefix("build ") || lowercased.hasPrefix("安装包 sha-256")
                || lowercased.hasPrefix("sha-256：")
                || (lowercased.hasPrefix("macos ") && lowercased.contains("apple silicon")) {
                return false
            }
            return trimmed.count != 64 || !trimmed.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("TaskDock \(newVersion) 已发布", systemImage: "arrow.up.circle.fill")
                .font(.headline)
            Text("当前版本为 \(currentVersion)。现在更新即可使用新版 TaskDock。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider()
            Text("本次更新").font(.subheadline.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if visibleReleaseNotes.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                        Text("此版本暂无更新说明。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(visibleReleaseNotes.enumerated()), id: \.offset) { _, line in
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            if trimmed.hasPrefix("#") {
                                Text(trimmed.drop(while: { $0 == "#" || $0 == " " }))
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.top, 4)
                            } else if !trimmed.isEmpty {
                                Text(.init(trimmed.hasPrefix("- ") ? "• " + String(trimmed.dropFirst(2)) : trimmed))
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
                .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Spacer()
                Button("暂不更新", action: onLater)
                Button("下载并更新", action: onUpdate)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500, height: 430)
    }
}
