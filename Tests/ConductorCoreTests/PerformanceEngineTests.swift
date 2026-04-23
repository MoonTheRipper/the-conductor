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
    func widerRightHandBoostsDynamics() {
        var narrowEngine = PerformanceEngine(keyCenter: .c)
        _ = narrowEngine.handle(snapshot: snapshot(
            rightPosition: SIMD2<Double>(0.05, -0.3),
            rightSpread: 0.2,
            timestamp: 0.0
        ))

        var wideEngine = PerformanceEngine(keyCenter: .c)
        _ = wideEngine.handle(snapshot: snapshot(
            rightPosition: SIMD2<Double>(0.05, -0.3),
            rightSpread: 0.9,
            timestamp: 0.0
        ))

        #expect(wideEngine.state.dynamics > narrowEngine.state.dynamics)
    }

    @Test
    func horizontalMotionBoostsPulseLayerMix() {
        var stillEngine = PerformanceEngine(keyCenter: .c)
        _ = stillEngine.handle(snapshot: snapshot(
            rightHorizontalVelocity: 0.0,
            timestamp: 0.0
        ))

        var movingEngine = PerformanceEngine(keyCenter: .c)
        _ = movingEngine.handle(snapshot: snapshot(
            rightHorizontalVelocity: 1.2,
            timestamp: 0.0
        ))

        let stillPulse = stillEngine.state.layers.first(where: { $0.name == "Pulse" })?.mix ?? 0
        let movingPulse = movingEngine.state.layers.first(where: { $0.name == "Pulse" })?.mix ?? 0
        #expect(movingPulse > stillPulse)
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

    @Test
    func liveDownbeatConfidenceCanEngageTransport() {
        var engine = PerformanceEngine(keyCenter: .c)

        let events = engine.handle(snapshot: snapshot(
            rightVerticalVelocity: -0.34,
            rightSpread: 0.36,
            rightDownbeatConfidence: 0.87,
            timestamp: 0.0
        ))

        #expect(engine.state.isPerforming)
        #expect(events.contains {
            if case .transportChanged(isPerforming: true, _) = $0 { return true }
            return false
        })
    }

    @Test
    func lowDownbeatConfidenceDoesNotEngageTransport() {
        var engine = PerformanceEngine(keyCenter: .c)

        let events = engine.handle(snapshot: snapshot(
            rightVerticalVelocity: -0.12,
            rightSpread: 0.18,
            rightDownbeatConfidence: 0.18,
            timestamp: 0.0
        ))

        #expect(engine.state.isPerforming == false)
        #expect(events.contains {
            if case .transportChanged = $0 { return true }
            return false
        } == false)
    }

    private func snapshot(
        leftPosition: SIMD2<Double> = SIMD2<Double>(-0.35, 0.2),
        rightPosition: SIMD2<Double> = SIMD2<Double>(0.1, -0.7),
        leftPinch: Double = 0.18,
        rightPinch: Double = 0.18,
        leftOpenness: HandOpenness = .relaxed,
        rightOpenness: HandOpenness = .open,
        leftVerticalVelocity: Double = 0,
        rightVerticalVelocity: Double = -0.2,
        leftHorizontalVelocity: Double = 0,
        rightHorizontalVelocity: Double = 0,
        leftSpread: Double = 0.45,
        rightSpread: Double = 0.45,
        leftRoll: Double = 0,
        rightRoll: Double = 0,
        leftDownbeatConfidence: Double = 0,
        rightDownbeatConfidence: Double = 0,
        timestamp: TimeInterval
    ) -> GestureSnapshot {
        GestureSnapshot(
            leftHand: HandState(
                position: leftPosition,
                pinch: leftPinch,
                openness: leftOpenness,
                verticalVelocity: leftVerticalVelocity,
                horizontalVelocity: leftHorizontalVelocity,
                spread: leftSpread,
                roll: leftRoll,
                downbeatConfidence: leftDownbeatConfidence
            ),
            rightHand: HandState(
                position: rightPosition,
                pinch: rightPinch,
                openness: rightOpenness,
                verticalVelocity: rightVerticalVelocity,
                horizontalVelocity: rightHorizontalVelocity,
                spread: rightSpread,
                roll: rightRoll,
                downbeatConfidence: rightDownbeatConfidence
            ),
            timestamp: timestamp
        )
    }
}
