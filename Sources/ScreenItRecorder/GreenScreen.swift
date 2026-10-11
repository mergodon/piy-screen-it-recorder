import AppKit
import Carbon.HIToolbox

/// Covers every display with a solid key colour (green or blue), for keying screen content in
/// later. Blue is for shots with green props in front of the screens (e.g. a green mic).
/// Toggle with ⌃⌥G (global) or the menu; Esc also turns it off. Optionally dims the
/// backlight meanwhile — full-brightness green floods the room; the file keeps the exact colour.
@MainActor
final class GreenScreen: ObservableObject {
    static let shared = GreenScreen()

    enum Shade: String, CaseIterable, Identifiable {
        case pure = "00FF00", chroma = "00B140", pureBlue = "0000FF", chromaBlue = "0047BB"
        var id: String { rawValue }
        var family: String { self == .pure || self == .chroma ? "Green" : "Blue" }
        var label: String {
            let kind = self == .pure || self == .pureBlue ? "Pure" : "Chroma"
            return "\(kind) \(family) #\(rawValue)"
        }
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

    @Published var dim: Bool {
        didSet { UserDefaults.standard.set(dim, forKey: "greenDim"); applyBacklight() }
    }
    /// Backlight level while green is on, 0.1–1.
    @Published var dimLevel: Double {
        didSet { UserDefaults.standard.set(dimLevel, forKey: "greenDimLevel"); applyBacklight() }
    }

    private var windows: [NSWindow] = []
    private var savedBacklight: [UInt32: Float] = [:]

    init() {
        let d = UserDefaults.standard
        shade = d.string(forKey: "greenShade").flatMap(Shade.init) ?? .pure
        dim = d.object(forKey: "greenDim") as? Bool ?? true
        dimLevel = d.object(forKey: "greenDimLevel") as? Double ?? 0.4
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
        applyBacklight()
    }

    func hide() {
        guard isOn else { return }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        NSCursor.unhide()
        isOn = false
        applyBacklight()
    }

    /// Dim each display (never brighten one already darker) while on; restore when off.
    private func applyBacklight() {
        guard isOn, dim else {
            savedBacklight.forEach { Backlight.set($0.key, $0.value) }
            savedBacklight.removeAll()
            return
        }
        for screen in NSScreen.screens {
            guard let id = Backlight.displayID(screen) else { continue }
            if savedBacklight[id] == nil { savedBacklight[id] = Backlight.get(id) }
            if let original = savedBacklight[id] { Backlight.set(id, min(original, Float(dimLevel))) }
        }
    }
}

private final class GreenWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { GreenScreen.shared.hide() } else { super.keyDown(with: event) }
    }
}

/// System-wide hotkeys via Carbon — need no Accessibility permission. A global hotkey takes
/// the key from every app, so check Final Cut Pro's Default.commandset before adding one.
enum HotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var refs: [EventHotKeyRef?] = []

    static func register(keyCode: Int, modifiers: Int, _ handler: @escaping () -> Void) {
        if actions.isEmpty {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                HotKey.actions[id.id]?()
                return noErr
            }, 1, &spec, nil, nil)
        }
        let id = EventHotKeyID(signature: OSType(0x5349_5252), id: UInt32(actions.count + 1))  // 'SIRR'
        actions[id.id] = handler
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }
}
