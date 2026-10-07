import AppKit
import SwiftUI

@main
struct FavoriteDragSelfTest {
    @MainActor static func main() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
        }
        var state = FavoriteDragRemovalState()
        check(FavoriteDragRemovalState.delay == 0.5, "Removal dwell is half a second")
        check(!state.isReady(now: 100), "Idle cannot remove")
        state.update(isOutside: true, now: 100)
        state.update(isOutside: true, now: 100.25)
        check(!state.isReady(now: 100.499), "Do not remove early")
        check(state.isReady(now: 100.5), "Arm removal at 0.5 seconds even without movement")
        check(!state.shouldRemove(onReleaseOutside: false, now: 100.6), "An armed item returned inside must remain")
        check(state.shouldRemove(onReleaseOutside: true, now: 100.6), "Only release outside commits removal")
        state.update(isOutside: false, now: 100.4)
        check(!state.isReady(now: 200), "Returning cancels removal")
        state.update(isOutside: true, now: 200)
        check(!state.isReady(now: 200.49), "Re-exit starts a new continuous dwell")
        state.cancel()
        check(!state.isReady(now: 300), "Release and escape cancel")

        let middle = FavoriteShelfInsertion.target(pointerX: 64, appTotal: 4, folderTotal: 2,
            hasUtilities: true, incomingApps: 1, incomingFolders: 0, preview: nil)
        check(middle.appIndex == 2 && middle.appCount == 1, "App opens an insertion gap at cursor")
        let steady = FavoriteShelfInsertion.target(pointerX: 80, appTotal: 4, folderTotal: 2,
            hasUtilities: true, incomingApps: 1, incomingFolders: 0, preview: middle)
        check(steady == middle, "Pointer within expanded gap must not oscillate insertion")
        let folderInsertion = FavoriteShelfInsertion.target(pointerX: 164, appTotal: 4, folderTotal: 2,
            hasUtilities: true, incomingApps: 0, incomingFolders: 1, preview: nil)
        check(folderInsertion.folderIndex == 1 && folderInsertion.appCount == 0, "Folder opens gap within folder section")
        let end = FavoriteShelfInsertion.target(pointerX: 1000, appTotal: 4, folderTotal: 2,
            hasUtilities: true, incomingApps: 1, incomingFolders: 1, preview: nil)
        check(end.appIndex == 4 && end.folderIndex == 2, "Both section targets are clamped")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("ordinary.txt")
        try Data("keep original".utf8).write(to: file)
        let app = root.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "test.taskdock.drag", "CFBundleName": "Example",
                                   "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let invalidApp = root.appendingPathComponent("Invalid.app")
        try FileManager.default.createDirectory(at: invalidApp, withIntermediateDirectories: true)
        let symlink = root.appendingPathComponent("Folder link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: folder)
        let accepted = FavoriteShelfDrop.supportedURLs([app, folder, file, invalidApp, symlink, folder,
            root.appendingPathComponent("missing"), URL(string: "https://example.com")!])
        check(accepted.map(\.path) == [app, folder].map { $0.resolvingSymlinksInPath().path },
              "Accept App and folder; reject files, invalid App, duplicates and remote URLs: \(accepted)")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        check(pasteboard.writeObjects([app as NSURL, folder as NSURL, file as NSURL]), "Write Finder file URL objects")
        let pasted = pasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        check(FavoriteShelfDrop.supportedURLs(pasted).map(\.path) == accepted.map(\.path),
              "Native file URL pasteboard bridges and classifies both App and folder")
        let originalContents = try String(contentsOf: file, encoding: .utf8)
        check(originalContents == "keep original", "Drop parsing preserves files")

        // Exercise native capture: clicks, reordering, drag-out early release, Escape, and fixed utilities.
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let view = FavoriteShelfInteractionView.TrackingView(frame: NSRect(x: 0, y: 0, width: 240, height: 42))
        window.contentView?.addSubview(view)
        view.shelfInset = 40
        view.shelfWidth = 100
        view.itemAt = { point in
            if (50...80).contains(point.x) { return "app" }
            if (130...150).contains(point.x) { return "trash" }
            return nil
        }
        view.canDragItem = { $0 == "app" }
        check(view.hitTest(NSPoint(x: 180, y: 20)) == nil,
            "An empty overflow area must pass clicks to adjacent task items")
        check(view.hitTest(NSPoint(x: 140, y: 20)) === view,
            "An icon covering the adjacent lane must still receive the click")
        var clicks = [String]()
        var updates = [(String, CGSize, Bool, CGFloat)]()
        var endings = [Bool]()
        var removals = [String]()
        view.onClick = { clicks.append($0) }
        view.onDragUpdate = { updates.append(($0, $1, $2, $3)) }
        view.onDragEnd = { endings.append($0) }
        view.onRemove = { removals.append($0) }
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, 60, 20))
        view.mouseUp(with: event(.leftMouseUp, 60, 20))
        check(clicks == ["app"], "A click still opens the correct item")
        view.mouseDown(with: event(.leftMouseDown, 60, 20))
        view.mouseDragged(with: event(.leftMouseDragged, 90, 20))
        view.mouseUp(with: event(.leftMouseUp, 120, 20))
        check(updates.last?.2 == false && endings == [false] && clicks.count == 1, "Reordering must not launch")
        check(updates.last?.3 == 120, "Release uses its final pointer position even after a fast jump")
        view.mouseDown(with: event(.leftMouseDown, 60, 20))
        let beforeBurst = updates.count
        for x in stride(from: CGFloat(90), through: 150, by: 5) {
            view.mouseDragged(with: event(.leftMouseDragged, x, 20))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        check(updates.last?.3 == 150 && updates.count - beforeBurst < 13,
              "Rapid mouse events coalesce to the latest visible drag position")
        view.mouseDragged(with: event(.leftMouseDragged, 155, 20))
        view.mouseUp(with: event(.leftMouseUp, 160, 20))
        let afterBurstRelease = updates.count
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        check(updates.last?.3 == 160 && updates.count == afterBurstRelease,
              "Mouse-up uses the final position and cancels queued stale updates")
        view.mouseDown(with: event(.leftMouseDown, 60, 20))
        view.mouseDragged(with: event(.leftMouseDragged, 60, 100))
        view.mouseUp(with: event(.leftMouseUp, 60, 100))
        check(updates.last?.2 == true && endings.last == true && removals.isEmpty, "Early release outside cancels")
        view.mouseDown(with: event(.leftMouseDown, 60, 20))
        view.mouseDragged(with: event(.leftMouseDragged, 90, 20))
        view.cancelInteraction()
        check(endings.last == true && removals.isEmpty, "Cancellation restores source")
        view.iconCenterForItem = { _ in CGPoint(x: 56, y: 20) }
        view.mouseDown(with: event(.leftMouseDown, 60, 20))
        view.mouseDragged(with: event(.leftMouseDragged, 60, 100))
        let beforeReturn = updates.count
        view.mouseDragged(with: event(.leftMouseDragged, 100, 20))
        check(updates.count == beforeReturn + 1 && updates.last?.2 == false,
              "Returning inside updates the shelf icon in the crossing event")
        view.mouseUp(with: event(.leftMouseUp, 100, 20))
        let afterReturn = updates.count
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        check(updates.count == afterReturn,
              "A queued outside update must not hide the icon after return")
        let count = updates.count
        view.mouseDown(with: event(.leftMouseDown, 140, 20))
        view.mouseDragged(with: event(.leftMouseDragged, 140, 100))
        view.mouseUp(with: event(.leftMouseUp, 140, 20))
        check(updates.count == count && clicks.last == "trash", "Trash remains fixed and clickable")
        view.mouseDown(with: event(.leftMouseDown, 60, 20))
        view.mouseDragged(with: event(.leftMouseDragged, 60, 100))
        RunLoop.main.run(until: Date().addingTimeInterval(0.65))
        check(removals.isEmpty, "Holding outside beyond 0.5 seconds must never remove")
        view.mouseUp(with: event(.leftMouseUp, 60, 100))
        check(removals == ["app"], "Release outside after the dwell removes once")
        view.mouseDown(with: event(.leftMouseDown, 60, 20))
        view.mouseDragged(with: event(.leftMouseDragged, 60, 100))
        RunLoop.main.run(until: Date().addingTimeInterval(0.65))
        view.mouseDragged(with: event(.leftMouseDragged, 90, 20))
        view.mouseUp(with: event(.leftMouseUp, 90, 20))
        check(removals.count == 1, "Returning after the dwell cancels the armed removal")
        let drag = TestDraggingInfo(pasteboard: pasteboard, window: window)
        var previewX: CGFloat?
        var droppedCount = 0
        var externalActivity = [Bool]()
        view.onDropPreview = { urls, x in previewX = x; return urls.count == 2 }
        view.onDropURLs = { urls, x in droppedCount = urls.count; return x == previewX }
        view.onExternalDragChanged = { externalActivity.append($0) }
        check(view.draggingEntered(drag) == .copy && previewX == 80, "Native drop hover reserves the cursor's slot")
        check(view.prepareForDragOperation(drag) && view.performDragOperation(drag), "Native App and folder drop commits")
        check(droppedCount == 2 && externalActivity.last == false, "Drop completion clears preview activity")
        view.onDropPreview = { _, _ in false }
        check(view.draggingUpdated(drag).isEmpty, "Duplicate-only or rejected drop never opens a gap")
        var hoverLocations = [CGPoint?]()
        view.onLocationChange = { hoverLocations.append($0) }
        view.mouseMoved(with: event(.mouseMoved, 140, 20))
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        check(hoverLocations.last!?.x == 140, "Trash slot remains a hover target")
        view.mouseMoved(with: event(.mouseMoved, 225, 20))
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        check(hoverLocations.last! == nil, "Empty right animation clearance does not magnify")
        view.itemAt = { point in (210...230).contains(point.x) ? "trash" : nil }
        view.mouseMoved(with: event(.mouseMoved, 220, 20))
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        check(hoverLocations.last!?.x == 220, "Actual expanded icon remains reachable past its idle slot")
        print("FAVORITE_DRAG_OK: dwell boundaries, reset, URL classification, preservation, native capture and cancellation")
    }
}

@MainActor
final class TestDraggingInfo: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation = NSPoint(x: 120, y: 20)
    var draggedImageLocation: NSPoint { draggingLocation }
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard: NSPasteboard
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 2
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(pasteboard: NSPasteboard, window: NSWindow) {
        draggingPasteboard = pasteboard
        draggingDestinationWindow = window
        super.init()
    }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
        classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
