import ConductorCore
import Foundation
import Testing
@testable import TheConductorApp

struct LiveGestureGateTests {
    @Test
    func commitGestureFiresOnceUntilReleased() {
        var gate = LiveGestureGate()

        let armed = GestureSnapshot(
            leftHand: nil,
            rightHand: HandState(
                position: SIMD2<Double>(0.1, -0.4),
                pinch: 0.95,
                openness: .open,
                verticalVelocity: 0,
                spread: 0.7,
                roll: 0,
                downbeatConfidence: 0.2
            ),
            timestamp: 0.0
        )

        let firstPass = gate.process(armed)
        #expect((firstPass.rightHand?.pinch ?? 1) <= 0.82)

        let firePass = gate.process(GestureSnapshot(leftHand: nil, rightHand: armed.rightHand, timestamp: 0.12))
        #expect((firePass.rightHand?.pinch ?? 0) > 0.82)

        let heldPass = gate.process(GestureSnapshot(leftHand: nil, rightHand: armed.rightHand, timestamp: 0.28))
        #expect((heldPass.rightHand?.pinch ?? 1) <= 0.82)

        let released = GestureSnapshot(
            leftHand: nil,
            rightHand: HandState(
                position: SIMD2<Double>(0.1, -0.4),
                pinch: 0.2,
                openness: .relaxed,
                verticalVelocity: 0,
                spread: 0.6,
                roll: 0,
                downbeatConfidence: 0.2
            ),
            timestamp: 0.6
        )
        _ = gate.process(released)

        let secondFire = gate.process(GestureSnapshot(leftHand: nil, rightHand: armed.rightHand, timestamp: 0.74))
        #expect((secondFire.rightHand?.pinch ?? 1) <= 0.82)
        let secondHeldFire = gate.process(GestureSnapshot(leftHand: nil, rightHand: armed.rightHand, timestamp: 0.86))
        #expect((secondHeldFire.rightHand?.pinch ?? 0) > 0.82)
    }

    @Test
    func openHandDownbeatRequiresStableHold() {
        var gate = LiveGestureGate()

        let downbeat = HandState(
            position: SIMD2<Double>(0, -0.7),
            pinch: 0.2,
            openness: .open,
            verticalVelocity: -1.0,
            spread: 0.85,
            roll: 0,
            downbeatConfidence: 0.92
        )

        let firstPass = gate.process(GestureSnapshot(leftHand: nil, rightHand: downbeat, timestamp: 0.0))
        #expect(firstPass.rightHand?.openness == .relaxed)

        let firePass = gate.process(GestureSnapshot(leftHand: nil, rightHand: downbeat, timestamp: 0.12))
        #expect(firePass.rightHand?.openness == .open)

        let repeatedPass = gate.process(GestureSnapshot(leftHand: nil, rightHand: downbeat, timestamp: 0.32))
        #expect(repeatedPass.rightHand?.openness == .relaxed)
    }
}
