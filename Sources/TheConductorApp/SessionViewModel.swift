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
        didSet { refreshFromDebugGesture() }
    }

    @Published private(set) var performanceState: PerformanceState
    @Published private(set) var chordLabels: [String]
    @Published private(set) var intervalLabels: [String]
    @Published var routingMode: RoutingMode = .standaloneHost
    @Published var keyCenter: PitchClass = .c {
        didSet {
            engine.setKeyCenter(keyCenter)
            chordLabels = engine.harmonyEngine.chordLabels
            refreshFromDebugGesture()
        }
    }
    @Published var selectedInstrumentID: String

    let availableInstruments: [InstrumentDescriptor]

    private var engine: PerformanceEngine
    private var frameClock: TimeInterval = 0

    init() {
        let engine = PerformanceEngine(keyCenter: .c)
        self.engine = engine
        self.performanceState = engine.state
        self.chordLabels = engine.harmonyEngine.chordLabels
        self.intervalLabels = engine.harmonyEngine.intervalLabels
        self.debugState = .seed
        self.availableInstruments = DemoInstrumentCatalog().availableInstruments()
        self.selectedInstrumentID = self.availableInstruments.first?.id ?? ""
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
        var onState = debugState
        engage(&onState)
        debugState = onState

        var offState = debugState
        release(&offState)
        debugState = offState
    }

    private func refreshFromDebugGesture() {
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

        engine.handle(snapshot: snapshot)
        performanceState = engine.state
    }
}
