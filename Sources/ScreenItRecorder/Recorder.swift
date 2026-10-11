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

    let folder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Movies/ScreenItRecorder", directoryHint: .isDirectory)

    private var streams: [SCStream] = []
    private var started: [SCStream] = []
    private var camera: CameraRecorder?
    private var pendingFinishes: [CheckedContinuation<Void, Never>] = []
    private var unfinished = 0
    private var awake: NSObjectProtocol?
    private var widgetsWereHidden: Bool?

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
        cameraFPS = d.object(forKey: "cameraFPS") as? Int ?? Int(Self.fps)  // match the screens
        super.init()
    }

    func start() async {
        guard !isRecording else { return }
        lastError = nil
        do {
            // An ad-hoc build is a new app to macOS after every rebuild, so this is the usual failure.
            guard CGPreflightScreenCaptureAccess() else {
                CGRequestScreenCaptureAccess()
                throw RecError("Allow ScreenItRecorder in System Settings → Privacy & Security → "
                    + "Screen & System Audio Recording, then quit and reopen it")
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let free = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage ?? 0
            guard free >= Self.minFreeBytes else {
                throw RecError("Only \(free / 1_000_000_000) GB free — need \(Self.minFreeBytes / 1_000_000_000) GB")
            }

            let stamp = Self.stampFormat.string(from: .now)
            let dir = folder.appending(path: stamp, directoryHint: .isDirectory)

            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard !content.displays.isEmpty else { throw RecError("No displays found") }
            if let cameraID {
                guard await AVCaptureDevice.requestAccess(for: .video) else { throw RecError("No camera permission") }
                if micID != nil { _ = await AVCaptureDevice.requestAccess(for: .audio) }
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
            status = "● Recording \(streams.count) screens\(camera == nil ? "" : " + camera @ \(cameraFPS) fps") → \(stamp)"
        } catch {
            camera?.stop()
            for stream in started { try? await stream.stopCapture() }
            await teardown()
            fail(error)
        }
    }

    func stop() async {
        guard isRecording else { return }
        status = "Saving…"
        camera?.stop()
        for stream in streams { try? await stream.stopCapture() }
        if unfinished > 0 {
            await withCheckedContinuation { pendingFinishes.append($0) }
        }
        await teardown()
        if lastError == nil { status = "Saved to \(folder.path(percentEncoded: false))" }
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
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
        status = "Error: \(error.localizedDescription)"
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
