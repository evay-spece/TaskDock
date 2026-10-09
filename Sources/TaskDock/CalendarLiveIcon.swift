import AppKit

/// The Calendar app supplies a static bundle icon; its Dock tile is drawn by macOS separately.
/// Draw the date on TaskDock's own tile so it remains correct without launching Calendar.
enum CalendarLiveIcon {
    static func isCalendar(_ favorite: FavoriteApp) -> Bool {
        favorite.bundleIdentifier == "com.apple.iCal"
    }

    static func dayKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(calendar.timeZone.identifier)|\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    static func image(for date: Date) -> NSImage {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let day = calendar.component(.day, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let weekdayName = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][weekday - 1]
        let size = NSSize(width: 256, height: 256)

        return NSImage(size: size, flipped: false) { rect in
            let tile = NSRect(x: 17, y: 13, width: 222, height: 226)
            let shape = NSBezierPath(roundedRect: tile, xRadius: 42, yRadius: 42)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
            shadow.shadowBlurRadius = 11
            shadow.shadowOffset = NSSize(width: 0, height: -5)
            shadow.set()
            NSColor.white.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()

            let title = weekdayName as NSString
            let titleFont = NSFont.systemFont(ofSize: 50, weight: .bold)
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: NSColor.systemRed
            ]
            let titleSize = title.size(withAttributes: titleAttributes)
            title.draw(at: NSPoint(x: rect.midX - titleSize.width / 2, y: 167),
                       withAttributes: titleAttributes)

            let number = String(day) as NSString
            let numberFont = NSFont.systemFont(ofSize: 139, weight: .regular)
            let numberAttributes: [NSAttributedString.Key: Any] = [
                .font: numberFont,
                .foregroundColor: NSColor(calibratedWhite: 0.06, alpha: 1)
            ]
            let numberSize = number.size(withAttributes: numberAttributes)
            number.draw(at: NSPoint(x: rect.midX - numberSize.width / 2,
                                    y: day < 10 ? 25 : 31),
                        withAttributes: numberAttributes)
            return true
        }
    }
}
