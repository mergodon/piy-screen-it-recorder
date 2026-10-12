import AppKit
import Combine

/// Shows a red ripple at each mouse click, on a transparent window above everything, so the
/// recording shows it. The ripple can last many seconds: a recording sped up 10× in FCP needs a
/// 10 s ripple to show a 1 s one. Mouse monitors need no Accessibility permission.
@MainActor
final class ClickHighlight: ObservableObject {
    static let shared = ClickHighlight()

    /// Prompt It Yourself red (`--red` on promptityourself.com).
    static let red = NSColor(srgbRed: 0xE2 / 255, green: 0x34 / 255, blue: 0x2B / 255, alpha: 1)
    static let durations = [1, 2, 3, 5, 10, 15, 20, 30]

    enum Mode: String, CaseIterable, Identifiable {
        case off, recording, always
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: "Off"
            case .recording: "While recording"
            case .always: "Always"
            }
        }
    }

    enum Size: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        /// The ripple's final radius, in points.
        var radius: CGFloat {
            switch self {
            case .small: 30
            case .medium: 50
            case .large: 80
            }
        }
    }

    @Published var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "clickMode"); update() }
    }
    /// Seconds one ripple lasts.
    @Published var duration: Int {
        didSet { UserDefaults.standard.set(duration, forKey: "clickDuration") }
    }
    @Published var size: Size {
        didSet { UserDefaults.standard.set(size.rawValue, forKey: "clickSize") }
    }

    private var windows: [NSWindow] = []
    private var monitors: [Any] = []
    private var watchers: [AnyCancellable] = []

    init() {
        let d = UserDefaults.standard
        mode = d.string(forKey: "clickMode").flatMap(Mode.init) ?? .recording
        duration = d.object(forKey: "clickDuration") as? Int ?? 1
        size = d.string(forKey: "clickSize").flatMap(Size.init) ?? .medium
        // Started by the app at launch; follows the recording state and display changes.
        watchers.append(Recorder.shared.$isRecording.sink { [weak self] recording in
            Task { @MainActor in self?.update(recording: recording) }
        })
        watchers.append(NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.rebuildWindows() } })
    }

    private var isActive: Bool { !monitors.isEmpty }

    private func update(recording: Bool? = nil) {
        let on = mode == .always || mode == .recording && (recording ?? Recorder.shared.isRecording)
        guard on != isActive else { return }
        if on {
            rebuildWindows()
            let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            // Global: clicks in other apps. Local: clicks in this app (the menu, Settings).
            if let m = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { _ in
                MainActor.assumeIsolated { ClickHighlight.shared.ripple(at: NSEvent.mouseLocation) }
            }) { monitors.append(m) }
            if let m = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { event in
                MainActor.assumeIsolated { ClickHighlight.shared.ripple(at: NSEvent.mouseLocation) }
                return event
            }) { monitors.append(m) }
        } else {
            monitors.forEach(NSEvent.removeMonitor)
            monitors.removeAll()
            windows.forEach { $0.orderOut(nil) }
            windows.removeAll()
        }
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        guard mode == .always || mode == .recording && Recorder.shared.isRecording else { return }
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            // Above the colour screen and Playback, which use .screenSaver.
            w.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.contentView?.wantsLayer = true
            w.setFrame(screen.frame, display: false)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    /// One ripple at a point in global screen coordinates (origin bottom left).
    func ripple(at point: NSPoint) {
        guard let window = windows.first(where: { NSMouseInRect(point, $0.frame, false) }),
              let host = window.contentView?.layer else { return }
        let r = size.radius
        let ring = CAShapeLayer()
        ring.frame = CGRect(x: point.x - window.frame.minX - r, y: point.y - window.frame.minY - r,
                            width: 2 * r, height: 2 * r)
        ring.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r).insetBy(dx: 2, dy: 2), transform: nil)
        ring.fillColor = Self.red.withAlphaComponent(0.3).cgColor
        ring.strokeColor = Self.red.cgColor
        ring.lineWidth = max(3, r / 12)
        ring.opacity = 0

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.2
        grow.toValue = 1
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = CFTimeInterval(duration)

        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "ripple")
        host.addSublayer(ring)
        CATransaction.commit()
    }
}
