import AppKit
import Carbon.HIToolbox

/// Covers every display with solid chroma green, for keying screen content in later.
/// Toggle with ⌃⌥G (global) or the menu; Esc also turns it off.
@MainActor
final class GreenScreen: ObservableObject {
    static let shared = GreenScreen()

    enum Shade: String, CaseIterable, Identifiable {
        case pure = "00FF00", chroma = "00B140"
        var id: String { rawValue }
        var label: String { self == .pure ? "Pure Green #00FF00" : "Chroma Green #00B140" }
        var color: NSColor {
            let v = Int(rawValue, radix: 16)!
            return NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
    }

    @Published private(set) var isOn = false
    @Published var shade: Shade {
        didSet {
            UserDefaults.standard.set(shade.rawValue, forKey: "greenShade")
            windows.forEach { $0.backgroundColor = shade.color }
        }
    }

    private var windows: [NSWindow] = []

    init() {
        shade = UserDefaults.standard.string(forKey: "greenShade").flatMap(Shade.init) ?? .pure
    }

    func toggle() { isOn ? hide() : show() }

    func show() {
        guard !isOn else { return }
        for screen in NSScreen.screens {
            let w = GreenWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver  // above the menu bar and the Dock
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.backgroundColor = shade.color
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
        NSApp.activate()
        windows.first?.makeKey()
        NSCursor.hide()
        isOn = true
    }

    func hide() {
        guard isOn else { return }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.unhide()
        isOn = false
    }
}

private final class GreenWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { GreenScreen.shared.hide() } else { super.keyDown(with: event) }
    }
}

/// One system-wide hotkey via Carbon — needs no Accessibility permission.
enum HotKey {
    private static var action: (() -> Void)?
    private static var ref: EventHotKeyRef?

    static func register(keyCode: Int, modifiers: Int, _ handler: @escaping () -> Void) {
        action = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKey.action?()
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x5349_5252), id: 1)  // 'SIRR'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
    }
}
