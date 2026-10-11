import AppKit

/// The S|R mark, drawn in code so the menu bar and app icon stay in step.
enum Logo {
    static func menuBar(recording: Bool) -> NSImage {
        let text = "S|R" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .heavy),
            .foregroundColor: recording ? NSColor.systemRed : NSColor.black,
        ]
        let size = text.size(withAttributes: attrs)
        let image = NSImage(size: NSSize(width: ceil(size.width) + 2, height: 18), flipped: false) { rect in
            text.draw(at: NSPoint(x: 1, y: (rect.height - size.height) / 2), withAttributes: attrs)
            return true
        }
        image.isTemplate = !recording  // red while recording, otherwise follows the menu bar
        return image
    }
}
