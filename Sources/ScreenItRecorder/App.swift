import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct ScreenItRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var rec = Recorder.shared
    @StateObject private var green = GreenScreen.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(rec).environmentObject(green)
        } label: {
            Image(nsImage: Logo.menuBar(recording: rec.isRecording))
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        HotKey.register(keyCode: kVK_ANSI_G, modifiers: controlKey | optionKey) {
            Task { @MainActor in GreenScreen.shared.toggle() }
        }
        // ⌃⌥R is FCP's Retime → Custom Speed; ⌃⌥⇧R is free there.
        HotKey.register(keyCode: kVK_ANSI_R, modifiers: controlKey | optionKey | shiftKey) {
            Task { @MainActor in
                let rec = Recorder.shared
                rec.isRecording ? await rec.stop() : await rec.start()
            }
        }

        // `--test <seconds> [--green]`: record (optionally over green), stop, quit — a headless smoke test.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--test"), i + 1 < args.count, let secs = Double(args[i + 1]) {
            Task { @MainActor in
                let rec = Recorder.shared
                if args.contains("--green") { GreenScreen.shared.show() }
                await rec.start()
                print(rec.status)
                try? await Task.sleep(for: .seconds(secs))
                await rec.stop()
                GreenScreen.shared.hide()
                print(rec.status)
                exit(rec.lastError == nil ? 0 : 1)
            }
        }
    }

    // Quitting (or logging out) mid-recording finalises the files first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Recorder.shared.isRecording else { return .terminateNow }
        Task { @MainActor in
            await Recorder.shared.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct MenuView: View {
    @EnvironmentObject var rec: Recorder
    @EnvironmentObject var green: GreenScreen

    var body: some View {
        Text(rec.status)
        Button(rec.isRecording ? "Stop Recording (⌃⌥⇧R)" : "Start Recording (⌃⌥⇧R)") {
            Task { rec.isRecording ? await rec.stop() : await rec.start() }
        }
        Divider()
        Picker("Microphone", selection: $rec.micID) {
            Text("None").tag(String?.none)
            ForEach(rec.mics, id: \.uniqueID) { Text($0.localizedName).tag(Optional($0.uniqueID)) }
        }
        .disabled(rec.isRecording)
        Picker("Camera", selection: $rec.cameraID) {
            let cams = CameraRecorder.devices
            let labels = CameraRecorder.labels(for: cams)
            Text("None").tag(String?.none)
            ForEach(cams, id: \.uniqueID) { Text(labels[$0.uniqueID]!).tag(Optional($0.uniqueID)) }
        }
        .disabled(rec.isRecording)
        if let cameraID = rec.cameraID {
            Picker("Camera Frame Rate", selection: $rec.cameraFPS) {
                ForEach(CameraRecorder.rates(cameraID: cameraID), id: \.self) { fps in
                    Text(fps == Int(Recorder.fps) ? "\(fps) fps (matches screens)" : "\(fps) fps").tag(fps)
                }
            }
            .disabled(rec.isRecording)
        }
        Toggle("Hide Desktop Widgets While Recording", isOn: $rec.hideWidgets)
            .disabled(rec.isRecording)
        Divider()
        Button(green.isOn ? "Green Screen Off (⌃⌥G / Esc)" : "Green Screen On (⌃⌥G)") { green.toggle() }
        Picker("Green", selection: $green.shade) {
            ForEach(GreenScreen.Shade.allCases) { Text($0.label).tag($0) }
        }
        Divider()
        Button("Open Recordings Folder") { rec.openFolder() }
        Divider()
        Button("Quit ScreenItRecorder") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
