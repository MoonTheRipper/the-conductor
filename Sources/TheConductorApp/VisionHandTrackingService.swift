import AppKit
import AVFoundation
import ConductorCore
import SwiftUI
import Vision
import simd

final class VisionHandTrackingService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Camera idle"
    @Published private(set) var latestSnapshot: GestureSnapshot?

    let captureSession = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "theconductor.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "theconductor.camera.video-output")
    private let processingActor = HandPoseProcessor()

    private let videoOutput = AVCaptureVideoDataOutput()
    private var configured = false

    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }

        switch status {
        case .authorized:
            DispatchQueue.main.async {
                self.statusText = "Starting camera"
            }
            configureIfNeededAndStart()
        case .notDetermined:
            DispatchQueue.main.async {
                self.statusText = "Requesting camera access"
            }
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted {
                        self.statusText = "Camera access granted"
                        self.configureIfNeededAndStart()
                    } else {
                        self.statusText = "Camera access denied"
                    }
                }
            }
        case .denied:
            DispatchQueue.main.async {
                self.statusText = "Camera access denied in System Settings"
            }
        case .restricted:
            DispatchQueue.main.async {
                self.statusText = "Camera access restricted"
            }
        @unknown default:
            DispatchQueue.main.async {
                self.statusText = "Unknown camera authorization state"
            }
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
                self.statusText = "Camera stopped"
            }
        }
    }

    private func configureIfNeededAndStart() {
        sessionQueue.async {
            if self.configured == false {
                self.configureSession()
            }

            guard self.configured else { return }
            guard self.captureSession.isRunning == false else { return }

            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isRunning = true
                self.statusText = "Camera live"
            }
        }
    }

    private func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        defer {
            captureSession.commitConfiguration()
        }

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video)
        else {
            DispatchQueue.main.async {
                self.statusText = "No camera available"
            }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            DispatchQueue.main.async {
                self.statusText = "Failed to create camera input"
            }
            return
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard captureSession.canAddOutput(videoOutput) else {
            DispatchQueue.main.async {
                self.statusText = "Failed to add camera output"
            }
            return
        }

        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        configured = true
    }
}

extension VisionHandTrackingService: @unchecked Sendable {}

extension VisionHandTrackingService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if let snapshot = processingActor.process(sampleBuffer: sampleBuffer) {
            DispatchQueue.main.async {
                self.latestSnapshot = snapshot
                self.statusText = snapshot.leftHand == nil && snapshot.rightHand == nil
                    ? "No hands detected"
                    : "Tracking hands live"
            }
        }
    }
}

private enum HandKey: Hashable {
    case left
    case right
    case unknown
}

final class HandPoseProcessor {
    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()

    private var lastMappedXByHand: [HandKey: Double] = [:]
    private var lastMappedYByHand: [HandKey: Double] = [:]
    private var lastTimestampByHand: [HandKey: TimeInterval] = [:]
    private var lastProcessedTime: TimeInterval = 0

    func process(sampleBuffer: CMSampleBuffer) -> GestureSnapshot? {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastProcessedTime > 0.05 else { return nil }
        lastProcessedTime = now

        let handler = VNImageRequestHandler(
            cmSampleBuffer: sampleBuffer,
            orientation: .up,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let observations = request.results ?? []
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        var leftHand: HandState?
        var rightHand: HandState?

        for observation in observations {
            guard let handState = handState(from: observation, timestamp: timestamp) else { continue }

            switch handKey(for: observation.chirality) {
            case .left:
                leftHand = handState
            case .right:
                rightHand = handState
            case .unknown:
                if rightHand == nil {
                    rightHand = handState
                }
            }
        }

        return GestureSnapshot(
            leftHand: leftHand,
            rightHand: rightHand,
            timestamp: timestamp
        )
    }

    private func handState(
        from observation: VNHumanHandPoseObservation,
        timestamp: TimeInterval
    ) -> HandState? {
        guard
            let points = try? observation.recognizedPoints(.all),
            let wrist = point(.wrist, in: points),
            let thumbTip = point(.thumbTip, in: points),
            let indexTip = point(.indexTip, in: points),
            let middleTip = point(.middleTip, in: points),
            let ringTip = point(.ringTip, in: points),
            let littleTip = point(.littleTip, in: points),
            let indexMCP = point(.indexMCP, in: points),
            let littleMCP = point(.littleMCP, in: points)
        else {
            return nil
        }

        let mappedPosition = normalizedPoint(from: wrist)
        let pinchDistance = simd_distance(thumbTip, indexTip)
        let pinch = clampValue(1.0 - (pinchDistance / 0.18))

        let opennessDistances = [
            simd_distance(wrist, indexTip),
            simd_distance(wrist, middleTip),
            simd_distance(wrist, ringTip),
            simd_distance(wrist, littleTip),
        ]
        let opennessAverage = opennessDistances.reduce(0, +) / Double(opennessDistances.count)
        let openness: HandOpenness
        switch opennessAverage {
        case ..<0.22:
            openness = .closed
        case 0.22..<0.34:
            openness = .relaxed
        default:
            openness = .open
        }

        let handKey = handKey(for: observation.chirality)
        let previousX = lastMappedXByHand[handKey] ?? mappedPosition.x
        let previousY = lastMappedYByHand[handKey] ?? mappedPosition.y
        let previousTimestamp = lastTimestampByHand[handKey] ?? timestamp
        let deltaTime = max(timestamp - previousTimestamp, 0.016)
        let horizontalVelocity = (mappedPosition.x - previousX) / deltaTime
        let verticalVelocity = -((mappedPosition.y - previousY) / deltaTime)
        let spread = clampValue(simd_distance(indexTip, littleTip) / 0.42)
        let rollRadians = atan2(littleMCP.y - indexMCP.y, littleMCP.x - indexMCP.x)
        let roll = clampValue(rollRadians / (.pi / 2), lower: -1.0, upper: 1.0)

        lastMappedXByHand[handKey] = mappedPosition.x
        lastMappedYByHand[handKey] = mappedPosition.y
        lastTimestampByHand[handKey] = timestamp

        return HandState(
            position: mappedPosition,
            pinch: pinch,
            openness: openness,
            verticalVelocity: clampValue(verticalVelocity, lower: -1.4, upper: 1.4),
            horizontalVelocity: clampValue(horizontalVelocity, lower: -1.4, upper: 1.4),
            spread: spread,
            roll: roll
        )
    }

    private func point(
        _ joint: VNHumanHandPoseObservation.JointName,
        in points: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]
    ) -> SIMD2<Double>? {
        guard let point = points[joint], point.confidence >= 0.25 else {
            return nil
        }

        return SIMD2<Double>(Double(point.location.x), Double(point.location.y))
    }

    private func normalizedPoint(from point: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2<Double>(
            x: clampValue((0.5 - point.x) * 2.0, lower: -1.0, upper: 1.0),
            y: clampValue((0.5 - point.y) * 2.0, lower: -1.0, upper: 1.0)
        )
    }

    private func handKey(for chirality: VNChirality) -> HandKey {
        switch chirality {
        case .left:
            return .left
        case .right:
            return .right
        case .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}

private func clampValue(_ value: Double, lower: Double = 0.0, upper: Double = 1.0) -> Double {
    min(max(value, lower), upper)
}

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.previewLayer.session = session
    }
}

final class PreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer = previewLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
