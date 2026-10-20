import AppKit

enum TileBrand {
    static let image = NSImage(contentsOf: Bundle.module.url(forResource: "TileLogo", withExtension: "png")!)!

    // The supplied artwork is a wide poster. Show its central mark at toolbar size.
    static let markRect = NSRect(x: 475, y: 275, width: 460, height: 460)

    static let appIcon: NSImage = {
        let icon = NSImage(size: NSSize(width: 512, height: 512))
        icon.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 512, height: 512), xRadius: 110, yRadius: 110).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 512, height: 512), xRadius: 110, yRadius: 110).addClip()
        image.draw(in: NSRect(x: 20, y: 20, width: 472, height: 472), from: markRect, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        icon.unlockFocus()
        return icon
    }()
}

final class TileBrandView: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 76, height: 36) }

    override func draw(_ dirtyRect: NSRect) {
        let icon = NSRect(x: 1, y: 1, width: 34, height: 34)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: icon, xRadius: 5, yRadius: 5).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: icon, xRadius: 5, yRadius: 5).addClip()
        TileBrand.image.draw(in: icon, from: TileBrand.markRect, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        "Tile".draw(at: NSPoint(x: 42, y: 9), withAttributes: attributes)
    }
}
