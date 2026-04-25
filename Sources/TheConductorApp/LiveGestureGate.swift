import ConductorCore
import Foundation

struct LiveGestureGate {
    private var commitActivationStartedAt: TimeInterval?
    private var loopActivationStartedAt: TimeInterval?
    private var startActivationStartedAt: TimeInterval?
    private var stopActivationStartedAt: TimeInterval?

    private var commitHasFired = false
    private var loopHasFired = false
    private var startHasFired = false
    private var stopHasFired = false

    private var lastCommitFireTimestamp: TimeInterval = -.infinity
    private var lastLoopFireTimestamp: TimeInterval = -.infinity
    private var lastStartFireTimestamp: TimeInterval = -.infinity
    private var lastStopFireTimestamp: TimeInterval = -.infinity

    mutating func process(_ snapshot: GestureSnapshot) -> GestureSnapshot {
        guard var rightHand = snapshot.rightHand else {
            reset()
            return snapshot
        }

        var leftHand = snapshot.leftHand
        let timestamp = snapshot.timestamp

        let loopActive = (leftHand?.pinch ?? 0) > 0.9 && rightHand.pinch > 0.9
        let commitActive = loopActive == false && rightHand.pinch > 0.84 && rightHand.openness != .closed
        let startStrength = max(
            rightHand.downbeatConfidence,
            max(0.0, -rightHand.verticalVelocity * 0.72) + (rightHand.spread * 0.18)
        )
        let startActive = rightHand.openness == .open && startStrength > 0.8
        let stopActive = rightHand.openness == .closed && rightHand.pinch > 0.72

        let fireLoop = Self.evaluate(
            active: loopActive,
            timestamp: timestamp,
            hold: 0.12,
            cooldown: 0.8,
            activationStartedAt: &loopActivationStartedAt,
            hasFired: &loopHasFired,
            lastFireTimestamp: &lastLoopFireTimestamp
        )
        let fireCommit = fireLoop == false && Self.evaluate(
            active: commitActive,
            timestamp: timestamp,
            hold: 0.08,
            cooldown: 0.55,
            activationStartedAt: &commitActivationStartedAt,
            hasFired: &commitHasFired,
            lastFireTimestamp: &lastCommitFireTimestamp
        )
        let fireStart = Self.evaluate(
            active: startActive,
            timestamp: timestamp,
            hold: 0.08,
            cooldown: 0.9,
            activationStartedAt: &startActivationStartedAt,
            hasFired: &startHasFired,
            lastFireTimestamp: &lastStartFireTimestamp
        )
        let fireStop = Self.evaluate(
            active: stopActive,
            timestamp: timestamp,
            hold: 0.12,
            cooldown: 0.9,
            activationStartedAt: &stopActivationStartedAt,
            hasFired: &stopHasFired,
            lastFireTimestamp: &lastStopFireTimestamp
        )

        if fireLoop {
            if var left = leftHand {
                left.pinch = max(left.pinch, 1.0)
                leftHand = left
            }
            rightHand.pinch = max(rightHand.pinch, 1.0)
        } else {
            if var left = leftHand {
                left.pinch = min(left.pinch, 0.35)
                leftHand = left
            }
        }

        if fireStop {
            rightHand.openness = .closed
            rightHand.pinch = max(rightHand.pinch, 0.86)
        } else if fireCommit {
            rightHand.openness = .relaxed
            rightHand.pinch = max(rightHand.pinch, 0.92)
        } else {
            rightHand.pinch = min(rightHand.pinch, 0.35)
        }

        if fireStart {
            rightHand.openness = .open
            rightHand.downbeatConfidence = max(rightHand.downbeatConfidence, 0.95)
        } else if rightHand.openness == .open {
            rightHand.openness = .relaxed
            rightHand.downbeatConfidence = min(rightHand.downbeatConfidence, 0.35)
        } else {
            rightHand.downbeatConfidence = min(rightHand.downbeatConfidence, 0.35)
        }

        return GestureSnapshot(
            leftHand: leftHand,
            rightHand: rightHand,
            timestamp: snapshot.timestamp
        )
    }

    mutating func reset() {
        commitActivationStartedAt = nil
        loopActivationStartedAt = nil
        startActivationStartedAt = nil
        stopActivationStartedAt = nil
        commitHasFired = false
        loopHasFired = false
        startHasFired = false
        stopHasFired = false
        lastCommitFireTimestamp = -.infinity
        lastLoopFireTimestamp = -.infinity
        lastStartFireTimestamp = -.infinity
        lastStopFireTimestamp = -.infinity
    }

    private static func evaluate(
        active: Bool,
        timestamp: TimeInterval,
        hold: TimeInterval,
        cooldown: TimeInterval,
        activationStartedAt: inout TimeInterval?,
        hasFired: inout Bool,
        lastFireTimestamp: inout TimeInterval
    ) -> Bool {
        guard active else {
            activationStartedAt = nil
            hasFired = false
            return false
        }

        if activationStartedAt == nil {
            activationStartedAt = timestamp
        }

        guard hasFired == false else {
            return false
        }

        let activeDuration = timestamp - (activationStartedAt ?? timestamp)
        guard activeDuration >= hold else {
            return false
        }

        guard timestamp - lastFireTimestamp >= cooldown else {
            return false
        }

        hasFired = true
        lastFireTimestamp = timestamp
        return true
    }
}
