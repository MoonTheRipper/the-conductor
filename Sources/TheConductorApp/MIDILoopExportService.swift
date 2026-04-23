import AppKit
import ConductorCore
import Foundation
import UniformTypeIdentifiers

@MainActor
final class MIDILoopExportService {
    private let pulsesPerQuarterNote: UInt16 = 480

    func export(loopBuffer: LoopBuffer, layers: [LayerState], options: MIDIExportOptions) throws -> URL {
        guard loopBuffer.phrase.isEmpty == false else {
            throw ExportError.noLoop
        }

        let panel = NSSavePanel()
        panel.title = "Export MIDI Loop"
        panel.prompt = "Export MIDI"
        panel.nameFieldStringValue = "\(options.clipName).mid"
        if let midiType = UTType(filenameExtension: "mid") {
            panel.allowedContentTypes = [midiType]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            throw ExportError.cancelled
        }

        let data = buildMIDIFile(loopBuffer: loopBuffer, layers: layers, options: options)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func buildMIDIFile(loopBuffer: LoopBuffer, layers: [LayerState], options: MIDIExportOptions) -> Data {
        let tracks = buildTracks(loopBuffer: loopBuffer, layers: layers, options: options)

        var file = Data()
        file.append(ascii: "MThd")
        file.append(uint32: 6)
        file.append(uint16: 1)
        file.append(uint16: UInt16(tracks.count))
        file.append(uint16: pulsesPerQuarterNote)

        for track in tracks {
            file.append(ascii: "MTrk")
            file.append(uint32: UInt32(track.count))
            file.append(track)
        }
        return file
    }

    private func buildTracks(loopBuffer: LoopBuffer, layers: [LayerState], options: MIDIExportOptions) -> [Data] {
        var tracks: [Data] = [buildTempoTrack(loopBuffer: loopBuffer, options: options)]

        for layerName in PerformanceLayerPlanner.layerNames {
            let track = buildLayerTrack(
                loopBuffer: loopBuffer,
                layers: layers,
                layerName: layerName,
                options: options
            )
            if track.isEmpty == false {
                tracks.append(track)
            }
        }

        return tracks
    }

    private func buildTempoTrack(loopBuffer: LoopBuffer, options: MIDIExportOptions) -> Data {
        let ticksPerSecond = Double(pulsesPerQuarterNote) * 2.0
        let loopStart = loopBuffer.startTimestamp ?? loopBuffer.phrase.first?.timestamp ?? 0.0
        let singleLoopDuration = max(
            (loopBuffer.endTimestamp ?? loopBuffer.phrase.last?.timestamp ?? loopStart) - loopStart,
            0.5
        )
        let loopDuration = singleLoopDuration * Double(max(options.repeatCount, 1))
        let microsecondsPerQuarterNote = UInt32((60.0 / max(options.tempoBPM, 30)) * 1_000_000)

        let endTick = Int(loopDuration * ticksPerSecond) + 1
        let events = [
            MIDIEvent(
                tick: 0,
                sortOrder: 0,
                bytes: [0xFF, 0x51, 0x03] + Array(microsecondsPerQuarterNote.bigEndianBytes.suffix(3))
            ),
            MIDIEvent(
                tick: 0,
                sortOrder: 1,
                bytes: trackNameMetaEvent("Conductor Tempo")
            ),
            MIDIEvent(
                tick: endTick,
                sortOrder: 9,
                bytes: [0xFF, 0x2F, 0x00]
            ),
        ]

        return serializeTrack(events)
    }

    private func buildLayerTrack(
        loopBuffer: LoopBuffer,
        layers: [LayerState],
        layerName: String,
        options: MIDIExportOptions
    ) -> Data {
        let ticksPerSecond = Double(pulsesPerQuarterNote) * 2.0
        let loopStart = loopBuffer.startTimestamp ?? loopBuffer.phrase.first?.timestamp ?? 0.0
        let singleLoopDuration = max(
            (loopBuffer.endTimestamp ?? loopBuffer.phrase.last?.timestamp ?? loopStart) - loopStart,
            0.5
        )
        let loopDuration = singleLoopDuration * Double(max(options.repeatCount, 1))

        guard let channel = PerformanceLayerPlanner.channel(for: layerName) else {
            return Data()
        }

        var events: [MIDIEvent] = [
            MIDIEvent(tick: 0, sortOrder: 0, bytes: trackNameMetaEvent(layerName)),
        ]

        for repeatIndex in 0..<max(options.repeatCount, 1) {
            let cycleOffset = singleLoopDuration * Double(repeatIndex)

            for phraseEvent in loopBuffer.phrase {
                let payload = PerformanceLayerPlanner.payloads(
                    chord: phraseEvent.chord,
                    interval: phraseEvent.interval,
                    dynamics: phraseEvent.dynamics,
                    layers: layers
                ).first(where: { $0.name == layerName })

                guard let payload else { continue }

                let eventTick = Int(max(0.0, phraseEvent.timestamp - loopStart + cycleOffset) * ticksPerSecond)
                let holdDuration = 0.45 + (phraseEvent.dynamics * 0.65)
                let noteOffTick = Int(
                    min(loopDuration, max(0.1, phraseEvent.timestamp - loopStart + cycleOffset + holdDuration)) * ticksPerSecond
                )

                for note in payload.notes {
                    events.append(
                        MIDIEvent(
                            tick: eventTick,
                            sortOrder: 1,
                            bytes: [0x90 | channel, note, payload.velocity]
                        )
                    )
                    events.append(
                        MIDIEvent(
                            tick: noteOffTick,
                            sortOrder: 0,
                            bytes: [0x80 | channel, note, 0]
                        )
                    )
                }
            }
        }

        guard events.count > 1 else {
            return Data()
        }

        let endTick = max(events.map(\.tick).max() ?? 0, Int(loopDuration * ticksPerSecond)) + 1
        events.append(MIDIEvent(tick: endTick, sortOrder: 9, bytes: [0xFF, 0x2F, 0x00]))
        return serializeTrack(events)
    }

    private func serializeTrack(_ events: [MIDIEvent]) -> Data {
        let sortedEvents = events.sorted {
            if $0.tick != $1.tick {
                return $0.tick < $1.tick
            }
            return $0.sortOrder < $1.sortOrder
        }

        var track = Data()
        var previousTick = 0
        for event in sortedEvents {
            track.append(contentsOf: variableLengthQuantity(event.tick - previousTick))
            track.append(contentsOf: event.bytes)
            previousTick = event.tick
        }

        return track
    }

    private func trackNameMetaEvent(_ trackName: String) -> [UInt8] {
        let bytes = Array(trackName.utf8.prefix(127))
        return [0xFF, 0x03, UInt8(bytes.count)] + bytes
    }

    private func variableLengthQuantity(_ value: Int) -> [UInt8] {
        var buffer = [UInt8(value & 0x7F)]
        var remaining = value >> 7

        while remaining > 0 {
            buffer.insert(UInt8((remaining & 0x7F) | 0x80), at: 0)
            remaining >>= 7
        }

        return buffer
    }
}

private struct MIDIEvent {
    let tick: Int
    let sortOrder: Int
    let bytes: [UInt8]
}

enum ExportError: LocalizedError {
    case noLoop
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noLoop:
            return "No loop is available to export."
        case .cancelled:
            return "MIDI export was cancelled."
        }
    }
}

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        Swift.withUnsafeBytes(of: bigEndian, Array.init)
    }
}

private extension Data {
    mutating func append(uint16: UInt16) {
        append(contentsOf: Swift.withUnsafeBytes(of: uint16.bigEndian, Array.init))
    }

    mutating func append(uint32: UInt32) {
        append(contentsOf: Swift.withUnsafeBytes(of: uint32.bigEndian, Array.init))
    }

    mutating func append(ascii string: String) {
        append(contentsOf: string.utf8)
    }
}
