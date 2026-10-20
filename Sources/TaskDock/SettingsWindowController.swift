import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: SettingsStore
    private let onChanged: () -> Void
    private let onVisualChanged: () -> Void
    private let onLayoutChanged: () -> Void
    private let license: LicenseService
    private let onOpenLicense: () -> Void
    private var hostingView: NSHostingView<AnyView>!

    init(
        settings: SettingsStore,
        windows: [WindowModel],
        license: LicenseService,
        onOpenLicense: @escaping () -> Void,
        onChanged: @escaping () -> Void,
        onVisualChanged: @escaping () -> Void,
        onLayoutChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.license = license
        self.onOpenLicense = onOpenLicense
        self.onChanged = onChanged
        self.onVisualChanged = onVisualChanged
        self.onLayoutChanged = onLayoutChanged

        let rootView = AnyView(
            SettingsView(
                settings: settings, license: license, windows: windows,
                onChanged: onChanged,
                onVisualChanged: onVisualChanged,
                onLayoutChanged: onLayoutChanged,
                onOpenLicense: onOpenLicense
            )
        )
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 710),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "TaskDock 设置"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
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
            SettingsView(
                settings: settings, license: license, windows: windows,
                onChanged: onChanged,
                onVisualChanged: onVisualChanged,
                onLayoutChanged: onLayoutChanged,
                onOpenLicense: onOpenLicense
            )
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
