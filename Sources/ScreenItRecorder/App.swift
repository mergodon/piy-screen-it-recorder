import AppKit
import SwiftUI

@main
struct ScreenItRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var rec = Recorder.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(rec)
        } label: {
            Image(nsImage: Logo.menuBar(recording: rec.isRecording))
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        // `--test <seconds>`: record, stop, quit — a headless smoke test.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--test"), i + 1 < args.count, let secs = Double(args[i + 1]) {
            Task { @MainActor in
                let rec = Recorder.shared
                await rec.start()
                print(rec.status)
                try? await Task.sleep(for: .seconds(secs))
                await rec.stop()
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

    var body: some View {
        Text(rec.status)
        Button(rec.isRecording ? "Stop Recording" : "Start Recording") {
            Task { rec.isRecording ? await rec.stop() : await rec.start() }
        }
        .keyboardShortcut("r")
        Divider()
        Picker("Microphone", selection: $rec.micID) {
            Text("None").tag(String?.none)
            ForEach(rec.mics, id: \.uniqueID) { Text($0.localizedName).tag(Optional($0.uniqueID)) }
        }
        .disabled(rec.isRecording)
        Toggle("Hide Desktop Widgets While Recording", isOn: $rec.hideWidgets)
            .disabled(rec.isRecording)
        Button("Open Recordings Folder") { rec.openFolder() }
        Divider()
        Button("Quit ScreenItRecorder") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
