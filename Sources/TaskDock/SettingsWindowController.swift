import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    private let onChanged: () -> Void
    private var hostingView: NSHostingView<AnyView>!

    init(settings: SettingsStore, windows: [WindowModel], onChanged: @escaping () -> Void) {
        self.settings = settings
        self.onChanged = onChanged

        let rootView = AnyView(
            SettingsView(settings: settings, windows: windows, onChanged: onChanged)
                .preferredColorScheme(settings.appearance.colorScheme)
        )
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 690),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TaskDock 设置"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        self.hostingView = hostingView
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(windows: [WindowModel]) {
        hostingView.rootView = AnyView(
            SettingsView(settings: settings, windows: windows, onChanged: onChanged)
                .preferredColorScheme(settings.appearance.colorScheme)
        )
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }
}
