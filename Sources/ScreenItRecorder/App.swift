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

        if CommandLine.arguments.contains("--settings") { MainActor.assumeIsolated { SettingsWindow.show() } }

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

    // Never leave the displays dimmed by the green screen.
    func applicationWillTerminate(_ note: Notification) {
        MainActor.assumeIsolated { GreenScreen.shared.hide() }
    }
}

struct MenuView: View {
    @EnvironmentObject var rec: Recorder
    @EnvironmentObject var green: GreenScreen

    var body: some View {
        Text(rec.status)
        if !Permission.allGranted {
            Button("⚠︎ Permissions Needed…") { SettingsWindow.show() }
        }
        Button(rec.isRecording ? "Stop Recording (⌃⌥⇧R)" : "Start Recording (⌃⌥⇧R)") {
            Task { rec.isRecording ? await rec.stop() : await rec.start() }
        }
        Button(green.isOn ? "\(green.shade.family) Screen Off (⌃⌥G / Esc)" : "\(green.shade.family) Screen On (⌃⌥G)") {
            green.toggle()
        }
        Divider()
        Button("Settings…") { SettingsWindow.show() }
            .keyboardShortcut(",")
        Button("Open Recordings Folder") { rec.openFolder() }
        Divider()
        Button("Quit ScreenItRecorder") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
