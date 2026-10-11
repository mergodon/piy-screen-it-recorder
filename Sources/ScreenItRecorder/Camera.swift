import AVFoundation

/// Records one camera (1080p HEVC) plus the mic to its own .mov, alongside the screens.
/// `@unchecked Sendable`: touched from the main actor and AVFoundation's queues, never concurrently.
final class CameraRecorder: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let camera: AVCaptureDevice
    private var locked = false
    private var onStarted: (() -> Void)?
    private var onFinish: ((Error?) -> Void)?

    static var devices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices
    }

    /// Menu labels, numbering duplicates (two Studio Displays → two "Studio Display Camera").
    static func labels(for devices: [AVCaptureDevice]) -> [String: String] {
        var seen: [String: Int] = [:]
        let total = Dictionary(grouping: devices, by: \.localizedName).mapValues(\.count)
        return Dictionary(uniqueKeysWithValues: devices.map { d in
            seen[d.localizedName, default: 0] += 1
            let name = total[d.localizedName]! > 1 ? "\(d.localizedName) (\(seen[d.localizedName]!))" : d.localizedName
            return (d.uniqueID, name)
        })
    }

    /// Whole frame rates the camera offers at 1080p, e.g. [24, 25, 30, 50, 60].
    static func rates(cameraID: String) -> [Int] {
        guard let camera = AVCaptureDevice(uniqueID: cameraID) else { return [] }
        let rates = camera.formats.filter {
            let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return d.width == 1920 && d.height == 1080
        }.flatMap { $0.videoSupportedFrameRateRanges.map { Int($0.maxFrameRate.rounded()) } }
        return Array(Set(rates)).sorted()
    }

    init(cameraID: String, micID: String?, fps: Int32) throws {
        guard let camera = AVCaptureDevice(uniqueID: cameraID) else { throw RecError("Camera not found") }
        self.camera = camera
        super.init()
        session.beginConfiguration()
        try add(AVCaptureDeviceInput(device: camera))
        if let micID, let mic = AVCaptureDevice(uniqueID: micID) { try add(AVCaptureDeviceInput(device: mic)) }
        guard session.canAddOutput(output) else { throw RecError("Cannot record from \(camera.localizedName)") }
        session.addOutput(output)
        try configure(camera, width: 1920, height: 1080, fps: fps)
        session.commitConfiguration()
        if let video = output.connection(with: .video) {
            output.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: video)
        }
    }

    /// Returns once the file is really recording — a camera can take seconds to warm up,
    /// so the screens start after this and the camera never misses the start (or the clap).
    func start(to url: URL, onFinish: @escaping (Error?) -> Void) async {
        self.onFinish = onFinish
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            onStarted = { done.resume() }
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                session.startRunning()  // blocks
                unlock()  // held since configure() so the session keeps our format
                output.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    func stop() { output.stopRecording() }

    func fileOutput(_ out: AVCaptureFileOutput, didStartRecordingTo url: URL,
                    from connections: [AVCaptureConnection]) {
        onStarted?()
        onStarted = nil
    }

    func fileOutput(_ out: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        session.stopRunning()
        onStarted?()  // never started: release the waiting start()
        onStarted = nil
        // AVFoundation reports some clean stops as errors with this flag set.
        let ok = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
        onFinish?(ok ? nil : error)
    }

    /// Pick the camera format directly (a session preset would reset the frame rate on start)
    /// and lock it to the screens' frame rate — cameras default to 25 or 24 fps — so the FCP
    /// timeline gets one camera frame per screen frame. Falls back to the largest format.
    /// Cameras report inexact rates (Insta360: 1000000/30000030 s), and setting a duration
    /// outside a range throws — so match within a tolerance and use the range's own duration.
    private func configure(_ camera: AVCaptureDevice, width: Int32, height: Int32, fps: Int32) throws {
        func range(_ f: AVCaptureDevice.Format) -> AVFrameRateRange? {
            f.videoSupportedFrameRateRanges.first {
                $0.minFrameRate - 0.5 <= Double(fps) && Double(fps) <= $0.maxFrameRate + 0.5
            }
        }
        let formats = camera.formats.filter {
            let d = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return d.width == width && d.height == height && range($0) != nil
        }
        // Prefer 4:2:0 ('420v'), what the HEVC encoder wants.
        let format = formats.first { CMFormatDescriptionGetMediaSubType($0.formatDescription)
            == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange } ?? formats.first
        try camera.lockForConfiguration()  // released in start(), after startRunning()
        locked = true
        if let format, let r = range(format) {
            let duration = max(r.minFrameDuration, min(r.maxFrameDuration, CMTime(value: 1, timescale: fps)))
            camera.activeFormat = format
            camera.activeVideoMinFrameDuration = duration
            camera.activeVideoMaxFrameDuration = duration
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
    }

    private func unlock() {
        if locked { camera.unlockForConfiguration() }
        locked = false
    }

    deinit { unlock() }  // created but never started (a later start step failed)

    private func add(_ input: AVCaptureDeviceInput) throws {
        guard session.canAddInput(input) else { throw RecError("Cannot use \(input.device.localizedName)") }
        session.addInput(input)
    }
}
