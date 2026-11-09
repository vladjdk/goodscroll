import AppKit

/// The menu bar version of the logo: a little paper scroll with one highlighted line.
/// Drawn in code as a template image so it tints with the menu bar like any system icon.
enum ScrollGlyph {
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            // Rollers
            NSBezierPath(roundedRect: NSRect(x: 2, y: 1.5, width: 14, height: 3.2), xRadius: 1.6, yRadius: 1.6).fill()
            NSBezierPath(roundedRect: NSRect(x: 2, y: 13.3, width: 14, height: 3.2), xRadius: 1.6, yRadius: 1.6).fill()
            // Paper edges
            let edges = NSBezierPath()
            edges.lineWidth = 1.3
            edges.move(to: NSPoint(x: 3.9, y: 4.5)); edges.line(to: NSPoint(x: 3.9, y: 13.5))
            edges.move(to: NSPoint(x: 14.1, y: 4.5)); edges.line(to: NSPoint(x: 14.1, y: 13.5))
            edges.stroke()
            // Text lines; the middle one is the line that "clicked", so it's bolder.
            NSBezierPath(roundedRect: NSRect(x: 6, y: 6.2, width: 6, height: 1.2), xRadius: 0.6, yRadius: 0.6).fill()
            NSBezierPath(roundedRect: NSRect(x: 5.2, y: 8.1, width: 7.6, height: 2.2), xRadius: 1.1, yRadius: 1.1).fill()
            NSBezierPath(roundedRect: NSRect(x: 6, y: 11, width: 4.5, height: 1.2), xRadius: 0.6, yRadius: 0.6).fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "GoodScroll"
        return img
    }()
}
