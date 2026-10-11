import AppKit
import SwiftUI

@MainActor
enum PlaybackPanel {
    static func show() {
        if Playback.shared.followsLatest, !Playback.shared.isActive { Task { await Playback.shared.useLatest() } }
        HostedWindow.show("Screen It Recorder Playback", PlaybackView())
    }
}

struct PlaybackView: View {
    @ObservedObject private var play = Playback.shared

    private struct Display: Identifiable {
        let id: UInt32
        let name: String
    }

    private var displays: [Display] {
        NSScreen.screens.compactMap { s in Backlight.displayID(s).map { Display(id: $0, name: s.localizedName) } }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Source") {
                    VStack(alignment: .trailing) {
                        Text(play.sourceLabel)
                        HStack {
                            Button("Latest Recording") { Task { await play.useLatest() } }
                            Button("Recording Folder…") { play.chooseFolder() }
                        }
                    }
                }
                ForEach(displays) { d in
                    LabeledContent(d.name) {
                        HStack {
                            Text(play.files[d.id]?.lastPathComponent ?? "Not covered")
                                .foregroundStyle(play.files[d.id] == nil ? .secondary : .primary)
                                .help(play.files[d.id]?.path(percentEncoded: false) ?? "")
                            Button("Choose…") { play.chooseFile(for: d.id) }
                            if play.files[d.id] != nil {
                                Button("Clear") { play.clear(d.id) }
                            }
                        }
                    }
                }
            } header: {
                Text("What to play")
            } footer: {
                Text("A recording plays each screen file on the display it came from. "
                    + "Choose any video for a display, for example a recut export from Final Cut Pro.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(play.isActive)

            Section {
                Picker("Countdown before play", selection: $play.countdown) {
                    ForEach(Playback.countdowns, id: \.self) { Text($0 == 0 ? "Off" : "\($0) seconds").tag($0) }
                }
                Picker("Tick", selection: $play.tickEvery) {
                    ForEach(Playback.tickIntervals, id: \.self) { Text($0 == 0 ? "Off" : "Every \($0) seconds").tag($0) }
                }
                Toggle("Count the last \(Playback.lastSeconds) seconds", isOn: $play.lastSecondBeeps)
                Picker("At the end", selection: $play.atEnd) {
                    ForEach(Playback.AtEnd.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Play the video's own sound", isOn: $play.videoSound)
            } header: {
                Text("Timing and sounds")
            } footer: {
                Text("Sounds: Pop = countdown and last seconds, Glass = start, Tink = tick, Hero = end. "
                    + "Your mic hears them — use headphones if the recording must not. "
                    + "The video's own sound is off, because a recording's track is your mic from the first take.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Text(play.status).monospacedDigit()
                HStack {
                    Button(playLabel) { play.togglePlay() }
                    Button("Restart") { play.restart() }.disabled(!play.isActive)
                    Button("Stop") { play.stop() }.disabled(!play.isActive)
                }
            } header: {
                Text("Play")
            } footer: {
                Text("⌃⌥P or Space: play / pause. ⌃⌥⇧P: restart. Esc: stop. Play always starts with the countdown.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var playLabel: String {
        switch play.state {
        case .idle: "Play"
        case .playing, .countdown: "Pause"
        case .paused: "Resume"
        case .ended: "Play Again"
        }
    }
}
