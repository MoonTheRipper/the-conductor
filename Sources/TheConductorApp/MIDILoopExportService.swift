import AppKit
import ConductorCore
import Foundation
import UniformTypeIdentifiers

@MainActor
final class MIDILoopExportService {
    private let pulsesPerQuarterNote: UInt16 = 480
    private let microsecondsPerQuarterNote: UInt32 = 500_000

    func export(loopBuffer: LoopBuffer, layers: [LayerState]) throws -> URL {
        guard loopBuffer.phrase.isEmpty == false else {
            throw ExportError.noLoop
        }

        let panel = NSSavePanel()
        panel.title = "Export MIDI Loop"
        panel.prompt = "Export MIDI"
        panel.nameFieldStringValue = "The Conductor Loop.mid"
        if let midiType = UTType(filenameExtension: "mid") {
            panel.allowedContentTypes = [midiType]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            throw ExportError.cancelled
        }

        let data = buildMIDIFile(loopBuffer: loopBuffer, layers: layers)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func buildMIDIFile(loopBuffer: LoopBuffer, layers: [LayerState]) -> Data {
        let trackData = buildTrack(loopBuffer: loopBuffer, layers: layers)

        var file = Data()
        file.append(ascii: "MThd")
        file.append(uint32: 6)
        file.append(uint16: 0)
        file.append(uint16: 1)
        file.append(uint16: pulsesPerQuarterNote)

        file.append(ascii: "MTrk")
        file.append(uint32: UInt32(trackData.count))
        file.append(trackData)
        return file
    }

    private func buildTrack(loopBuffer: LoopBuffer, layers: [LayerState]) -> Data {
        let ticksPerSecond = Double(pulsesPerQuarterNote) * 2.0
        let loopStart = loopBuffer.startTimestamp ?? loopBuffer.phrase.first?.timestamp ?? 0.0
        let loopDuration = max(
            (loopBuffer.endTimestamp ?? loopBuffer.phrase.last?.timestamp ?? loopStart) - loopStart,
            0.5
        )

        struct MIDIEvent {
            let tick: Int
            let sortOrder: Int
            let bytes: [UInt8]
        }

        var events: [MIDIEvent] = [
            MIDIEvent(
                tick: 0,
                sortOrder: 0,
                bytes: [0xFF, 0x51, 0x03] + Array(microsecondsPerQuarterNote.bigEndianBytes.suffix(3))
            ),
        ]

        for phraseEvent in loopBuffer.phrase {
            let payloads = PerformanceLayerPlanner.payloads(
                chord: phraseEvent.chord,
                interval: phraseEvent.interval,
                dynamics: phraseEvent.dynamics,
                layers: layers
            )

            let eventTick = Int(max(0.0, phraseEvent.timestamp - loopStart) * ticksPerSecond)
            let holdDuration = 0.45 + (phraseEvent.dynamics * 0.65)
            let noteOffTick = Int(min(loopDuration, max(0.1, phraseEvent.timestamp - loopStart + holdDuration)) * ticksPerSecond)

            for payload in payloads {
                for note in payload.notes {
                    events.append(
                        MIDIEvent(
                            tick: eventTick,
                            sortOrder: 1,
                            bytes: [0x90 | payload.channel, note, payload.velocity]
                        )
                    )
                    events.append(
                        MIDIEvent(
                            tick: noteOffTick,
                            sortOrder: 0,
                            bytes: [0x80 | payload.channel, note, 0]
                        )
                    )
                }
            }
        }

        let endTick = max(events.map(\.tick).max() ?? 0, Int(loopDuration * ticksPerSecond))
        events.append(MIDIEvent(tick: endTick + 1, sortOrder: 9, bytes: [0xFF, 0x2F, 0x00]))
        events.sort {
            if $0.tick != $1.tick {
                return $0.tick < $1.tick
            }
            return $0.sortOrder < $1.sortOrder
        }

        var track = Data()
        var previousTick = 0
        for event in events {
            track.append(contentsOf: variableLengthQuantity(event.tick - previousTick))
            track.append(contentsOf: event.bytes)
            previousTick = event.tick
        }

        return track
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
