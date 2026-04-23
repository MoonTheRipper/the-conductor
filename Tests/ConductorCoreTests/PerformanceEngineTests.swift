import ConductorCore
import Foundation
import Testing
import simd

struct PerformanceEngineTests {
    @Test
    func topOfChordCircleMapsToTonic() {
        let engine = HarmonyEngine(keyCenter: .c)

        let (selection, _) = engine.chordSelection(for: SIMD2<Double>(0, -1))

        #expect(selection.symbol == "Cmaj9")
        #expect(selection.function == .tonic)
    }

    @Test
    func loopGestureStartsAndClosesPlayback() {
        var engine = PerformanceEngine(keyCenter: .c)

        let startEvents = engine.handle(snapshot: snapshot(leftPinch: 0.95, rightPinch: 0.95, timestamp: 0.0))
        let commitEvents = engine.handle(snapshot: snapshot(
            leftPosition: SIMD2<Double>(-0.4, 0.1),
            rightPosition: SIMD2<Double>(0, -1),
            leftPinch: 0.18,
            rightPinch: 0.94,
            timestamp: 1.0
        ))
        let stopEvents = engine.handle(snapshot: snapshot(leftPinch: 0.95, rightPinch: 0.95, timestamp: 2.0))

        #expect(engine.state.loopBuffer.isRecording == false)
        #expect(engine.state.loopBuffer.isPlaying)
        #expect(engine.state.loopBuffer.phrase.count == 1)
        #expect(engine.state.loopBuffer.phrase.first?.chord.symbol == "Cmaj9")
        #expect(engine.state.loopBuffer.phrase.first?.timestamp == 1.0)
        #expect(startEvents.contains {
            if case .loopStateChanged = $0 { return true }
            return false
        })
        #expect(commitEvents.contains {
            if case .chordCommitted = $0 { return true }
            return false
        })
        #expect(stopEvents.contains {
            if case .loopStateChanged = $0 { return true }
            return false
        })
    }

    @Test
    func closedPinchedRightHandStopsPerformance() {
        var engine = PerformanceEngine(keyCenter: .c)

        _ = engine.handle(snapshot: snapshot(rightPinch: 0.94, timestamp: 0.0))
        #expect(engine.state.isPerforming)

        let stopEvents = engine.handle(snapshot: snapshot(
            rightPinch: 0.80,
            rightOpenness: HandOpenness.closed,
            timestamp: 1.0
        ))

        #expect(engine.state.isPerforming == false)
        #expect(stopEvents.contains {
            if case .transportChanged(isPerforming: false, _) = $0 { return true }
            return false
        })
    }

    @Test
    func commitProducesChordEvent() {
        var engine = PerformanceEngine(keyCenter: .c)

        let events = engine.handle(snapshot: snapshot(
            rightPosition: SIMD2<Double>(0.42, -0.12),
            rightPinch: 0.95,
            timestamp: 0.0
        ))

        #expect(events.contains {
            if case .chordCommitted(let chord, _, _, _) = $0 {
                return chord.symbol == engine.state.currentChord.symbol
            }
            return false
        })
    }

    @Test
    func repeatedChordCanStillBeCapturedAfterTimeGap() {
        var engine = PerformanceEngine(keyCenter: .c)

        _ = engine.handle(snapshot: snapshot(leftPinch: 0.95, rightPinch: 0.95, timestamp: 0.0))
        _ = engine.handle(snapshot: snapshot(rightPinch: 0.95, timestamp: 0.8))
        _ = engine.handle(snapshot: snapshot(rightPinch: 0.95, timestamp: 1.35))
        _ = engine.handle(snapshot: snapshot(leftPinch: 0.95, rightPinch: 0.95, timestamp: 2.0))

        #expect(engine.state.loopBuffer.phrase.count == 2)
        #expect(engine.state.loopBuffer.phrase[0].timestamp == 0.8)
        #expect(engine.state.loopBuffer.phrase[1].timestamp == 1.35)
    }

    private func snapshot(
        leftPosition: SIMD2<Double> = SIMD2<Double>(-0.35, 0.2),
        rightPosition: SIMD2<Double> = SIMD2<Double>(0.1, -0.7),
        leftPinch: Double = 0.18,
        rightPinch: Double = 0.18,
        leftOpenness: HandOpenness = .relaxed,
        rightOpenness: HandOpenness = .open,
        timestamp: TimeInterval
    ) -> GestureSnapshot {
        GestureSnapshot(
            leftHand: HandState(
                position: leftPosition,
                pinch: leftPinch,
                openness: leftOpenness,
                verticalVelocity: 0
            ),
            rightHand: HandState(
                position: rightPosition,
                pinch: rightPinch,
                openness: rightOpenness,
                verticalVelocity: -0.2
            ),
            timestamp: timestamp
        )
    }
}
