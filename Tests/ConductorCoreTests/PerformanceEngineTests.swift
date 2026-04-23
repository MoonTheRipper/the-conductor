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

        engine.handle(snapshot: snapshot(leftPinch: 0.95, rightPinch: 0.95, timestamp: 0.0))
        engine.handle(snapshot: snapshot(
            leftPosition: SIMD2<Double>(-0.4, 0.1),
            rightPosition: SIMD2<Double>(0, -1),
            leftPinch: 0.18,
            rightPinch: 0.94,
            timestamp: 1.0
        ))
        engine.handle(snapshot: snapshot(leftPinch: 0.95, rightPinch: 0.95, timestamp: 2.0))

        #expect(engine.state.loopBuffer.isRecording == false)
        #expect(engine.state.loopBuffer.isPlaying)
        #expect(engine.state.loopBuffer.phrase.count == 1)
    }

    @Test
    func closedPinchedRightHandStopsPerformance() {
        var engine = PerformanceEngine(keyCenter: .c)

        engine.handle(snapshot: snapshot(rightPinch: 0.94, timestamp: 0.0))
        #expect(engine.state.isPerforming)

        engine.handle(snapshot: snapshot(
            rightPinch: 0.80,
            rightOpenness: HandOpenness.closed,
            timestamp: 1.0
        ))

        #expect(engine.state.isPerforming == false)
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
