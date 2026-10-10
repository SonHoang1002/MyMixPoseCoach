import SwiftUI
import PhotosUI
import AVFoundation
import MediaPipeTasksVision
import Darwin

@main
struct SpikeApp: App {
    var body: some Scene { WindowGroup { SpikeView() } }
}

struct SpikeView: View {
    @StateObject private var runner = SpikeRunner()
    @State private var selection: PhotosPickerItem?
    var body: some View {
        VStack(spacing: 20) {
            Text("MediaPipe 1.1.0 • CPU • Full").font(.headline)
            Text(runner.status)
            Button("1. Initialize") { runner.initialize() }
            Button("2. Bundled Android image") { runner.image() }
            PhotosPicker("3. Select video", selection: $selection, matching: .videos)
                .onChange(of: selection) { item in
                    Task {
                        do {
                            guard let data = try await item?.loadTransferable(type: Data.self) else { return }
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent("input.mov")
                            try data.write(to: url)
                            runner.video(url)
                        } catch { runner.reportError(error) }
                    }
                }
            Button("4. Rear camera, 15 seconds") { runner.camera() }
            if let url = runner.logURL { ShareLink("Export JSONL", item: url) }
            Text("Use a physical iPhone. Keep portrait orientation. Export each run and collect the device crash log if initialization terminates the app.")
                .font(.caption)
        }.padding().disabled(runner.busy)
    }
}

final class SpikeRunner: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, PoseLandmarkerLiveStreamDelegate {
    @Published var status = "Ready"
    @Published var busy = false
    @Published var logURL: URL?
    private let queue = DispatchQueue(label: "pose.spike")
    private let logLock = NSLock()
    private var log: FileHandle?
    private var detector: PoseLandmarker?
    private var session: AVCaptureSession?
    private var lastTimestamp = -1
    private var submittedAt: [Int: Double] = [:]

    private func record(_ fields: [String: Any]) {
        logLock.lock(); defer { logLock.unlock() }
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
        log?.write(data); log?.write(Data([10])); log?.synchronizeFile()
    }
    private func begin(_ mode: String) {
        try? log?.close()
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pose-\(mode)-\(UUID().uuidString).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        log = try? FileHandle(forWritingTo: url)
        DispatchQueue.main.async { self.logURL = url }
        var system = utsname()
        uname(&system)
        let device = withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        record(["event": "begin", "mode": mode, "device": device, "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "mediapipe": "1.1.0", "delegate": "CPU", "segmentation": false,
                "thresholds": [0.5, 0.5, 0.5], "model": "pose_landmarker_full.task"])
    }
    private func make(_ mode: RunningMode) throws -> PoseLandmarker {
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task")!
        options.baseOptions.delegate = .CPU
        options.runningMode = mode
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5
        options.minPosePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        options.shouldOutputSegmentationMasks = false
        if mode == .liveStream { options.poseLandmarkerLiveStreamDelegate = self }
        record(["event": "init_begin"])
        let task = try PoseLandmarker(options: options)
        record(["event": "init_ok"])
        return task
    }
    private func results(_ result: PoseLandmarkerResult, timestamp: Int, elapsed: Double) {
        func point(_ x: Float, _ y: Float, _ z: Float, _ visibility: NSNumber?, _ presence: NSNumber?) -> [String: Any] {
            ["x": x, "y": y, "z": z, "visibility": visibility as Any? ?? NSNull(), "presence": presence as Any? ?? NSNull()]
        }
        record(["event": "result", "timestamp_ms": timestamp, "latency_ms": elapsed * 1000,
                "normalized": result.landmarks.map { $0.map { point($0.x, $0.y, $0.z, $0.visibility, $0.presence) } },
                "world": result.worldLandmarks.map { $0.map { point($0.x, $0.y, $0.z, $0.visibility, $0.presence) } }])
    }
    func reportError(_ error: Error) {
        record(["event": "error", "message": String(describing: error)])
        DispatchQueue.main.async { self.status = String(describing: error); self.busy = false }
    }
    private func run(_ mode: String, work: @escaping () throws -> Void) {
        busy = true
        queue.async {
            self.begin(mode)
            do {
                try work()
                self.record(["event": "complete"])
                DispatchQueue.main.async { self.status = "\(mode) complete"; self.busy = false }
            } catch { self.reportError(error) }
        }
    }
    func initialize() { run("initialize") { _ = try self.make(.image) } }
    func image() {
        run("image") {
            let task = try self.make(.image)
            let url = Bundle.main.url(forResource: "reference", withExtension: "jpg")!
            let image = try MPImage(uiImage: UIImage(contentsOfFile: url.path)!)
            let start = ProcessInfo.processInfo.systemUptime
            let result = try task.detect(image: image)
            self.results(result, timestamp: 0, elapsed: ProcessInfo.processInfo.systemUptime - start)
        }
    }
    func video(_ url: URL) {
        run("video") {
            let task = try self.make(.video)
            let asset = AVURLAsset(url: url)
            guard let track = asset.tracks(withMediaType: .video).first else { throw NSError(domain: "No video track", code: 1) }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            output.videoComposition = AVMutableVideoComposition(propertiesOf: asset)
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? NSError(domain: "Video reader", code: 1) }
            var last = -1
            while let sample = output.copyNextSampleBuffer() {
                let timestamp = Int(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) * 1000)
                guard timestamp > last else { continue }; last = timestamp
                let start = ProcessInfo.processInfo.systemUptime
                let result = try task.detect(videoFrame: MPImage(sampleBuffer: sample), timestampInMilliseconds: timestamp)
                self.results(result, timestamp: timestamp, elapsed: ProcessInfo.processInfo.systemUptime - start)
            }
            if reader.status != .completed { throw reader.error ?? NSError(domain: "Incomplete video", code: 1) }
        }
    }
    func camera() {
        busy = true
        AVCaptureDevice.requestAccess(for: .video) { allowed in
            guard allowed else { self.reportError(NSError(domain: "Camera permission denied", code: 1)); return }
            self.queue.async {
                self.begin("liveStream")
                do {
                    self.detector = try self.make(.liveStream)
                    self.lastTimestamp = -1; self.submittedAt = [:]
                    let session = AVCaptureSession()
                    session.sessionPreset = .vga640x480
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw NSError(domain: "No camera", code: 1) }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else { throw NSError(domain: "Camera input", code: 1) }
                    session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    guard session.canAddOutput(output) else { throw NSError(domain: "Camera output", code: 1) }
                    session.addOutput(output)
                    if let connection = output.connection(with: .video) {
                        connection.isVideoMirrored = false
                        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                    }
                    self.session = session; session.startRunning()
                    self.queue.asyncAfter(deadline: .now() + 15) {
                        session.stopRunning()
                        self.record(["event": "capture_stopped"])
                        self.queue.asyncAfter(deadline: .now() + 2) {
                            self.detector = nil; self.session = nil
                            self.record(["event": "complete", "pending": self.submittedAt.count])
                            DispatchQueue.main.async { self.status = "Camera complete"; self.busy = false }
                        }
                    }
                } catch { self.session?.stopRunning(); self.detector = nil; self.reportError(error) }
            }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard submittedAt.isEmpty else { return }
        let timestamp = Int(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000)
        guard timestamp > lastTimestamp else { return }
        do {
            let image = try MPImage(sampleBuffer: sampleBuffer)
            submittedAt[timestamp] = ProcessInfo.processInfo.systemUptime
            lastTimestamp = timestamp
            try detector?.detectAsync(image: image, timestampInMilliseconds: timestamp)
        } catch { submittedAt.removeValue(forKey: timestamp); reportError(error) }
    }
    func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: PoseLandmarkerResult?, timestampInMilliseconds: Int, error: Error?) {
        queue.async {
            let start = self.submittedAt.removeValue(forKey: timestampInMilliseconds)
            if let error { self.record(["event": "error", "message": String(describing: error)]) }
            if let result, let start { self.results(result, timestamp: timestampInMilliseconds, elapsed: ProcessInfo.processInfo.systemUptime - start) }
        }
    }
}
