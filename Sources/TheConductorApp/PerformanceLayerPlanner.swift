import ConductorCore
import Foundation

struct PlaybackLayerPayload {
    let name: String
    let channel: UInt8
    let notes: [UInt8]
    let velocity: UInt8
}

enum PerformanceLayerPlanner {
    static let layerChannels: [(name: String, channel: UInt8)] = [
        ("Strings", 0),
        ("Brass", 1),
        ("Woods", 2),
        ("Pulse", 3),
    ]

    static var layerNames: [String] {
        layerChannels.map(\.name)
    }

    static var channelMapDescription: [String] {
        layerChannels.map { "\($0.name) -> MIDI ch \($0.channel + 1)" }
    }

    static func channel(for layerName: String) -> UInt8? {
        layerChannels.first(where: { $0.name == layerName })?.channel
    }

    static func payloads(
        chord: ChordSelection,
        interval: IntervalChoice,
        dynamics: Double,
        layers: [LayerState]
    ) -> [PlaybackLayerPayload] {
        layerChannels.compactMap { mapping in
            guard let layer = layers.first(where: { $0.name == mapping.name }) else {
                return nil
            }
            guard layer.isEnabled, layer.mix > 0.12 else {
                return nil
            }

            let notes = voicing(
                for: mapping.name,
                chord: chord,
                interval: interval,
                dynamics: dynamics
            )

            guard notes.isEmpty == false else { return nil }

            let velocity = UInt8(
                max(24, min(124, Int(34 + (dynamics * 48) + (layer.mix * 36))))
            )

            return PlaybackLayerPayload(
                name: mapping.name,
                channel: mapping.channel,
                notes: notes,
                velocity: velocity
            )
        }
    }

    private static func voicing(
        for layerName: String,
        chord: ChordSelection,
        interval: IntervalChoice,
        dynamics: Double
    ) -> [UInt8] {
        let root = 48 + chord.root.rawValue
        let tones = chordToneOffsets(for: chord.quality)
        let third = tones[safe: 1] ?? 4
        let fifth = tones[safe: 2] ?? 7
        let seventh = tones[safe: 3] ?? 10
        let top = interval.rawValue

        let candidateNotes: [Int]
        switch layerName {
        case "Strings":
            candidateNotes = [
                root + 12,
                root + 12 + third,
                root + 12 + fifth,
                root + 12 + top,
                dynamics > 0.72 ? root + 24 : nil,
            ].compactMap { $0 }
        case "Brass":
            candidateNotes = [
                root,
                root + third,
                root + fifth,
                root + seventh,
            ]
        case "Woods":
            candidateNotes = [
                root + 24,
                root + 24 + third,
                root + 24 + top,
            ]
        case "Pulse":
            candidateNotes = [
                max(24, root - 12),
                max(31, root - 5),
                root,
            ]
        default:
            candidateNotes = [root, root + third, root + fifth, root + top]
        }

        let normalized = Set(candidateNotes)
            .filter { 0...127 ~= $0 }
            .sorted()

        return normalized.map(UInt8.init)
    }

    private static func chordToneOffsets(for quality: ChordQuality) -> [Int] {
        switch quality {
        case .major9:
            return [0, 4, 7, 11, 14]
        case .minor9:
            return [0, 3, 7, 10, 14]
        case .dominant13:
            return [0, 4, 7, 10, 14, 21]
        case .suspended2:
            return [0, 2, 7, 14]
        case .suspended4:
            return [0, 5, 7, 10]
        case .diminished7:
            return [0, 3, 6, 9]
        case .halfDiminished:
            return [0, 3, 6, 10]
        case .major7Sharp11:
            return [0, 4, 7, 11, 18]
        case .major6Add9:
            return [0, 4, 7, 9, 14]
        case .minor6:
            return [0, 3, 7, 9]
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
