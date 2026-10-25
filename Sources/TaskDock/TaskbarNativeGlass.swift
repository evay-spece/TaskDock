import AppKit
import ObjectiveC.runtime

/// Private appearance experiment is isolated to our nonactivating taskbar panels.
/// Unsupported systems keep NSPanel's original implementation.
class TaskbarAppearancePanel: NSPanel {
    var permitsExperimentalGlass = false
}

enum TaskbarExperimentalGlass {
    static let preferenceKey = "taskdock.experimentalActiveGlassV1"
    static let clarityKey = "taskdock.customGlassClarityV1"

    static func normalizedClarity(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 1
    }
    private static var didCaptureOriginal = false
    private static var originalArgumentTint: Any?
    private static var appliedManualTint: Double?
    private static var didApply = false
    private static var observedSystemTint: Double?
    private static var preferenceObserver: NSObjectProtocol?
    private static let systemTintKey = "NSGlassTintAmount"

    /// Volatile argument-domain override is confined to this process. Never write
    /// global defaults or persist Apple's private key in the application's domain.
    static func installPreferenceIsolation() {
        synchronizePreferenceIsolation()
        guard preferenceObserver == nil else { return }
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { _ in synchronizePreferenceIsolation() }
    }

    static func synchronizePreferenceIsolation() {
        guard isSupported else { return }
        let defaults = UserDefaults.standard
        let custom = defaults.bool(forKey: preferenceKey)
        let clarity = (defaults.object(forKey: clarityKey) as? NSNumber)?.doubleValue ?? 1
        let manualTint: Double? = custom ? 1 - normalizedClarity(clarity) : nil
        if didApply && manualTint == appliedManualTint {
            // Following mode must also invalidate the cached native material when
            // System Settings changes its value during this process's lifetime.
            let resolved = defaults.double(forKey: systemTintKey)
            if manualTint == nil && observedSystemTint != resolved {
                observedSystemTint = resolved
                refreshNativeMaterial()
            }
            return
        }
        var domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        if !didCaptureOriginal {
            originalArgumentTint = domain[systemTintKey]
            didCaptureOriginal = true
        }
        // Commit before setting defaults; notifications can re-enter this method.
        appliedManualTint = manualTint
        didApply = true
        if let manualTint { domain[systemTintKey] = manualTint }
        else if let originalArgumentTint { domain[systemTintKey] = originalArgumentTint }
        else { domain.removeValue(forKey: systemTintKey) }
        defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
        observedSystemTint = defaults.double(forKey: systemTintKey)
        refreshNativeMaterial()
    }

    private static func refreshNativeMaterial() {
        NotificationCenter.default.post(
            name: Notification.Name("NSGlassEffectDiffusionDidChangeNotification"), object: nil)
    }

    static var isSupported: Bool { panelType != nil }
    private static let panelType: NSPanel.Type? = {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else { return nil }
        let selector = NSSelectorFromString("_hasActiveAppearance")
        guard let method = class_getInstanceMethod(NSPanel.self, selector),
              let encoding = method_getTypeEncoding(method),
              String(cString: encoding).hasPrefix("B"),
              method_getNumberOfArguments(method) == 2,
              let subclass = objc_allocateClassPair(TaskbarAppearancePanel.self, "TaskDockExperimentalAppearancePanel", 0) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        let original = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        let getter: @convention(block) (AnyObject) -> Bool = { object in
            if let panel = object as? TaskbarAppearancePanel,
               panel.permitsExperimentalGlass,
               UserDefaults.standard.bool(forKey: preferenceKey) { return true }
            return original(object, selector)
        }
        let implementation = imp_implementationWithBlock(getter)
        guard class_addMethod(subclass, selector, implementation, encoding) else {
            imp_removeBlock(implementation)
            objc_disposeClassPair(subclass)
            return nil
        }
        objc_registerClassPair(subclass)
        return subclass as? NSPanel.Type
    }()

    static func makePanel() -> NSPanel {
        (panelType ?? TaskbarAppearancePanel.self).init(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    }
}


/// Glass is a native sibling beneath the hosting view, never an offscreen SwiftUI image.
final class TaskbarNativeContentView: NSView {
    let hosting: NSView

    init(hosting: NSView) {
        self.hosting = hosting
        super.init(frame: hosting.frame)
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    required init?(coder: NSCoder) { nil }

    func attachGlass(_ glass: NSView) {
        guard glass.superview !== self else { return }
        addSubview(glass, positioned: .below, relativeTo: hosting)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// SwiftUI only places this invisible anchor. AppKit owns the actual glass rendering.
final class TaskbarGlassAnchorView: NSView {
    private var glass: NSView
    private var experimentalAppearance: Bool?

    private static func makeGlass() -> NSView {
        if #available(macOS 26, *) {
            let effect = NSGlassEffectView(frame: .zero)
            effect.style = .clear
            return effect
        } else {
            let effect = NSVisualEffectView(frame: .zero)
            effect.material = .popover
            effect.state = .active
            effect.blendingMode = .behindWindow
            effect.wantsLayer = true
            effect.layer?.masksToBounds = true
            return effect
        }
    }

    override init(frame: NSRect) {
        glass = Self.makeGlass()
        super.init(frame: frame)
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(cornerRadius: CGFloat, opacity: Double, experimental: Bool, clarity: Double = 1) {
        TaskbarExperimentalGlass.synchronizePreferenceIsolation()
        if experimentalAppearance != experimental {
            detachGlass()
            glass = Self.makeGlass()
            experimentalAppearance = experimental
        }
        if #available(macOS 26, *), let effect = glass as? NSGlassEffectView {
            effect.cornerRadius = cornerRadius
            effect.tintColor = nil
        } else {
            glass.layer?.cornerRadius = cornerRadius
        }
        glass.alphaValue = CGFloat(min(1, max(0, opacity)))
        synchronizeGlass()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        synchronizeGlass()
    }

    override func layout() {
        super.layout()
        synchronizeGlass()
    }

    func detachGlass() { glass.removeFromSuperview() }

    private func synchronizeGlass() {
        guard let root = window?.contentView as? TaskbarNativeContentView else {
            detachGlass()
            return
        }
        root.attachGlass(glass)
        glass.frame = convert(bounds, to: root)
        glass.isHidden = isHiddenOrHasHiddenAncestor || bounds.isEmpty
    }
}
