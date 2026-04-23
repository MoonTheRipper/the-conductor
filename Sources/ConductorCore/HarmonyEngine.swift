import Foundation
import simd

public struct ChordSlot: Identifiable, Equatable, Sendable {
    public var degreeOffset: Int
    public var quality: ChordQuality
    public var function: HarmonicFunction

    public init(
        degreeOffset: Int,
        quality: ChordQuality,
        function: HarmonicFunction
    ) {
        self.degreeOffset = degreeOffset
        self.quality = quality
        self.function = function
    }

    public var id: String {
        "\(degreeOffset)-\(quality.rawValue)-\(function.rawValue)"
    }
}

public struct HarmonyEngine: Sendable {
    public var keyCenter: PitchClass
    public let chordSlots: [ChordSlot]
    public let intervalSlots: [IntervalChoice]

    public init(keyCenter: PitchClass = .c) {
        self.keyCenter = keyCenter
        self.chordSlots = [
            ChordSlot(degreeOffset: 0, quality: .major9, function: .tonic),
            ChordSlot(degreeOffset: 2, quality: .minor9, function: .predominant),
            ChordSlot(degreeOffset: 4, quality: .minor9, function: .color),
            ChordSlot(degreeOffset: 5, quality: .major7Sharp11, function: .predominant),
            ChordSlot(degreeOffset: 7, quality: .dominant13, function: .dominant),
            ChordSlot(degreeOffset: 9, quality: .minor9, function: .tonic),
            ChordSlot(degreeOffset: 11, quality: .halfDiminished, function: .dominant),
            ChordSlot(degreeOffset: 10, quality: .major6Add9, function: .borrowed),
            ChordSlot(degreeOffset: 5, quality: .minor6, function: .borrowed),
            ChordSlot(degreeOffset: 3, quality: .major9, function: .borrowed),
            ChordSlot(degreeOffset: 2, quality: .dominant13, function: .color),
            ChordSlot(degreeOffset: 8, quality: .major6Add9, function: .borrowed),
        ]
        self.intervalSlots = IntervalChoice.allCases
    }

    public var chordLabels: [String] {
        chordSlots.map {
            ChordSelection(
                root: keyCenter.transposed(by: $0.degreeOffset),
                quality: $0.quality,
                function: $0.function
            ).symbol
        }
    }

    public var intervalLabels: [String] {
        intervalSlots.map(\.displayName)
    }

    public func chordSelection(for normalizedPoint: SIMD2<Double>) -> (ChordSelection, PlotPosition) {
        let index = slotIndex(for: normalizedPoint, slotCount: chordSlots.count)
        let slot = chordSlots[index]
        let selection = ChordSelection(
            root: keyCenter.transposed(by: slot.degreeOffset),
            quality: slot.quality,
            function: slot.function
        )
        return (selection, plotPosition(for: normalizedPoint, index: index, slotCount: chordSlots.count))
    }

    public func intervalSelection(for normalizedPoint: SIMD2<Double>) -> (IntervalChoice, PlotPosition) {
        let index = slotIndex(for: normalizedPoint, slotCount: intervalSlots.count)
        let selection = intervalSlots[index]
        return (selection, plotPosition(for: normalizedPoint, index: index, slotCount: intervalSlots.count))
    }

    private func slotIndex(for point: SIMD2<Double>, slotCount: Int) -> Int {
        let angle = normalizedAngle(for: point)
        let sectorSize = (2.0 * Double.pi) / Double(slotCount)
        return Int(angle / sectorSize) % slotCount
    }

    private func plotPosition(for point: SIMD2<Double>, index: Int, slotCount: Int) -> PlotPosition {
        let safeRadius = clamped(simd_length(point), lower: 0.25, upper: 1.0)
        let sectorSize = (2.0 * Double.pi) / Double(slotCount)
        let angle = (Double(index) + 0.5) * sectorSize
        let normalized = SIMD2<Double>(
            x: sin(angle) * safeRadius,
            y: -cos(angle) * safeRadius
        )
        return PlotPosition(angle: angle, radius: safeRadius, normalized: normalized)
    }

    private func normalizedAngle(for point: SIMD2<Double>) -> Double {
        let point = simd_length(point) < 0.001 ? SIMD2<Double>(0, -1) : point
        let angle = atan2(point.x, -point.y)
        return angle >= 0 ? angle : angle + (2.0 * Double.pi)
    }
}

func clamped(_ value: Double, lower: Double = 0.0, upper: Double = 1.0) -> Double {
    min(max(value, lower), upper)
}
