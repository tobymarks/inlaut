// Render the installer artwork at 1x and 2x using the supplied brand master.
// Run from the repository root: swift scripts/render-dmg-background.swift OUTPUT_DIRECTORY
import AppKit

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift scripts/render-dmg-background.swift OUTPUT_DIRECTORY")
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
guard let logo = NSImage(contentsOfFile: "design/inlaut-brand-kit/logo/inlaut-logo-petrol-880.png") else {
    fatalError("The supplied inlaut wordmark is missing; run from the repository root.")
}

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
let petrol = color(0x103D3B)
let accent = color(0x236E64)

for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 660 * scale,
                                  pixelsHigh: 430 * scale, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: 660, height: 430)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    // bitmap.size already makes AppKit use the correct backing scale. Applying
    // another scale here would crop and enlarge the Retina representation.
    color(0xF6F7F4).setFill()
    NSRect(x: 0, y: 0, width: 660, height: 430).fill()

    // Coordinates below use the same top-left origin as the Finder layout.
    func label(_ text: String, x: CGFloat, top: CGFloat, width: CGFloat,
               size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        (text as NSString).draw(in: NSRect(x: x, y: 430 - top - 34, width: width, height: 34),
            withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                             .foregroundColor: color])
    }
    logo.draw(in: NSRect(x: 40, y: 430 - 38 - 38, width: 160, height: 38))
    label("inlaut installieren", x: 40, top: 106, width: 580, size: 27, weight: .semibold, color: petrol)
    label("Ziehe inlaut in den Ordner „Programme“.", x: 40, top: 151,
          width: 580, size: 16, weight: .regular, color: petrol)

    let arrow = NSBezierPath()
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 296, y: 430 - 252))
    arrow.line(to: NSPoint(x: 364, y: 430 - 252))
    arrow.move(to: NSPoint(x: 352, y: 430 - 240))
    arrow.line(to: NSPoint(x: 364, y: 430 - 252))
    arrow.line(to: NSPoint(x: 352, y: 430 - 264))
    accent.setStroke()
    arrow.stroke()

    color(0xD9E3DD).setFill()
    NSRect(x: 40, y: 430 - 354, width: 580, height: 1).fill()
    label("Danach inlaut aus „Programme“ öffnen.", x: 40, top: 376,
          width: 580, size: 14, weight: .regular, color: accent)
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 1 ? "" : "@2x"
    try bitmap.representation(using: .png, properties: [:])!.write(
        to: output.appendingPathComponent("background\(suffix).png"))
}
