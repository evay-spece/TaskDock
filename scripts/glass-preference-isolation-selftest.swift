import AppKit

// Compile alongside TaskbarNativeGlass.swift (copy this file to main.swift).
// A temporary defaults suite stands in for the inherited system preference;
// no global defaults or TaskDock preferences are changed.
let defaults = UserDefaults.standard
let suiteName = "TaskDockGlassSelftest.\(UUID().uuidString)"
let suite = UserDefaults(suiteName: suiteName)!
defaults.addSuite(named: suiteName)
defer {
    defaults.removeSuite(named: suiteName)
    suite.removePersistentDomain(forName: suiteName)
}
suite.set(0.0, forKey: "NSGlassTintAmount")
var args = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
args[TaskbarExperimentalGlass.preferenceKey] = true
args[TaskbarExperimentalGlass.clarityKey] = 0.6
defaults.setVolatileDomain(args, forName: UserDefaults.argumentDomain)
TaskbarExperimentalGlass.installPreferenceIsolation()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let panel = TaskbarExperimentalGlass.makePanel()
(panel as? TaskbarAppearancePanel)?.permitsExperimentalGlass = true
panel.setFrame(NSRect(x: 100, y: 100, width: 400, height: 70), display: false)
let host = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 70))
let root = TaskbarNativeContentView(hosting: host)
panel.contentView = root
let anchor = TaskbarGlassAnchorView(frame: host.bounds)
host.addSubview(anchor)
panel.orderFrontRegardless()
func filterValues(_ layer: CALayer) -> [Double] {
    var result: [Double] = []
    for case let filter as NSObject in layer.filters ?? [] {
        if filter.responds(to: NSSelectorFromString("inputKeys")),
           let keys = filter.value(forKey: "inputKeys") as? [String],
           keys.contains("inputBlurFillNormalOpacity"),
           let value = filter.value(forKey: "inputBlurFillNormalOpacity") as? NSNumber {
            result.append(value.doubleValue)
        }
    }
    for sublayer in layer.sublayers ?? [] { result += filterValues(sublayer) }
    return result
}
func sample(manual: Bool) -> [Double] {
    var args = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
    args[TaskbarExperimentalGlass.preferenceKey] = manual
    defaults.setVolatileDomain(args, forName: UserDefaults.argumentDomain)
    TaskbarExperimentalGlass.synchronizePreferenceIsolation()
    anchor.configure(cornerRadius: 18, opacity: 1, experimental: manual, clarity: 0.6)
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    return filterValues(root.layer!)
}
let fixed = sample(manual: true)
assert(!fixed.isEmpty)
assert(abs(defaults.double(forKey: "NSGlassTintAmount") - 0.4) < 0.001)
suite.set(1.0, forKey: "NSGlassTintAmount")
assert(sample(manual: true) == fixed)
// Retired settings must never re-enable system following.
assert(sample(manual: false) == fixed)
assert(abs(defaults.double(forKey: "NSGlassTintAmount") - 0.4) < 0.001)
suite.set(0.0, forKey: "NSGlassTintAmount")
assert(sample(manual: false) == fixed)
var updated = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
updated[TaskbarExperimentalGlass.clarityKey] = 0.2
defaults.setVolatileDomain(updated, forName: UserDefaults.argumentDomain)
TaskbarExperimentalGlass.synchronizePreferenceIsolation()
assert(abs(defaults.double(forKey: "NSGlassTintAmount") - 0.8) < 0.001)
let frosted = sample(manual: false)
assert(frosted != fixed)
assert(!panel.isKeyWindow && !panel.isMainWindow)
assert(root.subviews.count == 2)
print("PASS: slider controls glass, inherited changes and retired toggle ignored, no duplicate layers or focus activation")
