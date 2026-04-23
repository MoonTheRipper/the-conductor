import ConductorCore
import Foundation
import simd

struct GestureCalibration: Codable, Equatable, Sendable {
    var centerX: Double
    var centerY: Double
    var horizontalReach: Double
    var verticalReach: Double
    var pinchFloor: Double
    var pinchCeiling: Double
    var velocityScale: Double

    init(
        centerX: Double = 0.0,
        centerY: Double = 0.0,
        horizontalReach: Double = 1.0,
        verticalReach: Double = 1.0,
        pinchFloor: Double = 0.12,
        pinchCeiling: Double = 0.92,
        velocityScale: Double = 1.0
    ) {
        self.centerX = centerX
        self.centerY = centerY
        self.horizontalReach = horizontalReach
        self.verticalReach = verticalReach
        self.pinchFloor = pinchFloor
        self.pinchCeiling = pinchCeiling
        self.velocityScale = velocityScale
    }

    func apply(to snapshot: GestureSnapshot) -> GestureSnapshot {
        GestureSnapshot(
            leftHand: snapshot.leftHand.map(apply(to:)),
            rightHand: snapshot.rightHand.map(apply(to:)),
            timestamp: snapshot.timestamp
        )
    }

    func apply(to hand: HandState) -> HandState {
        HandState(
            position: SIMD2<Double>(
                normalizedAxis(hand.position.x - centerX, reach: horizontalReach),
                normalizedAxis(hand.position.y - centerY, reach: verticalReach)
            ),
            pinch: normalizedPinch(hand.pinch),
            openness: hand.openness,
            verticalVelocity: clamped(hand.verticalVelocity * velocityScale, lower: -1.5, upper: 1.5),
            horizontalVelocity: clamped(hand.horizontalVelocity * velocityScale, lower: -1.5, upper: 1.5),
            spread: clamped(hand.spread),
            roll: clamped(hand.roll, lower: -1.0, upper: 1.0),
            downbeatConfidence: clamped(hand.downbeatConfidence)
        )
    }

    private func normalizedAxis(_ value: Double, reach: Double) -> Double {
        let safeReach = max(0.2, reach)
        return clamped(value / safeReach, lower: -1.0, upper: 1.0)
    }

    private func normalizedPinch(_ pinch: Double) -> Double {
        let safeCeiling = max(pinchFloor + 0.05, pinchCeiling)
        return clamped((pinch - pinchFloor) / (safeCeiling - pinchFloor))
    }

    private func clamped(_ value: Double, lower: Double = 0.0, upper: Double = 1.0) -> Double {
        min(max(value, lower), upper)
    }
}
