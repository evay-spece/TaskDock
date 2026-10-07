import AppKit
import SwiftUI

@MainActor
final class UpdateProgressWindowController: NSWindowController {
    init(checker: UpdateChecker) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 185),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "TaskDock 软件更新"
        window.contentView = NSHostingView(rootView: UpdateProgressView(checker: checker))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}

private struct UpdateProgressView: View {
    @ObservedObject var checker: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TaskDock 软件更新").font(.headline)
            Text(message).font(.callout)
            switch checker.status {
            case .checking, .verifying, .installing:
                ProgressView().progressViewStyle(.linear)
            case .downloading:
                if let progress = checker.downloadProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            default:
                EmptyView()
            }
            if case .failed = checker.status {
                Button("重试") { checker.checkAndInstall() }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 390, height: 185, alignment: .topLeading)
    }

    private var message: String {
        switch checker.status {
        case .idle, .checking: return "正在检查最新版本…"
        case .upToDate(let version): return "已经是最新版本（\(version)）。"
        case .updateAvailable(let update): return "发现 \(update.version)，准备下载…"
        case .downloading(let version): return "正在下载 \(version)…"
        case .verifying: return "正在验证安装包和签名…"
        case .installing: return "正在安装，TaskDock 即将重新启动…"
        case .failed(let message, _): return message
        }
    }
}
