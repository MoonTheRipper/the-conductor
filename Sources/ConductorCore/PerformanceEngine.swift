import Foundation
import simd

public struct PerformanceEngine: Sendable {
    public private(set) var harmonyEngine: HarmonyEngine
    public private(set) var state: PerformanceState

    private var lastLoopToggleTimestamp: TimeInterval = -.infinity
    private var lastCommitTimestamp: TimeInterval = -.infinity
    private var lastTransportTimestamp: TimeInterval = -.infinity

    public init(keyCenter: PitchClass = .c) {
        let harmonyEngine = HarmonyEngine(keyCenter: keyCenter)
        let (openingChord, chordPlot) = harmonyEngine.chordSelection(for: SIMD2<Double>(0, -1))
        let (openingInterval, intervalPlot) = harmonyEngine.intervalSelection(for: SIMD2<Double>(0, -1))
        self.harmonyEngine = harmonyEngine
        self.state = PerformanceState(
            currentChord: openingChord,
            previewChord: openingChord,
            interval: openingInterval,
            dynamics: 0.58,
            isPerforming: false,
            loopBuffer: LoopBuffer(),
            layers: Self.defaultLayers,
            chordPlot: chordPlot,
            intervalPlot: intervalPlot,
            activityText: "Standby"
        )
    }

    public mutating func setKeyCenter(_ keyCenter: PitchClass) {
        harmonyEngine = HarmonyEngine(keyCenter: keyCenter)
        let (chord, chordPlot) = harmonyEngine.chordSelection(for: state.chordPlot.normalized)
        let (interval, intervalPlot) = harmonyEngine.intervalSelection(for: state.intervalPlot.normalized)
        state.currentChord = chord
        state.previewChord = chord
        state.interval = interval
        state.chordPlot = chordPlot
        state.intervalPlot = intervalPlot
        state.activityText = "Key center set to \(keyCenter.displayName)"
    }

    public mutating func handle(snapshot: GestureSnapshot) -> [PerformanceEvent] {
        var events: [PerformanceEvent] = []
        updatePreviewState(with: snapshot)
        events.append(contentsOf: handleLoopToggle(with: snapshot))
        events.append(contentsOf: handleTransport(with: snapshot))
        events.append(contentsOf: handleCommit(with: snapshot))
        updateLayers(with: snapshot)
        return events
    }

    public mutating func clearLoopBuffer() {
        state.loopBuffer = LoopBuffer()
        updateLayers(with: GestureSnapshot(leftHand: nil, rightHand: nil, timestamp: 0))
        state.activityText = "Loop cleared"
    }

    private mutating func updatePreviewState(with snapshot: GestureSnapshot) {
        if let rightHand = snapshot.rightHand {
            let (previewChord, chordPlot) = harmonyEngine.chordSelection(for: rightHand.position)
            state.previewChord = previewChord
            state.chordPlot = chordPlot

            let normalizedHeight = 1.0 - ((rightHand.position.y + 1.0) / 2.0)
            let gestureEnergy = max(0.0, -rightHand.verticalVelocity) * 0.22
            let opennessLift = rightHand.spread * 0.16
            let shapeLift = abs(rightHand.roll) * 0.08
            state.dynamics = clamped(normalizedHeight + gestureEnergy + opennessLift + shapeLift, lower: 0.12, upper: 1.0)
        }

        if let leftHand = snapshot.leftHand {
            let (interval, intervalPlot) = harmonyEngine.intervalSelection(for: leftHand.position)
            state.interval = interval
            state.intervalPlot = intervalPlot
        }
    }

    private mutating func handleLoopToggle(with snapshot: GestureSnapshot) -> [PerformanceEvent] {
        guard
            let leftHand = snapshot.leftHand,
            let rightHand = snapshot.rightHand,
            leftHand.pinch > 0.88,
            rightHand.pinch > 0.88,
            snapshot.timestamp - lastLoopToggleTimestamp > 0.45
        else {
            return []
        }

        if state.loopBuffer.isRecording == false && state.loopBuffer.isPlaying == false {
            state.loopBuffer = LoopBuffer(
                phrase: [],
                isRecording: true,
                isPlaying: false,
                startTimestamp: snapshot.timestamp,
                endTimestamp: nil
            )
            state.activityText = "Loop capture started"
        } else if state.loopBuffer.isRecording {
            state.loopBuffer.isRecording = false
            state.loopBuffer.isPlaying = !state.loopBuffer.phrase.isEmpty
            state.loopBuffer.endTimestamp = snapshot.timestamp
            state.activityText = state.loopBuffer.phrase.isEmpty
                ? "Loop closed with no committed chords"
                : "Loop closed with \(state.loopBuffer.phrase.count) chord events"
        } else {
            state.loopBuffer = LoopBuffer()
            state.activityText = "Loop cleared"
        }

        lastLoopToggleTimestamp = snapshot.timestamp
        return [
            .loopStateChanged(loopBuffer: state.loopBuffer, timestamp: snapshot.timestamp),
        ]
    }

    private mutating func handleTransport(with snapshot: GestureSnapshot) -> [PerformanceEvent] {
        guard
            let rightHand = snapshot.rightHand,
            snapshot.timestamp - lastTransportTimestamp > 0.35
        else {
            return []
        }

        if rightHand.openness == .open && rightHand.verticalVelocity < -0.72 {
            let wasPerforming = state.isPerforming
            state.isPerforming = true
            state.activityText = "Ensemble engaged"
            lastTransportTimestamp = snapshot.timestamp
            return wasPerforming ? [] : [
                .transportChanged(isPerforming: true, timestamp: snapshot.timestamp),
            ]
        }

        let gestureDownbeatStrength = (-rightHand.verticalVelocity * 0.78) + (rightHand.spread * 0.22)
        if rightHand.openness == .open && gestureDownbeatStrength > 0.92 {
            let wasPerforming = state.isPerforming
            state.isPerforming = true
            state.activityText = "Ensemble engaged"
            lastTransportTimestamp = snapshot.timestamp
            return wasPerforming ? [] : [
                .transportChanged(isPerforming: true, timestamp: snapshot.timestamp),
            ]
        }

        if rightHand.openness == .closed && rightHand.pinch > 0.55 {
            let wasPerforming = state.isPerforming
            state.isPerforming = false
            state.activityText = "Ensemble muted"
            lastTransportTimestamp = snapshot.timestamp
            return wasPerforming ? [
                .transportChanged(isPerforming: false, timestamp: snapshot.timestamp),
            ] : []
        }

        return []
    }

    private mutating func handleCommit(with snapshot: GestureSnapshot) -> [PerformanceEvent] {
        let isLoopToggleGesture =
            (snapshot.leftHand?.pinch ?? 0.0) > 0.88 &&
            (snapshot.rightHand?.pinch ?? 0.0) > 0.88

        guard
            let rightHand = snapshot.rightHand,
            rightHand.pinch > 0.82,
            isLoopToggleGesture == false,
            snapshot.timestamp - lastCommitTimestamp > 0.25
        else {
            return []
        }

        var events: [PerformanceEvent] = []
        let wasPerforming = state.isPerforming
        state.currentChord = state.previewChord
        state.isPerforming = true

        if state.loopBuffer.isRecording {
            let phraseEvent = LoopPhraseEvent(
                chord: state.currentChord,
                interval: state.interval,
                dynamics: state.dynamics,
                timestamp: snapshot.timestamp
            )

            let shouldAppend: Bool
            if let lastEvent = state.loopBuffer.phrase.last {
                let isRepeatedChord = lastEvent.chord == phraseEvent.chord
                let isRepeatedInterval = lastEvent.interval == phraseEvent.interval
                let isRepeatedDynamics = abs(lastEvent.dynamics - phraseEvent.dynamics) < 0.08
                let elapsed = phraseEvent.timestamp - lastEvent.timestamp
                shouldAppend = (isRepeatedChord && isRepeatedInterval && isRepeatedDynamics) == false || elapsed > 0.4
            } else {
                shouldAppend = true
            }

            if shouldAppend {
                state.loopBuffer.phrase.append(phraseEvent)
            }
        }

        state.activityText = "Committed \(state.currentChord.symbol) with \(state.interval.spokenName.lowercased()) focus"
        lastCommitTimestamp = snapshot.timestamp
        if wasPerforming == false {
            events.append(.transportChanged(isPerforming: true, timestamp: snapshot.timestamp))
        }
        events.append(
            .chordCommitted(
                chord: state.currentChord,
                interval: state.interval,
                dynamics: state.dynamics,
                timestamp: snapshot.timestamp
            )
        )
        return events
    }

    private mutating func updateLayers(with snapshot: GestureSnapshot) {
        let leftRadius = snapshot.leftHand.map { clamped(simd_length($0.position)) } ?? 0.35
        let leftSpread = snapshot.leftHand?.spread ?? 0.45
        let rightSpread = snapshot.rightHand?.spread ?? 0.45
        let rightRoll = abs(snapshot.rightHand?.roll ?? 0)
        let horizontalMotion = abs(snapshot.rightHand?.horizontalVelocity ?? 0)
        let intervalWeight = Double(state.interval.rawValue) / Double(IntervalChoice.thirteenth.rawValue)
        let stringsMix = clamped(0.45 + state.dynamics * 0.30 - leftRadius * 0.12 + rightSpread * 0.12)
        let brassMix = clamped(state.dynamics * 0.80 + intervalWeight * 0.18 + rightRoll * 0.12)
        let woodsMix = clamped(0.25 + (1.0 - leftRadius) * 0.55 + leftSpread * 0.10)
        let pulseMix = clamped(0.18 + leftRadius * 0.72 + horizontalMotion * 0.12)

        state.layers = [
            LayerState(name: "Strings", mix: stringsMix, isEnabled: state.isPerforming),
            LayerState(name: "Brass", mix: brassMix, isEnabled: state.dynamics > 0.42),
            LayerState(name: "Woods", mix: woodsMix, isEnabled: state.isPerforming),
            LayerState(
                name: "Pulse",
                mix: pulseMix,
                isEnabled: state.loopBuffer.isRecording || state.loopBuffer.isPlaying
            ),
        ]
    }

    private static let defaultLayers: [LayerState] = [
        LayerState(name: "Strings", mix: 0.62, isEnabled: false),
        LayerState(name: "Brass", mix: 0.35, isEnabled: false),
        LayerState(name: "Woods", mix: 0.44, isEnabled: false),
        LayerState(name: "Pulse", mix: 0.20, isEnabled: false),
    ]
}
