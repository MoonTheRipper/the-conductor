import AVFoundation
import Combine
import ConductorCore
import SwiftUI
import simd

struct DebugGestureState: Equatable {
    var leftPosition = SIMD2<Double>(-0.36, 0.14)
    var leftPinch = 0.18
    var leftOpenness: HandOpenness = .relaxed
    var leftVerticalVelocity = 0.08

    var rightPosition = SIMD2<Double>(0.08, -0.76)
    var rightPinch = 0.16
    var rightOpenness: HandOpenness = .open
    var rightVerticalVelocity = -0.12

    static let seed = DebugGestureState()
}

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var debugState: DebugGestureState {
        didSet {
            if trackingMode == .simulator {
                refreshFromDebugGesture()
            }
        }
    }

    @Published private(set) var performanceState: PerformanceState
    @Published private(set) var chordLabels: [String]
    @Published private(set) var intervalLabels: [String]
    @Published var trackingMode: TrackingMode = .simulator {
        didSet { handleTrackingModeChange() }
    }
    @Published var routingMode: RoutingMode = .standaloneHost {
        didSet { handleRoutingModeChange() }
    }
    @Published var keyCenter: PitchClass = .c {
        didSet {
            engine.setKeyCenter(keyCenter)
            chordLabels = engine.harmonyEngine.chordLabels
            refreshCurrentInput()
        }
    }
    @Published var selectedInstrumentID: String
    @Published private(set) var midiDestinations: [MIDIDestinationDescriptor] = []
    @Published private(set) var midiStatusText = "MIDI bridge ready"
    @Published var selectedMIDIDestinationID = LogicMIDIBridgeService.noDestinationID {
        didSet {
            guard selectedMIDIDestinationID != midiBridgeService.selectedDestinationID else { return }
            midiBridgeService.setSelectedDestination(id: selectedMIDIDestinationID)
        }
    }
    @Published var sendToVirtualMIDISource = true {
        didSet {
            guard sendToVirtualMIDISource != midiBridgeService.sendToVirtualSource else { return }
            midiBridgeService.sendToVirtualSource = sendToVirtualMIDISource
        }
    }

    let availableInstruments: [InstrumentDescriptor]

    private var engine: PerformanceEngine
    private var frameClock: TimeInterval = 0
    private let liveTrackingService = VisionHandTrackingService()
    private let midiBridgeService = LogicMIDIBridgeService()
    private var cancellables = Set<AnyCancellable>()
    private var loopPlaybackTimer: Timer?
    private var loopPlaybackIndex = 0

    init() {
        let engine = PerformanceEngine(keyCenter: .c)
        self.engine = engine
        self.performanceState = engine.state
        self.chordLabels = engine.harmonyEngine.chordLabels
        self.intervalLabels = engine.harmonyEngine.intervalLabels
        self.debugState = .seed
        self.availableInstruments = DemoInstrumentCatalog().availableInstruments()
        self.selectedInstrumentID = self.availableInstruments.first?.id ?? ""
        bindLiveTracking()
        bindMIDIBridge()
        refreshFromDebugGesture()
    }

    var selectedInstrument: InstrumentDescriptor? {
        availableInstruments.first { $0.id == selectedInstrumentID }
    }

    var routingDescription: String {
        switch routingMode {
        case .standaloneHost:
            return "Drive hosted instruments and libraries directly without opening Logic."
        case .logicBridge:
            return "Send committed harmony and performance gestures into Logic over MIDI."
        }
    }

    var liveTrackingStatusText: String {
        liveTrackingService.statusText
    }

    var cameraAuthorizationStatusText: String {
        switch liveTrackingService.authorizationStatus {
        case .authorized:
            return liveTrackingService.isRunning ? "Authorized and running" : "Authorized"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }

    var captureSession: AVCaptureSession {
        liveTrackingService.captureSession
    }

    var isLiveTracking: Bool {
        trackingMode == .liveCamera
    }

    var isCameraRunning: Bool {
        liveTrackingService.isRunning
    }

    var virtualMIDISourceName: String {
        midiBridgeService.virtualSourceName
    }

    var midiChannelMapDescription: [String] {
        midiBridgeService.channelMapDescription
    }

    func binding<Value>(_ keyPath: WritableKeyPath<DebugGestureState, Value>) -> Binding<Value> {
        Binding(
            get: { self.debugState[keyPath: keyPath] },
            set: { newValue in
                var copy = self.debugState
                copy[keyPath: keyPath] = newValue
                self.debugState = copy
            }
        )
    }

    func startLiveTracking() {
        liveTrackingService.start()
    }

    func stopLiveTracking() {
        liveTrackingService.stop()
    }

    func refreshMIDIDestinations() {
        midiBridgeService.refreshDestinations()
    }

    func silenceMIDINotes() {
        midiBridgeService.silenceAllNotes()
    }

    func pulseCommit() {
        pulse(
            engage: {
                $0.rightPinch = 0.95
                $0.rightOpenness = .open
            },
            release: { $0.rightPinch = 0.18 }
        )
    }

    func pulseLoopToggle() {
        pulse(
            engage: {
                $0.leftPinch = 0.95
                $0.rightPinch = 0.95
            },
            release: {
                $0.leftPinch = 0.18
                $0.rightPinch = 0.18
            }
        )
    }

    func pulseDownbeat() {
        pulse(
            engage: {
                $0.rightOpenness = .open
                $0.rightVerticalVelocity = -1.0
            },
            release: { $0.rightVerticalVelocity = 0.0 }
        )
    }

    func pulseStop() {
        pulse(
            engage: {
                $0.rightOpenness = .closed
                $0.rightPinch = 0.82
            },
            release: {
                $0.rightOpenness = .relaxed
                $0.rightPinch = 0.18
            }
        )
    }

    private func pulse(
        engage: (inout DebugGestureState) -> Void,
        release: (inout DebugGestureState) -> Void
    ) {
        guard trackingMode == .simulator else { return }

        var onState = debugState
        engage(&onState)
        debugState = onState

        var offState = debugState
        release(&offState)
        debugState = offState
    }

    private func bindLiveTracking() {
        liveTrackingService.$latestSnapshot
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self, self.trackingMode == .liveCamera else { return }
                self.apply(snapshot: snapshot)
            }
            .store(in: &cancellables)
    }

    private func bindMIDIBridge() {
        midiBridgeService.$destinations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] destinations in
                self?.midiDestinations = destinations
            }
            .store(in: &cancellables)

        midiBridgeService.$statusText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] statusText in
                self?.midiStatusText = statusText
            }
            .store(in: &cancellables)

        midiBridgeService.$selectedDestinationID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedDestinationID in
                self?.selectedMIDIDestinationID = selectedDestinationID
            }
            .store(in: &cancellables)

        midiBridgeService.$sendToVirtualSource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sendToVirtualSource in
                self?.sendToVirtualMIDISource = sendToVirtualSource
            }
            .store(in: &cancellables)
    }

    private func handleTrackingModeChange() {
        switch trackingMode {
        case .simulator:
            liveTrackingService.stop()
            refreshFromDebugGesture()
        case .liveCamera:
            performanceState.activityText = "Live camera ready"
        }
    }

    private func handleRoutingModeChange() {
        switch routingMode {
        case .standaloneHost:
            stopLoopPlayback(shouldSilence: true)
        case .logicBridge:
            midiBridgeService.refreshDestinations()
            if performanceState.loopBuffer.isPlaying {
                startLoopPlayback(using: performanceState.loopBuffer)
            }
        }
    }

    private func refreshCurrentInput() {
        switch trackingMode {
        case .simulator:
            refreshFromDebugGesture()
        case .liveCamera:
            if let snapshot = liveTrackingService.latestSnapshot {
                apply(snapshot: snapshot)
            }
        }
    }

    private func refreshFromDebugGesture() {
        guard trackingMode == .simulator else { return }

        frameClock += 0.12

        let snapshot = GestureSnapshot(
            leftHand: HandState(
                position: debugState.leftPosition,
                pinch: debugState.leftPinch,
                openness: debugState.leftOpenness,
                verticalVelocity: debugState.leftVerticalVelocity
            ),
            rightHand: HandState(
                position: debugState.rightPosition,
                pinch: debugState.rightPinch,
                openness: debugState.rightOpenness,
                verticalVelocity: debugState.rightVerticalVelocity
            ),
            timestamp: frameClock
        )

        apply(snapshot: snapshot)
    }

    private func apply(snapshot: GestureSnapshot) {
        let events = engine.handle(snapshot: snapshot)
        performanceState = engine.state
        processPerformanceEvents(events)
    }

    private func processPerformanceEvents(_ events: [PerformanceEvent]) {
        guard events.isEmpty == false else { return }

        for event in events {
            switch event {
            case .chordCommitted(let chord, let interval, let dynamics, _):
                guard routingMode == .logicBridge else { continue }
                midiBridgeService.send(
                    chord: chord,
                    interval: interval,
                    dynamics: dynamics,
                    layers: performanceState.layers
                )
            case .transportChanged(let isPerforming, _):
                if isPerforming == false {
                    stopLoopPlayback(shouldSilence: routingMode == .logicBridge)
                }
            case .loopStateChanged(let loopBuffer, _):
                guard routingMode == .logicBridge else {
                    stopLoopPlayback()
                    continue
                }

                if loopBuffer.isPlaying {
                    startLoopPlayback(using: loopBuffer)
                } else {
                    stopLoopPlayback()
                }
            }
        }
    }

    private func startLoopPlayback(using loopBuffer: LoopBuffer) {
        stopLoopPlayback()

        guard loopBuffer.phrase.isEmpty == false else { return }

        let duration = loopDuration(for: loopBuffer)
        let stepDuration = max(duration / Double(loopBuffer.phrase.count), 0.35)

        loopPlaybackIndex = 0
        sendCurrentLoopChord(from: loopBuffer)

        loopPlaybackTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendCurrentLoopChord(from: loopBuffer)
            }
        }

        if let loopPlaybackTimer {
            RunLoop.main.add(loopPlaybackTimer, forMode: .common)
        }
    }

    private func sendCurrentLoopChord(from loopBuffer: LoopBuffer) {
        guard loopBuffer.phrase.isEmpty == false else { return }

        let chord = loopBuffer.phrase[loopPlaybackIndex % loopBuffer.phrase.count]
        midiBridgeService.send(
            chord: chord,
            interval: performanceState.interval,
            dynamics: performanceState.dynamics,
            layers: performanceState.layers
        )

        loopPlaybackIndex = (loopPlaybackIndex + 1) % loopBuffer.phrase.count
    }

    private func stopLoopPlayback(shouldSilence: Bool = false) {
        loopPlaybackTimer?.invalidate()
        loopPlaybackTimer = nil
        loopPlaybackIndex = 0

        if shouldSilence {
            midiBridgeService.silenceAllNotes()
        }
    }

    private func loopDuration(for loopBuffer: LoopBuffer) -> TimeInterval {
        let capturedDuration: TimeInterval
        if let startTimestamp = loopBuffer.startTimestamp, let endTimestamp = loopBuffer.endTimestamp {
            capturedDuration = max(endTimestamp - startTimestamp, 0.0)
        } else {
            capturedDuration = 0.0
        }

        let fallbackDuration = Double(max(loopBuffer.phrase.count, 1)) * 0.75
        return max(capturedDuration, fallbackDuration)
    }
}
