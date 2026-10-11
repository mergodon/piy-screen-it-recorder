import AppKit
import AVFoundation
import ScreenCaptureKit

/// Records every display to its own .mov (HEVC, ~1440p, 30fps). Each file carries the
/// same microphone track, so FCP's "Synchronize Clips" (or a clap) lines them up.
@MainActor
final class Recorder: NSObject, ObservableObject {
    static let shared = Recorder()

    static let targetWidth = 2560
    nonisolated static let fps: Int32 = 30
    static let minFreeBytes: Int64 = 10_000_000_000  // ~1h of two screens
    static let stampFormat = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmmss"  // local time, matches the `rec` script
        return f
    }()

    @Published private(set) var isRecording = false
    @Published private(set) var status = "Ready"
    @Published private(set) var lastError: String?
    @Published var micID: String? {
        didSet { UserDefaults.standard.set(micID, forKey: "micID") }
    }
    @Published var cameraID: String? {
        didSet { UserDefaults.standard.set(cameraID, forKey: "cameraID") }
    }
    @Published var cameraFPS: Int {
        didSet { UserDefaults.standard.set(cameraFPS, forKey: "cameraFPS") }
    }
    @Published var hideWidgets: Bool {
        didSet { UserDefaults.standard.set(hideWidgets, forKey: "hideWidgets") }
    }

    static let defaultFolder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Movies/ScreenItRecorder", directoryHint: .isDirectory)
    /// Where each session's folder goes. Chosen in Settings; nil in the prefs = the default.
    @Published var folder: URL {
        didSet {
            UserDefaults.standard.set(isDefaultFolder ? nil : folder.path(percentEncoded: false), forKey: "saveFolder")
        }
    }

    private var streams: [SCStream] = []
    private var started: [SCStream] = []
    private var camera: CameraRecorder?
    private var pendingFinishes: [CheckedContinuation<Void, Never>] = []
    private var unfinished = 0
    private var awake: NSObjectProtocol?
    private var widgetsWereHidden: Bool?
    private var session: String?  // the folder name of the current recording
    /// A start or stop is in progress. A camera can take seconds to warm up, and a second ⌃⌥⇧R
    /// meanwhile must not begin a second recording.
    private var busy = false
    /// Longest wait for the files to finish saving before stop() gives up on them.
    static let saveTimeout: Duration = .seconds(30)

    private var isDefaultFolder: Bool { folder.standardizedFileURL == Self.defaultFolder.standardizedFileURL }

    var mics: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices
    }

    override init() {
        let d = UserDefaults.standard
        hideWidgets = d.object(forKey: "hideWidgets") as? Bool ?? true
        micID = d.string(forKey: "micID") ?? AVCaptureDevice.default(for: .audio)?.uniqueID
        cameraID = d.string(forKey: "cameraID")  // off unless chosen
        folder = d.string(forKey: "saveFolder").map { URL(filePath: $0, directoryHint: .isDirectory) } ?? Self.defaultFolder
        cameraFPS = d.object(forKey: "cameraFPS") as? Int ?? Int(Self.fps)  // match the screens
        super.init()
    }

    func start() async {
        guard !isRecording, !busy else { return }
        busy = true
        defer { busy = false }
        lastError = nil
        unfinished = 0
        do {
            // An ad-hoc build is a new app to macOS after every rebuild, so this is the usual failure.
            guard CGPreflightScreenCaptureAccess() else {
                CGRequestScreenCaptureAccess()
                throw RecError("Allow Screen It Recorder in System Settings → Privacy & Security → "
                    + "Screen & System Audio Recording, then quit and reopen it")
            }
            // Create only the default folder. A chosen folder that is missing is usually a drive
            // that is not connected; creating it would record onto the internal disk instead.
            if isDefaultFolder {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } else if !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
                throw RecError("The save folder \(folder.path(percentEncoded: false)) is not there. "
                    + "Connect its drive, or choose another folder in Settings → Recording.")
            }
            // On an SMB share both URL capacity keys come back 0/nil (measured on the fleet share);
            // statfs (via attributesOfFileSystem) reports the real figure there.
            let space = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            var free = space.volumeAvailableCapacityForImportantUsage ?? 0
            if free == 0, let fs = try? FileManager.default.attributesOfFileSystem(forPath: folder.path(percentEncoded: false)),
               let n = fs[.systemFreeSize] as? NSNumber {
                free = n.int64Value
            }
            guard free >= Self.minFreeBytes else {
                throw RecError("Only \(free / 1_000_000_000) GB free — need \(Self.minFreeBytes / 1_000_000_000) GB")
            }

            let stamp = Self.stampFormat.string(from: .now)
            let dir = folder.appending(path: stamp, directoryHint: .isDirectory)

            if let micID {
                guard mics.contains(where: { $0.uniqueID == micID }) else {
                    throw RecError("The chosen microphone is not connected. Connect it, or choose another one "
                        + "in Settings → Recording.")
                }
                guard await AVCaptureDevice.requestAccess(for: .audio) else {
                    throw RecError("Screen It Recorder has no permission to use the microphone.")
                }
            }

            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard !content.displays.isEmpty else { throw RecError("No displays found") }
            if let cameraID {
                guard await AVCaptureDevice.requestAccess(for: .video) else {
                    throw RecError("Screen It Recorder has no permission to use the camera.")
                }
                camera = try CameraRecorder(cameraID: cameraID, micID: micID, fps: Int32(cameraFPS))
            }

            if hideWidgets {
                widgetsWereHidden = Widgets.hidden
                Widgets.hidden = true
            }
            awake = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Recording screens")

            for (i, display) in content.displays.enumerated() {
                let stream = try makeStream(display: display, url: dir.appending(path: "screen\(i).mov"))
                streams.append(stream)
                unfinished += 1
            }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let camera {
                status = "Starting camera…"
                unfinished += 1
                await camera.start(to: dir.appending(path: "camera.mov")) { error in
                    Task { @MainActor in
                        if let error { self.fail(error) }
                        self.finishedOne()
                    }
                }
            }
            for stream in streams {
                try await stream.startCapture()
                started.append(stream)
            }

            isRecording = true
            session = stamp
            status = "● Recording \(streams.count) screens\(camera == nil ? "" : " + camera")"
        } catch {
            camera?.stop()
            for stream in started { try? await stream.stopCapture() }
            await teardown()
            fail(error)
        }
    }

    func stop() async {
        guard isRecording, !busy else { return }
        busy = true
        defer { busy = false }
        status = "Saving…"
        camera?.stop()
        for stream in streams { try? await stream.stopCapture() }
        if unfinished > 0 {
            // A file whose stream died may never report that it finished. Never wait forever:
            // that would block the next recording and Quit.
            let timeout = Task {
                try? await Task.sleep(for: Self.saveTimeout)
                guard !Task.isCancelled, unfinished > 0 else { return }
                fail(RecError("\(unfinished) file(s) did not finish saving. They can be incomplete."))
                unfinished = 1
                finishedOne()
            }
            await withCheckedContinuation { pendingFinishes.append($0) }
            timeout.cancel()
        }
        await teardown()
        if lastError == nil { status = "Saved: \(session ?? "")" }
    }

    func openFolder() {
        if isDefaultFolder { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        NSWorkspace.shared.open(folder)
    }

    private func makeStream(display: SCDisplay, url: URL) throws -> SCStream {
        let cfg = SCStreamConfiguration()
        let width = min(Self.targetWidth, display.width * 2)
        cfg.width = width & ~1
        cfg.height = (width * display.height / display.width) & ~1
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: Self.fps)
        cfg.showsCursor = true
        // Capture in sRGB, not the display's P3, so pixels match the file's BT.709 tag
        // (and the green screen lands as exact #00FF00).
        cfg.colorSpaceName = CGColorSpace.sRGB
        cfg.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        cfg.queueDepth = 8
        if let micID {
            cfg.captureMicrophone = true
            cfg.microphoneCaptureDeviceID = micID
        }

        let out = SCRecordingOutputConfiguration()
        out.outputURL = url
        out.outputFileType = .mov
        out.videoCodecType = .hevc

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: cfg, delegate: self)
        try stream.addRecordingOutput(SCRecordingOutput(configuration: out, delegate: self))
        return stream
    }

    private func teardown() async {
        streams.removeAll()
        started.removeAll()
        camera = nil
        unfinished = 0
        if let awake { ProcessInfo.processInfo.endActivity(awake) }
        awake = nil
        if let was = widgetsWereHidden { Widgets.hidden = was }
        widgetsWereHidden = nil
        isRecording = false
    }

    private func finishedOne() {
        unfinished -= 1
        guard unfinished <= 0 else { return }
        pendingFinishes.forEach { $0.resume() }
        pendingFinishes.removeAll()
    }

    private func fail(_ error: Error) {
        lastError = error.localizedDescription
        status = isRecording ? "● Recording, with an error" : "Recording failed"
        // Offer the System Settings pane when a missing permission is the likely cause.
        let fix: Permission? = !CGPreflightScreenCaptureAccess() ? .screen
            : cameraID != nil && Permission.camera.granted != true ? .camera
            : micID != nil && Permission.microphone.granted != true ? .microphone : nil
        ErrorAlert.show("Recording failed", error.localizedDescription, fix: fix)
    }
}

extension Recorder: SCStreamDelegate, SCRecordingOutputDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.fail(error)
            await self.stop()
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ out: SCRecordingOutput) {
        Task { @MainActor in self.finishedOne() }
    }

    nonisolated func recordingOutput(_ out: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            self.fail(error)
            self.finishedOne()
        }
    }
}

struct RecError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// System Settings → Desktop & Dock → Show Widgets → On Desktop. Takes effect live.
enum Widgets {
    static var hidden: Bool {
        get { defaults(["read", "com.apple.WindowManager", "StandardHideWidgets"]) == "1" }
        set { _ = defaults(["write", "com.apple.WindowManager", "StandardHideWidgets", "-bool", newValue ? "true" : "false"]) }
    }

    private static func defaults(_ args: [String]) -> String {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(filePath: "/usr/bin/defaults")
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
