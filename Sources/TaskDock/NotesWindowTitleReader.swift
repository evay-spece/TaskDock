import ApplicationServices
import Foundation

/// Reads only the selected note editor in this window; skips the sidebar/list.
final class NotesWindowTitleReader {
    func title(in window: AXUIElement) -> String? {
        let deadline = Date().addingTimeInterval(0.08)
        var remaining = 40
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            guard Date() < deadline else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.025)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        func visit(_ element: AXUIElement, depth: Int) -> String? {
            guard depth <= 8, remaining > 0, Date() < deadline else { return nil }
            remaining -= 1
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            if role == kAXTextAreaRole {
                // Distinguish the note editor from search fields and other text areas.
                let identifier = attribute(element, kAXIdentifierAttribute) as? String ?? ""
                guard identifier.hasPrefix("Note[") else { return nil }
                return (attribute(element, kAXValueAttribute) as? String)
                    .flatMap(WindowDisplayTitle.noteTitle(from:))
            }
            guard ![kAXTableRole, kAXOutlineRole, kAXToolbarRole, kAXRowRole].contains(role),
                  let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
            // The editor is normally the rightmost child in Notes' split view.
            for child in children.reversed() {
                if let title = visit(child, depth: depth + 1) { return title }
            }
            return nil
        }
        return visit(window, depth: 0)
    }
}
