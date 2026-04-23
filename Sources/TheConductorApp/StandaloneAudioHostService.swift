import AVFoundation
import AudioToolbox
import ConductorCore
import Foundation

struct LayerHostedInstrumentSelection {
    let layerName: String
    let instrument: InstrumentDescriptor?
    let audioUnitDescription: AudioComponentDescription?
    let sampleLibraryLoadPlan: SampleLibraryLoadPlan?
    let capabilitySummary: String
}

private enum HostedLayerKind {
    case audioUnit
    case sampler

    var displayName: String {
        switch self {
        case .audioUnit:
            return "Audio Unit"
        case .sampler:
            return "Sampler"
        }
    }
}

private struct HostedLayerSlot {
    let layerName: String
    let instrumentID: String
    let instrumentName: String
    let hostedKind: HostedLayerKind
    let busLabel: String
    let hostSummaryText: String
    let midiInstrument: AVAudioUnitMIDIInstrument
}

@MainActor
final class StandaloneAudioHostService: ObservableObject {
    @Published private(set) var statusText = "Standalone host idle"
    @Published private(set) var supportText = "No layer assignments"
    @Published private(set) var loadedInstrumentName: String?
    @Published private(set) var loadedLayerNames: [String: String] = [:]
    @Published private(set) var layerTopologyText: [String: String] = [:]
    @Published private(set) var isEngineRunning = false
    @Published private(set) var isInstrumentLoaded = false

    private let engine = AVAudioEngine()
    private var layerSlotsByName: [String: HostedLayerSlot] = [:]
    private var noteGeneration = 0
    private var activeNotesByLayer: [String: Set<UInt8>] = [:]

    init() {
        startEngineIfNeeded()
    }

    func configureAssignments(_ selections: [LayerHostedInstrumentSelection]) {
        startEngineIfNeeded()

        let desiredLayers = Set(selections.map(\.layerName))
        for layerName in Set(layerSlotsByName.keys).subtracting(desiredLayers) {
            unloadSlot(for: layerName)
        }

        var unsupportedAssignments: [String] = []
        var readyLayers: [String] = []

        for selection in selections {
            guard let instrument = selection.instrument else {
                unloadSlot(for: selection.layerName)
                continue
            }

            if let existingSlot = layerSlotsByName[selection.layerName], existingSlot.instrumentID == instrument.id {
                readyLayers.append(selection.layerName)
                continue
            }

            switch instrument.format {
            case .audioUnit:
                guard let description = selection.audioUnitDescription else {
                    unloadSlot(for: selection.layerName)
                    unsupportedAssignments.append("\(selection.layerName): \(selection.capabilitySummary)")
                    continue
                }

                loadAudioUnit(
                    layerName: selection.layerName,
                    instrumentID: instrument.id,
                    instrumentName: instrument.name,
                    description: description
                )
                readyLayers.append(selection.layerName)
            case .sampleLibrary:
                guard let sampleLibraryLoadPlan = selection.sampleLibraryLoadPlan,
                      sampleLibraryLoadPlan.isPlayableNow else {
                    unloadSlot(for: selection.layerName)
                    unsupportedAssignments.append("\(selection.layerName): \(selection.capabilitySummary)")
                    continue
                }

                loadSampleLibrary(
                    layerName: selection.layerName,
                    instrumentID: instrument.id,
                    instrumentName: instrument.name,
                    loadPlan: sampleLibraryLoadPlan
                )
                readyLayers.append(selection.layerName)
            case .vst3:
                unloadSlot(for: selection.layerName)
                unsupportedAssignments.append("\(selection.layerName): \(selection.capabilitySummary)")
            }
        }

        if readyLayers.isEmpty {
            statusText = selections.contains(where: { $0.instrument != nil })
                ? "No hostable standalone targets assigned to active layers"
                : "No standalone layer targets selected"
        } else {
            statusText = "Ready on \(readyLayers.count) layer\(readyLayers.count == 1 ? "" : "s")"
        }

        supportText = unsupportedAssignments.isEmpty
            ? supportSummary(assignedCount: selections.filter { $0.instrument != nil }.count)
            : unsupportedAssignments.joined(separator: " | ")

        updatePublishedState()
    }

    func send(
        chord: ChordSelection,
        interval: IntervalChoice,
        dynamics: Double,
        layers: [LayerState]
    ) {
        guard layerSlotsByName.isEmpty == false else {
            statusText = "No standalone targets loaded for playback"
            return
        }

        startEngineIfNeeded()

        let payloads = PerformanceLayerPlanner.payloads(
            chord: chord,
            interval: interval,
            dynamics: dynamics,
            layers: layers
        )

        guard payloads.isEmpty == false else {
            statusText = "No enabled layers to render in standalone mode"
            return
        }

        noteGeneration += 1
        let generation = noteGeneration
        silenceAllNotes()

        var renderedLayers: [String] = []
        var missingLayers: [String] = []

        for payload in payloads {
            guard let slot = layerSlotsByName[payload.name] else {
                missingLayers.append(payload.name)
                continue
            }

            renderedLayers.append(payload.name)
            for note in payload.notes {
                slot.midiInstrument.startNote(note, withVelocity: payload.velocity, onChannel: payload.channel)
                activeNotesByLayer[payload.name, default: []].insert(note)
            }
        }

        guard renderedLayers.isEmpty == false else {
            statusText = "Enabled layers have no loaded Audio Unit assignments"
            return
        }

        let holdDuration = 0.45 + (dynamics * 0.65)
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) { [weak self] in
            guard let self, self.noteGeneration == generation else { return }
            Task { @MainActor in
                self.silenceAllNotes()
            }
        }

        let renderedSummary = renderedLayers.sorted().joined(separator: ", ")
        if missingLayers.isEmpty {
            statusText = "Played \(chord.symbol) on \(renderedSummary)"
        } else {
            statusText = "Played \(chord.symbol) on \(renderedSummary) · missing \(missingLayers.sorted().joined(separator: ", "))"
        }
    }

    func silenceAllNotes() {
        noteGeneration += 1

        for layerName in PerformanceLayerPlanner.layerNames {
            silenceNotes(for: layerName)
        }

        activeNotesByLayer.removeAll()
        statusText = loadedInstrumentName.map { "Stopped notes on \($0)" } ?? "Stopped notes"
    }

    func unloadAll() {
        silenceAllNotes()
        for layerName in Array(layerSlotsByName.keys) {
            unloadSlot(for: layerName)
        }
        updatePublishedState()
        statusText = "Unloaded standalone layer assignments"
        supportText = "No layer assignments"
    }

    private func supportSummary(assignedCount: Int) -> String {
        let loadedCount = layerSlotsByName.count
        if assignedCount == 0 {
            return "Assign Audio Units or library folders to orchestration layers to play them directly"
        }
        return "\(loadedCount)/\(assignedCount) assigned layer\(assignedCount == 1 ? "" : "s") loaded"
    }

    private func loadAudioUnit(
        layerName: String,
        instrumentID: String,
        instrumentName: String,
        description: AudioComponentDescription
    ) {
        unloadSlot(for: layerName)
        startEngineIfNeeded()

        let instrument = AVAudioUnitMIDIInstrument(audioComponentDescription: description)
        engine.attach(instrument)
        engine.connect(instrument, to: engine.mainMixerNode, format: nil)
        startEngineIfNeeded()

        layerSlotsByName[layerName] = HostedLayerSlot(
            layerName: layerName,
            instrumentID: instrumentID,
            instrumentName: instrumentName,
            hostedKind: .audioUnit,
            busLabel: busLabel(for: layerName),
            hostSummaryText: "Audio Unit -> \(busLabel(for: layerName))",
            midiInstrument: instrument
        )
        updatePublishedState()
    }

    private func loadSampleLibrary(
        layerName: String,
        instrumentID: String,
        instrumentName: String,
        loadPlan: SampleLibraryLoadPlan
    ) {
        unloadSlot(for: layerName)
        startEngineIfNeeded()

        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)

        do {
            let resolvedHostSummary = try loadSampleLibrary(into: sampler, with: loadPlan)
            sampler.overallGain = -4
            startEngineIfNeeded()

            layerSlotsByName[layerName] = HostedLayerSlot(
                layerName: layerName,
                instrumentID: instrumentID,
                instrumentName: instrumentName,
                hostedKind: .sampler,
                busLabel: busLabel(for: layerName),
                hostSummaryText: "\(resolvedHostSummary) -> \(busLabel(for: layerName))",
                midiInstrument: sampler
            )
            updatePublishedState()
        } catch {
            engine.disconnectNodeOutput(sampler)
            engine.detach(sampler)
            statusText = "Failed to load \(instrumentName) on \(layerName): \(error.localizedDescription)"
        }
    }

    private func loadSampleLibrary(
        into sampler: AVAudioUnitSampler,
        with loadPlan: SampleLibraryLoadPlan
    ) throws -> String {
        if let presetURL = loadPlan.presetURL {
            do {
                try sampler.loadInstrument(at: presetURL)
                return "Sampler preset: \(presetURL.lastPathComponent)"
            } catch {
                if loadPlan.audioFileURLs.isEmpty == false {
                    try sampler.loadAudioFiles(at: loadPlan.audioFileURLs)
                    return "\(loadPlan.audioFileURLs.count) audio samples fallback"
                }
                throw error
            }
        }

        try sampler.loadAudioFiles(at: loadPlan.audioFileURLs)
        return loadPlan.hostSummaryText
    }

    private func unloadSlot(for layerName: String) {
        silenceNotes(for: layerName)

        guard let slot = layerSlotsByName.removeValue(forKey: layerName) else { return }

        engine.disconnectNodeOutput(slot.midiInstrument)
        engine.detach(slot.midiInstrument)
        activeNotesByLayer.removeValue(forKey: layerName)
        updatePublishedState()
    }

    private func silenceNotes(for layerName: String) {
        guard let slot = layerSlotsByName[layerName] else { return }

        let channel = PerformanceLayerPlanner.channel(for: layerName) ?? 0
        for note in activeNotesByLayer[layerName, default: []] {
            slot.midiInstrument.stopNote(note, onChannel: channel)
        }
        slot.midiInstrument.sendController(123, withValue: 0, onChannel: channel)
        slot.midiInstrument.sendController(120, withValue: 0, onChannel: channel)
        activeNotesByLayer[layerName] = []
    }

    private func updatePublishedState() {
        loadedLayerNames = Dictionary(
            uniqueKeysWithValues: layerSlotsByName.map { ($0.key, $0.value.instrumentName) }
        )
        layerTopologyText = Dictionary(
            uniqueKeysWithValues: layerSlotsByName.map { ($0.key, $0.value.hostSummaryText) }
        )
        loadedInstrumentName = loadedLayerNames.isEmpty
            ? nil
            : loadedLayerNames.keys.sorted().compactMap { layerName in
                guard let slot = layerSlotsByName[layerName] else { return nil }
                return "\(layerName): \(slot.instrumentName) (\(slot.hostedKind.displayName))"
            }.joined(separator: " · ")
        isInstrumentLoaded = loadedLayerNames.isEmpty == false
    }

    private func busLabel(for layerName: String) -> String {
        let channel = Int(PerformanceLayerPlanner.channel(for: layerName) ?? 0) + 1
        return "Main Mixer Bus · ch \(channel)"
    }

    private func startEngineIfNeeded() {
        guard engine.isRunning == false else {
            isEngineRunning = true
            return
        }

        do {
            engine.prepare()
            try engine.start()
            isEngineRunning = true
        } catch {
            isEngineRunning = false
            statusText = "Audio engine failed to start: \(error.localizedDescription)"
        }
    }
}
