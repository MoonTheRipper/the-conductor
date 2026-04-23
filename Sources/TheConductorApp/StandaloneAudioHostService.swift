import AVFoundation
import ConductorCore
import Foundation

@MainActor
final class StandaloneAudioHostService: ObservableObject {
    @Published private(set) var statusText = "Standalone host idle"
    @Published private(set) var supportText = "No instrument selected"
    @Published private(set) var loadedInstrumentName: String?
    @Published private(set) var isEngineRunning = false
    @Published private(set) var isInstrumentLoaded = false

    private let engine = AVAudioEngine()
    private var midiInstrument: AVAudioUnitMIDIInstrument?
    private var loadedInstrumentID: String?
    private var noteGeneration = 0
    private var activeNotesByChannel: [UInt8: Set<UInt8>] = [:]

    init() {
        startEngineIfNeeded()
    }

    func configureSelection(
        instrument: InstrumentDescriptor?,
        audioUnitDescription: AudioComponentDescription?,
        capabilitySummary: String
    ) {
        supportText = capabilitySummary

        guard let instrument else {
            unloadInstrument()
            statusText = "No standalone target selected"
            return
        }

        guard let audioUnitDescription else {
            unloadInstrument()
            statusText = capabilitySummary
            return
        }

        guard loadedInstrumentID != instrument.id else {
            statusText = "Ready: \(instrument.name)"
            return
        }

        loadAudioUnit(
            instrumentID: instrument.id,
            instrumentName: instrument.name,
            description: audioUnitDescription
        )
    }

    func send(
        chord: ChordSelection,
        interval: IntervalChoice,
        dynamics: Double,
        layers: [LayerState]
    ) {
        guard let midiInstrument else {
            statusText = "No Audio Unit loaded for standalone playback"
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

        for payload in payloads {
            for note in payload.notes {
                midiInstrument.startNote(note, withVelocity: payload.velocity, onChannel: payload.channel)
                activeNotesByChannel[payload.channel, default: []].insert(note)
            }
        }

        let holdDuration = 0.45 + (dynamics * 0.65)
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) { [weak self] in
            guard let self, self.noteGeneration == generation else { return }
            Task { @MainActor in
                self.silenceAllNotes()
            }
        }

        statusText = "Played \(chord.symbol) through \(loadedInstrumentName ?? "Audio Unit")"
    }

    func silenceAllNotes() {
        guard let midiInstrument else { return }

        noteGeneration += 1

        for (channel, notes) in activeNotesByChannel {
            for note in notes {
                midiInstrument.stopNote(note, onChannel: channel)
            }
            midiInstrument.sendController(123, withValue: 0, onChannel: channel)
            midiInstrument.sendController(120, withValue: 0, onChannel: channel)
        }

        activeNotesByChannel.removeAll()
        statusText = loadedInstrumentName.map { "Stopped notes on \($0)" } ?? "Stopped notes"
    }

    private func loadAudioUnit(
        instrumentID: String,
        instrumentName: String,
        description: AudioComponentDescription
    ) {
        unloadInstrument()

        startEngineIfNeeded()

        let instrument = AVAudioUnitMIDIInstrument(audioComponentDescription: description)
        engine.attach(instrument)
        engine.connect(instrument, to: engine.mainMixerNode, format: nil)
        startEngineIfNeeded()

        midiInstrument = instrument
        loadedInstrumentID = instrumentID
        loadedInstrumentName = instrumentName
        isInstrumentLoaded = true
        statusText = "Loaded \(instrumentName)"
    }

    private func unloadInstrument() {
        if midiInstrument != nil {
            silenceAllNotes()
        }

        if let midiInstrument {
            engine.disconnectNodeOutput(midiInstrument)
            engine.detach(midiInstrument)
        }

        midiInstrument = nil
        loadedInstrumentID = nil
        loadedInstrumentName = nil
        isInstrumentLoaded = false
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
