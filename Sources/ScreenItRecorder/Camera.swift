import AVFoundation

/// Records one camera (1080p HEVC) plus the mic to its own .mov, alongside the screens.
final class CameraRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
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

    init(cameraID: String, micID: String?) throws {
        guard let camera = AVCaptureDevice(uniqueID: cameraID) else { throw RecError("Camera not found") }
        super.init()
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
        try add(AVCaptureDeviceInput(device: camera))
        if let micID, let mic = AVCaptureDevice(uniqueID: micID) { try add(AVCaptureDeviceInput(device: mic)) }
        guard session.canAddOutput(output) else { throw RecError("Cannot record from \(camera.localizedName)") }
        session.addOutput(output)
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

    private func add(_ input: AVCaptureDeviceInput) throws {
        guard session.canAddInput(input) else { throw RecError("Cannot use \(input.device.localizedName)") }
        session.addInput(input)
    }
}
