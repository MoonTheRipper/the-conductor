import ConductorCore
import Foundation

struct PlaybackLayerPayload {
    let name: String
    let channel: UInt8
    let notes: [UInt8]
    let velocity: UInt8
    let holdDuration: Double
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
        layers: [LayerState],
        performanceSettingsByLayer: [String: LayerPerformanceSettings] = [:]
    ) -> [PlaybackLayerPayload] {
        layerChannels.compactMap { mapping in
            guard let layer = layers.first(where: { $0.name == mapping.name }) else {
                return nil
            }
            guard layer.isEnabled, layer.mix > 0.12 else {
                return nil
            }

            let performanceSettings = performanceSettingsByLayer[mapping.name] ?? .default(for: mapping.name)
            let notes = voicing(
                for: mapping.name,
                chord: chord,
                interval: interval,
                dynamics: dynamics,
                performanceSettings: performanceSettings
            )

            guard notes.isEmpty == false else { return nil }

            let baseVelocity = Double(max(24, min(124, Int(34 + (dynamics * 48) + (layer.mix * 36)))))
            let velocity = UInt8(
                max(
                    18,
                    min(
                        124,
                        Int((baseVelocity * performanceSettings.articulation.velocityMultiplier) + performanceSettings.velocityBias)
                    )
                )
            )
            let baseHoldDuration = 0.45 + (dynamics * 0.65)
            let holdDuration = max(
                0.08,
                min(
                    3.2,
                    baseHoldDuration * performanceSettings.articulation.holdMultiplier * performanceSettings.holdScale
                )
            )

            return PlaybackLayerPayload(
                name: mapping.name,
                channel: mapping.channel,
                notes: notes,
                velocity: velocity,
                holdDuration: holdDuration
            )
        }
    }

    private static func voicing(
        for layerName: String,
        chord: ChordSelection,
        interval: IntervalChoice,
        dynamics: Double,
        performanceSettings: LayerPerformanceSettings
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

        let transposed = Set(candidateNotes.map { $0 + (performanceSettings.octaveShift * 12) })
            .filter { 0...127 ~= $0 }
            .sorted()
        let limited = limitedVoicing(
            transposed,
            maxVoices: max(performanceSettings.maxVoices, 1),
            preferLowerRegister: layerName == "Pulse"
        )

        return limited.map(UInt8.init)
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

    private static func limitedVoicing(
        _ notes: [Int],
        maxVoices: Int,
        preferLowerRegister: Bool
    ) -> [Int] {
        guard notes.count > maxVoices else { return notes }
        guard maxVoices > 0 else { return [] }

        if preferLowerRegister {
            return Array(notes.prefix(maxVoices))
        }

        if maxVoices == 1 {
            return [notes.last ?? notes[0]]
        }

        if maxVoices == 2 {
            return [notes[0], notes[notes.count - 1]]
        }

        let step = Double(notes.count - 1) / Double(maxVoices - 1)
        var selectedIndices = Set([0, notes.count - 1])
        for slot in 1..<(maxVoices - 1) {
            let index = Int((Double(slot) * step).rounded())
            selectedIndices.insert(index)
        }

        return selectedIndices
            .sorted()
            .prefix(maxVoices)
            .map { notes[$0] }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
