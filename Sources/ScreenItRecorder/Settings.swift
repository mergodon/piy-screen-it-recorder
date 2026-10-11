import AVFoundation
import Combine
import AppKit
import SwiftUI

/// One AppKit-hosted window: opens reliably from a menu bar app, the hotkeys, or `--settings`.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Screen It Recorder Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()  // a menu bar app's window opens behind the front app otherwise
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var rec = Recorder.shared
    @ObservedObject private var green = GreenScreen.shared

    var body: some View {
        Form {
            Section("Recording") {
                Picker("Microphone", selection: $rec.micID) {
                    Text("None").tag(String?.none)
                    ForEach(rec.mics, id: \.uniqueID) { Text($0.localizedName).tag(Optional($0.uniqueID)) }
                }
                Picker("Camera", selection: $rec.cameraID) {
                    let cams = CameraRecorder.devices
                    let labels = CameraRecorder.labels(for: cams)
                    Text("None").tag(String?.none)
                    ForEach(cams, id: \.uniqueID) { Text(labels[$0.uniqueID]!).tag(Optional($0.uniqueID)) }
                }
                if let cameraID = rec.cameraID {
                    Picker("Camera frame rate", selection: $rec.cameraFPS) {
                        ForEach(CameraRecorder.rates(cameraID: cameraID), id: \.self) { fps in
                            Text(fps == Int(Recorder.fps) ? "\(fps) fps (matches screens)" : "\(fps) fps").tag(fps)
                        }
                    }
                }
                Toggle("Hide desktop widgets while recording", isOn: $rec.hideWidgets)
                LabeledContent("Saves to") {
                    VStack(alignment: .trailing) {
                        Text(rec.folder.path(percentEncoded: false)).textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                        HStack {
                            if rec.folder.standardizedFileURL != Recorder.defaultFolder.standardizedFileURL {
                                Button("Use Default") { rec.folder = Recorder.defaultFolder }
                            }
                            Button("Change…") { chooseFolder() }
                            Button("Open") { rec.openFolder() }
                        }
                    }
                }
            }
            .disabled(rec.isRecording)

            Section {
                Picker("Colour", selection: $green.shade) {
                    ForEach(GreenScreen.Shade.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Dim displays while the screen colour is on", isOn: $green.dim)
                LabeledContent("Display brightness") {
                    HStack {
                        Slider(value: $green.dimLevel, in: 0.1...1, step: 0.05)
                        Text("\(Int((green.dimLevel * 100).rounded()))%").monospacedDigit().frame(width: 40)
                    }
                }
                .disabled(!green.dim)
                Button("Preview \(green.shade.family) Screen") { green.show() }
            } header: {
                Text("Green / blue screen")
            } footer: {
                Text("Dimming changes only the backlight. The recording keeps the exact colour. "
                    + "Press ⌃⌥G or Esc to end the preview.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                LabeledContent("Start / stop recording", value: "⌃⌥⇧R")
                LabeledContent("Green / blue screen on / off", value: "⌃⌥G  (Esc also turns it off)")
            }

            PermissionsSection()

            AboutSection()
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension SettingsView {
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose where Screen It Recorder saves recordings"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = rec.folder
        if panel.runModal() == .OK, let url = panel.url { rec.folder = url }
    }
}

enum About {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    static let repo = URL(string: "https://github.com/promptityourself/piy-screen-it-recorder")!
    // The project page does not exist yet (promptityourself-web#116); point at it once live.
    static let site = URL(string: "https://promptityourself.com/projects/")!
    static let blurb = "Records every screen, and a camera if you want one, to separate files "
        + "with the same mic track, so Final Cut Pro can sync them."
    static let credit = "A Prompt It Yourself project. MIT licence. © 2026 Mergodon Limited."

    /// The standard About panel, with the blurb and links as credits.
    @MainActor static func showPanel() {
        let credits = NSMutableAttributedString(string: blurb + "\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor,
        ])
        for (title, url) in [("Prompt It Yourself", site), ("Source on GitHub", repo)] {
            credits.append(NSAttributedString(string: title, attributes: [.link: url, .font: NSFont.systemFont(ofSize: 11)]))
            credits.append(NSAttributedString(string: "   "))
        }
        credits.append(NSAttributedString(string: "\n\n" + credit, attributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        credits.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: credits.length))
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

private struct AboutSection: View {
    var body: some View {
        Section("About") {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screen It Recorder").font(.headline)
                    Text("Version \(About.version)").foregroundStyle(.secondary)
                    Text(About.blurb).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        Link("Prompt It Yourself", destination: About.site)
                        Link("Source on GitHub", destination: About.repo)
                    }
                    Text(About.credit).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

enum Permission: String, CaseIterable, Identifiable {
    case screen = "Screen Recording", camera = "Camera", microphone = "Microphone"
    var id: String { rawValue }

    /// true = allowed, false = denied, nil = not asked yet.
    var granted: Bool? {
        switch self {
        case .screen: CGPreflightScreenCaptureAccess() ? true : false
        case .camera: Self.status(.video)
        case .microphone: Self.status(.audio)
        }
    }

    @MainActor static var allGranted: Bool { allCases.allSatisfy { $0 == .camera && Recorder.shared.cameraID == nil || $0.granted == true } }

    func request() async {
        switch self {
        case .screen:
            if !CGRequestScreenCaptureAccess() { openSettings() }
        case .camera, .microphone:
            let type: AVMediaType = self == .camera ? .video : .audio
            if granted == nil { _ = await AVCaptureDevice.requestAccess(for: type) } else { openSettings() }
        }
    }

    func openSettings() {
        let anchor = switch self {
        case .screen: "Privacy_ScreenCapture"
        case .camera: "Privacy_Camera"
        case .microphone: "Privacy_Microphone"
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }

    private static func status(_ type: AVMediaType) -> Bool? {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: true
        case .notDetermined: nil
        default: false
        }
    }
}

/// Ticks every 2 s while the Settings window is open, so permission rows re-read their status.
/// (An ObservableObject, not @State: SwiftUI's macros need Xcode, and we build with the CLT.)
private final class Ticker: ObservableObject {
    @Published var tick = 0
    private var timer: AnyCancellable?
    init() { timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick += 1 } }
}

private struct PermissionsSection: View {
    @StateObject private var ticker = Ticker()

    var body: some View {
        Section {
            let _ = ticker.tick
            ForEach(Permission.allCases) { p in
                let granted = p.granted
                LabeledContent {
                    if granted != true {
                        Button(granted == nil ? "Allow…" : "Open System Settings") { Task { await p.request() } }
                    }
                } label: {
                    Label {
                        Text(p.rawValue)
                    } icon: {
                        Image(systemName: granted == true ? "checkmark.circle.fill"
                              : granted == false ? "xmark.circle.fill" : "questionmark.circle")
                            .foregroundStyle(granted == true ? .green : granted == false ? .red : .secondary)
                    }
                }
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("After you allow Screen Recording, quit and reopen Screen It Recorder.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
