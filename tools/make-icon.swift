// Renders the S|R app icon to a 1024px PNG. Usage: swift tools/make-icon.swift <out.png>
import AppKit

let out = CommandLine.arguments[1]
let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824px rounded square centred on a 1024 canvas.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
NSGradient(starting: NSColor(white: 0.16, alpha: 1), ending: NSColor(white: 0.05, alpha: 1))!
    .draw(in: NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185), angle: -90)

let font = NSFont.systemFont(ofSize: 330, weight: .black)
func part(_ s: String, _ color: NSColor) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
}
let mark = NSMutableAttributedString()
mark.append(part("S", .white))
mark.append(part("|", .systemRed))
mark.append(part("R", .white))
let size = mark.size()
mark.draw(at: NSPoint(x: tile.midX - size.width / 2, y: tile.midY - size.height / 2))

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(filePath: out))
