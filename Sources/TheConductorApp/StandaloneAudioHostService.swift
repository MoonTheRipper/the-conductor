import AVFoundation
import AudioToolbox
import ConductorCore
import Foundation

struct LayerHostedInstrumentSelection {
    let layerName: String
    let instrument: InstrumentDescriptor?
    let selectionSignature: String
    let audioUnitDescription: AudioComponentDescription?
    let sampleLibraryLoadPlan: SampleLibraryLoadPlan?
    let performanceSettings: LayerPerformanceSettings
    let outputSettings: LayerOutputSettings
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

private final class HostedLayerSlot {
    let layerName: String
    let instrumentID: String
    let selectionSignature: String
    let instrumentName: String
    let hostedKind: HostedLayerKind
    let sourceSummaryText: String
    let midiInstrument: AVAudioUnitMIDIInstrument
    let layerMixer: AVAudioMixerNode
    let delay: AVAudioUnitDelay
    let reverb: AVAudioUnitReverb
    var performanceSettings: LayerPerformanceSettings
    var outputSettings: LayerOutputSettings

    init(
        layerName: String,
        instrumentID: String,
        selectionSignature: String,
        instrumentName: String,
        hostedKind: HostedLayerKind,
        sourceSummaryText: String,
        midiInstrument: AVAudioUnitMIDIInstrument,
        layerMixer: AVAudioMixerNode,
        delay: AVAudioUnitDelay,
        reverb: AVAudioUnitReverb,
        performanceSettings: LayerPerformanceSettings,
        outputSettings: LayerOutputSettings
    ) {
        self.layerName = layerName
        self.instrumentID = instrumentID
        self.selectionSignature = selectionSignature
        self.instrumentName = instrumentName
        self.hostedKind = hostedKind
        self.sourceSummaryText = sourceSummaryText
        self.midiInstrument = midiInstrument
        self.layerMixer = layerMixer
        self.delay = delay
        self.reverb = reverb
        self.performanceSettings = performanceSettings
        self.outputSettings = outputSettings
    }

    var topologyText: String {
        "\(sourceSummaryText) -> \(outputSettings.bus.rawValue) bus · \(performanceSettings.topologyText) · pan \(Int(outputSettings.pan * 100)) · space \(Int(outputSettings.reverbMix))% · echo \(Int(outputSettings.delayMix))%"
    }
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
    private var busMixersByID: [LayerOutputBus: AVAudioMixerNode] = [:]
    private var noteGeneration = 0
    private var activeNotesByLayer: [String: Set<UInt8>] = [:]

    init() {
        setupBusMixersIfNeeded()
        startEngineIfNeeded()
    }

    func configureAssignments(_ selections: [LayerHostedInstrumentSelection]) {
        setupBusMixersIfNeeded()
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

            if let existingSlot = layerSlotsByName[selection.layerName],
               existingSlot.selectionSignature == selection.selectionSignature,
               matchesHostedKind(of: existingSlot, for: instrument) {
                existingSlot.performanceSettings = selection.performanceSettings
                applyOutputSettings(selection.outputSettings, to: existingSlot)
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
                    selectionSignature: selection.selectionSignature,
                    instrumentName: instrument.name,
                    description: description,
                    performanceSettings: selection.performanceSettings,
                    outputSettings: selection.outputSettings
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
                    selectionSignature: selection.selectionSignature,
                    instrumentName: sampleLibraryLoadPlan.displayName,
                    loadPlan: sampleLibraryLoadPlan,
                    performanceSettings: selection.performanceSettings,
                    outputSettings: selection.outputSettings
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
        layers: [LayerState],
        performanceSettingsByLayer: [String: LayerPerformanceSettings]
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
            layers: layers,
            performanceSettingsByLayer: performanceSettingsByLayer
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
            statusText = "Enabled layers have no loaded standalone assignments"
            return
        }

        for payload in payloads {
            DispatchQueue.main.asyncAfter(deadline: .now() + payload.holdDuration) { [weak self] in
                guard let self, self.noteGeneration == generation else { return }
                Task { @MainActor in
                    self.silenceNotes(for: payload.name)
                }
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

    private func matchesHostedKind(of slot: HostedLayerSlot, for instrument: InstrumentDescriptor) -> Bool {
        switch (slot.hostedKind, instrument.format) {
        case (.audioUnit, .audioUnit), (.sampler, .sampleLibrary):
            return true
        default:
            return false
        }
    }

    private func supportSummary(assignedCount: Int) -> String {
        let loadedCount = layerSlotsByName.count
        if assignedCount == 0 {
            return "Assign Audio Units or library folders to orchestration layers to play them directly"
        }
        return "\(loadedCount)/\(assignedCount) assigned layer\(assignedCount == 1 ? "" : "s") loaded"
    }

    private func setupBusMixersIfNeeded() {
        for bus in LayerOutputBus.allCases where busMixersByID[bus] == nil {
            let mixer = AVAudioMixerNode()
            engine.attach(mixer)
            engine.connect(mixer, to: engine.mainMixerNode, format: nil)
            mixer.outputVolume = bus.defaultVolume
            busMixersByID[bus] = mixer
        }
    }

    private func loadAudioUnit(
        layerName: String,
        instrumentID: String,
        selectionSignature: String,
        instrumentName: String,
        description: AudioComponentDescription,
        performanceSettings: LayerPerformanceSettings,
        outputSettings: LayerOutputSettings
    ) {
        unloadSlot(for: layerName)
        startEngineIfNeeded()

        let instrument = AVAudioUnitMIDIInstrument(audioComponentDescription: description)
        let layerMixer = AVAudioMixerNode()
        let delay = AVAudioUnitDelay()
        let reverb = AVAudioUnitReverb()
        configureHostedNodes(
            midiInstrument: instrument,
            layerMixer: layerMixer,
            delay: delay,
            reverb: reverb,
            outputSettings: outputSettings
        )

        let slot = HostedLayerSlot(
            layerName: layerName,
            instrumentID: instrumentID,
            selectionSignature: selectionSignature,
            instrumentName: instrumentName,
            hostedKind: .audioUnit,
            sourceSummaryText: "Audio Unit",
            midiInstrument: instrument,
            layerMixer: layerMixer,
            delay: delay,
            reverb: reverb,
            performanceSettings: performanceSettings,
            outputSettings: outputSettings
        )

        layerSlotsByName[layerName] = slot
        applyOutputSettings(outputSettings, to: slot)
        updatePublishedState()
    }

    private func loadSampleLibrary(
        layerName: String,
        instrumentID: String,
        selectionSignature: String,
        instrumentName: String,
        loadPlan: SampleLibraryLoadPlan,
        performanceSettings: LayerPerformanceSettings,
        outputSettings: LayerOutputSettings
    ) {
        unloadSlot(for: layerName)
        startEngineIfNeeded()

        let sampler = AVAudioUnitSampler()
        let layerMixer = AVAudioMixerNode()
        let delay = AVAudioUnitDelay()
        let reverb = AVAudioUnitReverb()
        configureHostedNodes(
            midiInstrument: sampler,
            layerMixer: layerMixer,
            delay: delay,
            reverb: reverb,
            outputSettings: outputSettings
        )

        do {
            let resolvedHostSummary = try loadSampleLibrary(into: sampler, with: loadPlan)
            sampler.overallGain = -4
            startEngineIfNeeded()

            let slot = HostedLayerSlot(
                layerName: layerName,
                instrumentID: instrumentID,
                selectionSignature: selectionSignature,
                instrumentName: instrumentName,
                hostedKind: .sampler,
                sourceSummaryText: resolvedHostSummary,
                midiInstrument: sampler,
                layerMixer: layerMixer,
                delay: delay,
                reverb: reverb,
                performanceSettings: performanceSettings,
                outputSettings: outputSettings
            )

            layerSlotsByName[layerName] = slot
            applyOutputSettings(outputSettings, to: slot)
            updatePublishedState()
        } catch {
            teardownNodes(midiInstrument: sampler, layerMixer: layerMixer, delay: delay, reverb: reverb)
            statusText = "Failed to load \(instrumentName) on \(layerName): \(error.localizedDescription)"
        }
    }

    private func configureHostedNodes(
        midiInstrument: AVAudioUnitMIDIInstrument,
        layerMixer: AVAudioMixerNode,
        delay: AVAudioUnitDelay,
        reverb: AVAudioUnitReverb,
        outputSettings: LayerOutputSettings
    ) {
        engine.attach(midiInstrument)
        engine.attach(layerMixer)
        engine.attach(delay)
        engine.attach(reverb)

        reverb.loadFactoryPreset(.mediumHall)
        delay.feedback = 18
        delay.lowPassCutoff = 15_000

        engine.connect(midiInstrument, to: layerMixer, format: nil)
        engine.connect(layerMixer, to: delay, format: nil)
        engine.connect(delay, to: reverb, format: nil)
        engine.connect(reverb, to: busMixer(for: outputSettings.bus), format: nil)

        startEngineIfNeeded()
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

        teardownNodes(
            midiInstrument: slot.midiInstrument,
            layerMixer: slot.layerMixer,
            delay: slot.delay,
            reverb: slot.reverb
        )
        activeNotesByLayer.removeValue(forKey: layerName)
        updatePublishedState()
    }

    private func teardownNodes(
        midiInstrument: AVAudioUnitMIDIInstrument,
        layerMixer: AVAudioMixerNode,
        delay: AVAudioUnitDelay,
        reverb: AVAudioUnitReverb
    ) {
        engine.disconnectNodeOutput(midiInstrument)
        engine.disconnectNodeOutput(layerMixer)
        engine.disconnectNodeOutput(delay)
        engine.disconnectNodeOutput(reverb)
        engine.detach(midiInstrument)
        engine.detach(layerMixer)
        engine.detach(delay)
        engine.detach(reverb)
    }

    private func applyOutputSettings(_ outputSettings: LayerOutputSettings, to slot: HostedLayerSlot) {
        if slot.outputSettings.bus != outputSettings.bus {
            engine.disconnectNodeOutput(slot.reverb)
            engine.connect(slot.reverb, to: busMixer(for: outputSettings.bus), format: nil)
        }

        slot.outputSettings = outputSettings
        slot.layerMixer.pan = Float(outputSettings.pan)
        slot.delay.wetDryMix = Float(outputSettings.delayMix)
        slot.delay.delayTime = outputSettings.delayTime
        slot.delay.feedback = Float(min(max(outputSettings.delayMix * 0.55, 0), 48))
        slot.reverb.wetDryMix = Float(outputSettings.reverbMix)
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
            uniqueKeysWithValues: layerSlotsByName.map { ($0.key, $0.value.topologyText) }
        )
        loadedInstrumentName = loadedLayerNames.isEmpty
            ? nil
            : loadedLayerNames.keys.sorted().compactMap { layerName in
                guard let slot = layerSlotsByName[layerName] else { return nil }
                return "\(layerName): \(slot.instrumentName) (\(slot.hostedKind.displayName))"
            }.joined(separator: " · ")
        isInstrumentLoaded = loadedLayerNames.isEmpty == false
    }

    private func busMixer(for bus: LayerOutputBus) -> AVAudioMixerNode {
        setupBusMixersIfNeeded()
        return busMixersByID[bus] ?? engine.mainMixerNode
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

private extension LayerOutputBus {
    var defaultVolume: Float {
        switch self {
        case .core:
            return 1.0
        case .halo:
            return 0.95
        case .drive:
            return 0.92
        }
    }
}
