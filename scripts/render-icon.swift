import AppKit

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
guard let image = NSImage(contentsOf: source) else { fatalError("Could not load Tile logo") }
let mark = NSRect(x: 475, y: 275, width: 460, height: 460)
for (name, size) in [("icon_16x16", 16), ("icon_16x16@2x", 32),
                     ("icon_32x32", 32), ("icon_32x32@2x", 64),
                     ("icon_128x128", 128), ("icon_128x128@2x", 256),
                     ("icon_256x256", 256), ("icon_256x256@2x", 512),
                     ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let canvas = NSImage(size: NSSize(width: size, height: size))
    canvas.lockFocus()
    NSColor.white.setFill()
    let inset = CGFloat(size) * 0.04
    let radius = CGFloat(size) * 0.215
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
    image.draw(in: bounds.insetBy(dx: inset, dy: inset), from: mark, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    canvas.unlockFocus()
    guard let tiff = canvas.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render icon") }
    try png.write(to: destination.appendingPathComponent("\(name).png"))
}
