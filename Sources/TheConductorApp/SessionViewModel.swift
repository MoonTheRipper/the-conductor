import AVFoundation
import Combine
import ConductorCore
import SwiftUI
import simd

struct DebugGestureState: Equatable {
    var leftPosition = SIMD2<Double>(-0.36, 0.14)
    var leftPinch = 0.18
    var leftOpenness: HandOpenness = .relaxed
    var leftVerticalVelocity = 0.08

    var rightPosition = SIMD2<Double>(0.08, -0.76)
    var rightPinch = 0.16
    var rightOpenness: HandOpenness = .open
    var rightVerticalVelocity = -0.12

    static let seed = DebugGestureState()
}

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var debugState: DebugGestureState {
        didSet {
            if trackingMode == .simulator {
                refreshFromDebugGesture()
            }
        }
    }

    @Published private(set) var performanceState: PerformanceState
    @Published private(set) var chordLabels: [String]
    @Published private(set) var intervalLabels: [String]
    @Published var trackingMode: TrackingMode = .simulator {
        didSet { handleTrackingModeChange() }
    }
    @Published var routingMode: RoutingMode = .standaloneHost {
        didSet { handleRoutingModeChange() }
    }
    @Published var keyCenter: PitchClass = .c {
        didSet {
            engine.setKeyCenter(keyCenter)
            chordLabels = engine.harmonyEngine.chordLabels
            refreshCurrentInput()
        }
    }
    @Published var instrumentSearchText = ""
    @Published var selectedInstrumentID = "" {
        didSet { handleSelectedInstrumentChange() }
    }
    @Published var calibration: GestureCalibration {
        didSet {
            persistCalibration()
            refreshCurrentInput()
        }
    }
    @Published private(set) var midiDestinations: [MIDIDestinationDescriptor] = []
    @Published private(set) var midiStatusText = "MIDI bridge ready"
    @Published var selectedMIDIDestinationID = LogicMIDIBridgeService.noDestinationID {
        didSet {
            guard selectedMIDIDestinationID != midiBridgeService.selectedDestinationID else { return }
            midiBridgeService.setSelectedDestination(id: selectedMIDIDestinationID)
        }
    }
    @Published var sendToVirtualMIDISource = true {
        didSet {
            guard sendToVirtualMIDISource != midiBridgeService.sendToVirtualSource else { return }
            midiBridgeService.sendToVirtualSource = sendToVirtualMIDISource
        }
    }
    @Published private(set) var availableInstruments: [InstrumentDescriptor] = []
    @Published private(set) var libraryFolders: [LibraryFolderDescriptor] = []
    @Published private(set) var instrumentCatalogStatusText = "Standalone catalog idle"
    @Published private(set) var standaloneHostStatusText = "Standalone host idle"
    @Published private(set) var standaloneSupportText = "No instrument selected"
    @Published private(set) var standaloneLoadedInstrumentName: String?
    @Published private(set) var standaloneLoadedLayerNames: [String: String] = [:]
    @Published private(set) var standaloneLayerTopologyText: [String: String] = [:]
    @Published private(set) var isStandaloneEngineRunning = false
    @Published private(set) var isStandaloneInstrumentLoaded = false
    @Published private(set) var loopTransportStatusText = "No loop captured"
    @Published private(set) var exportStatusText = "No MIDI export yet"
    @Published var exportOptions: MIDIExportOptions {
        didSet { persistExportOptions() }
    }
    @Published var scenePresetName = ""
    @Published var selectedScenePresetID = ""
    @Published private(set) var scenePresets: [PerformanceScenePreset]
    @Published private(set) var layerMixMultipliers: [String: Double]
    @Published private(set) var layerManualEnabled: [String: Bool]
    @Published private(set) var layerAssignedInstrumentIDs: [String: String]
    @Published private(set) var layerPerformanceSettings: [String: LayerPerformanceSettings]
    @Published private(set) var layerMIDIRoutingSettings: [String: LayerMIDIRoutingSettings]
    @Published private(set) var layerLibraryFollowArticulation: [String: Bool]
    @Published private(set) var layerLibraryTargetIDs: [String: String]
    @Published private(set) var layerOutputSettings: [String: LayerOutputSettings]
    @Published private(set) var liveBeatConfidence = 0.0
    @Published private(set) var liveRightHandVelocity = 0.0
    @Published private(set) var liveRightHandPinch = 0.0
    @Published private(set) var liveRightHandSpread = 0.0
    @Published private(set) var liveGestureIntentText = "Awaiting gesture input"

    private var engine: PerformanceEngine
    private var frameClock: TimeInterval = 0
    private let liveTrackingService = VisionHandTrackingService()
    private let midiBridgeService = LogicMIDIBridgeService()
    private let standaloneCatalogService = StandaloneInstrumentCatalogService()
    private let standaloneHostService = StandaloneAudioHostService()
    private let loopExportService = MIDILoopExportService()
    private var cancellables = Set<AnyCancellable>()
    private var loopPlaybackGeneration = 0
    private var loopPlaybackWorkItems: [DispatchWorkItem] = []
    private var loopCycleWorkItem: DispatchWorkItem?
    private var isLoopPlaybackSuspended = false

    private static let calibrationDefaultsKey = "TheConductor.gestureCalibration"
    private static let layerMixDefaultsKey = "TheConductor.layerMixMultipliers"
    private static let layerEnabledDefaultsKey = "TheConductor.layerManualEnabled"
    private static let layerAssignmentsDefaultsKey = "TheConductor.layerAssignedInstrumentIDs"
    private static let layerPerformanceSettingsDefaultsKey = "TheConductor.layerPerformanceSettings"
    private static let layerMIDIRoutingSettingsDefaultsKey = "TheConductor.layerMIDIRoutingSettings"
    private static let layerLibraryFollowArticulationDefaultsKey = "TheConductor.layerLibraryFollowArticulation"
    private static let layerLibraryTargetsDefaultsKey = "TheConductor.layerLibraryTargetIDs"
    private static let layerOutputSettingsDefaultsKey = "TheConductor.layerOutputSettings"
    private static let exportOptionsDefaultsKey = "TheConductor.exportOptions"
    private static let scenePresetsDefaultsKey = "TheConductor.scenePresets"

    init() {
        let engine = PerformanceEngine(keyCenter: .c)
        self.engine = engine
        self.performanceState = engine.state
        self.chordLabels = engine.harmonyEngine.chordLabels
        self.intervalLabels = engine.harmonyEngine.intervalLabels
        self.debugState = .seed
        self.calibration = Self.loadCalibration()
        self.exportOptions = Self.loadExportOptions()
        self.scenePresets = Self.loadScenePresets()
        self.layerMixMultipliers = Self.loadLayerMixMultipliers()
        self.layerManualEnabled = Self.loadLayerManualEnabled()
        self.layerAssignedInstrumentIDs = Self.loadLayerAssignments()
        self.layerPerformanceSettings = Self.loadLayerPerformanceSettings()
        self.layerMIDIRoutingSettings = Self.loadLayerMIDIRoutingSettings()
        self.layerLibraryFollowArticulation = Self.loadLayerLibraryFollowArticulation()
        self.layerLibraryTargetIDs = Self.loadLayerLibraryTargets()
        self.layerOutputSettings = Self.loadLayerOutputSettings()
        self.scenePresetName = scenePresets.first?.name ?? ""
        self.selectedScenePresetID = scenePresets.first.map { $0.id.uuidString } ?? ""
        bindLiveTracking()
        bindMIDIBridge()
        bindStandaloneCatalog()
        midiBridgeService.setMIDIRoutingSettings(layerMIDIRoutingSettings)
        refreshFromDebugGesture()
    }

    var selectedInstrument: InstrumentDescriptor? {
        availableInstruments.first { $0.id == selectedInstrumentID }
    }

    var filteredInstruments: [InstrumentDescriptor] {
        let query = instrumentSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return availableInstruments }

        return availableInstruments.filter { instrument in
            instrument.name.localizedCaseInsensitiveContains(query) ||
                instrument.source.localizedCaseInsensitiveContains(query) ||
                instrument.format.rawValue.localizedCaseInsensitiveContains(query) ||
                standaloneCatalogService.catalogLine(for: instrument).localizedCaseInsensitiveContains(query)
        }
    }

    var browseInstrumentOptions: [InstrumentDescriptor] {
        instrumentOptions(including: selectedInstrumentID)
    }

    var effectiveLayers: [LayerState] {
        performanceState.layers.map { layer in
            LayerState(
                name: layer.name,
                mix: min(max(layer.mix * layerMixMultipliers[layer.name, default: 1.0], 0.0), 1.2),
                isEnabled: layer.isEnabled && layerManualEnabled[layer.name, default: true]
            )
        }
    }

    var isLoopAvailable: Bool {
        performanceState.loopBuffer.phrase.isEmpty == false
    }

    var routingDescription: String {
        switch routingMode {
        case .standaloneHost:
            return "Drive hosted instruments and libraries directly without opening Logic."
        case .logicBridge:
            return "Send committed harmony and performance gestures into Logic over MIDI."
        }
    }

    var liveTrackingStatusText: String {
        liveTrackingService.statusText
    }

    var cameraAuthorizationStatusText: String {
        switch liveTrackingService.authorizationStatus {
        case .authorized:
            return liveTrackingService.isRunning ? "Authorized and running" : "Authorized"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }

    var captureSession: AVCaptureSession {
        liveTrackingService.captureSession
    }

    var isLiveTracking: Bool {
        trackingMode == .liveCamera
    }

    var isCameraRunning: Bool {
        liveTrackingService.isRunning
    }

    var virtualMIDISourceName: String {
        midiBridgeService.virtualSourceName
    }

    var midiChannelMapDescription: [String] {
        PerformanceLayerPlanner.channelMapDescription(using: layerMIDIRoutingSettings)
    }

    var isSelectedInstrumentHostableNow: Bool {
        standaloneCatalogService.isStandalonePlayable(selectedInstrumentID)
    }

    var standaloneLoadedLayerSummary: [String] {
        PerformanceLayerPlanner.layerNames.compactMap { layerName in
            guard let instrumentName = standaloneLoadedLayerNames[layerName] else { return nil }
            return "\(layerName): \(instrumentName)"
        }
    }

    var selectedScenePreset: PerformanceScenePreset? {
        scenePresets.first { $0.id.uuidString == selectedScenePresetID }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<DebugGestureState, Value>) -> Binding<Value> {
        Binding(
            get: { self.debugState[keyPath: keyPath] },
            set: { newValue in
                var copy = self.debugState
                copy[keyPath: keyPath] = newValue
                self.debugState = copy
            }
        )
    }

    func calibrationBinding<Value>(_ keyPath: WritableKeyPath<GestureCalibration, Value>) -> Binding<Value> {
        Binding(
            get: { self.calibration[keyPath: keyPath] },
            set: { newValue in
                var updated = self.calibration
                updated[keyPath: keyPath] = newValue
                self.calibration = updated
            }
        )
    }

    func exportOptionsBinding<Value>(_ keyPath: WritableKeyPath<MIDIExportOptions, Value>) -> Binding<Value> {
        Binding(
            get: { self.exportOptions[keyPath: keyPath] },
            set: { newValue in
                var updated = self.exportOptions
                updated[keyPath: keyPath] = newValue
                self.exportOptions = updated
            }
        )
    }

    func layerGainBinding(for layerName: String) -> Binding<Double> {
        Binding(
            get: { self.layerMixMultipliers[layerName, default: 1.0] },
            set: { newValue in
                self.layerMixMultipliers[layerName] = newValue
                self.persistLayerControls()
            }
        )
    }

    func layerEnabledBinding(for layerName: String) -> Binding<Bool> {
        Binding(
            get: { self.layerManualEnabled[layerName, default: true] },
            set: { newValue in
                self.layerManualEnabled[layerName] = newValue
                self.persistLayerControls()
            }
        )
    }

    func layerInstrumentBinding(for layerName: String) -> Binding<String> {
        Binding(
            get: { self.layerAssignedInstrumentIDs[layerName] ?? "" },
            set: { newValue in
                self.layerAssignedInstrumentIDs[layerName] = newValue
                self.persistLayerAssignments()
                self.normalizeLayerLibraryTargets()
                self.configureStandaloneSelection()
            }
        )
    }

    func layerOutputBusBinding(for layerName: String) -> Binding<LayerOutputBus> {
        Binding(
            get: { self.layerOutputSettings[layerName]?.bus ?? LayerOutputSettings.default(for: layerName).bus },
            set: { newValue in
                var settings = self.layerOutputSettings[layerName] ?? LayerOutputSettings.default(for: layerName)
                settings.bus = newValue
                self.layerOutputSettings[layerName] = settings
                self.persistLayerOutputSettings()
                self.configureStandaloneSelection()
            }
        )
    }

    func layerOutputScalarBinding(
        for layerName: String,
        keyPath: WritableKeyPath<LayerOutputSettings, Double>
    ) -> Binding<Double> {
        Binding(
            get: { self.layerOutputSettings[layerName]?[keyPath: keyPath] ?? LayerOutputSettings.default(for: layerName)[keyPath: keyPath] },
            set: { newValue in
                var settings = self.layerOutputSettings[layerName] ?? LayerOutputSettings.default(for: layerName)
                settings[keyPath: keyPath] = newValue
                self.layerOutputSettings[layerName] = settings
                self.persistLayerOutputSettings()
                self.configureStandaloneSelection()
            }
        )
    }

    func layerArticulationBinding(for layerName: String) -> Binding<LayerArticulationStyle> {
        Binding(
            get: { self.layerPerformanceSettings[layerName]?.articulation ?? LayerPerformanceSettings.default(for: layerName).articulation },
            set: { newValue in
                var settings = self.layerPerformanceSettings[layerName] ?? LayerPerformanceSettings.default(for: layerName)
                settings.articulation = newValue
                self.layerPerformanceSettings[layerName] = settings
                self.persistLayerPerformanceSettings()
                self.configureStandaloneSelection()
            }
        )
    }

    func layerPerformanceIntBinding(
        for layerName: String,
        keyPath: WritableKeyPath<LayerPerformanceSettings, Int>
    ) -> Binding<Int> {
        Binding(
            get: { self.layerPerformanceSettings[layerName]?[keyPath: keyPath] ?? LayerPerformanceSettings.default(for: layerName)[keyPath: keyPath] },
            set: { newValue in
                var settings = self.layerPerformanceSettings[layerName] ?? LayerPerformanceSettings.default(for: layerName)
                settings[keyPath: keyPath] = newValue
                self.layerPerformanceSettings[layerName] = settings
                self.persistLayerPerformanceSettings()
                self.configureStandaloneSelection()
            }
        )
    }

    func layerPerformanceDoubleBinding(
        for layerName: String,
        keyPath: WritableKeyPath<LayerPerformanceSettings, Double>
    ) -> Binding<Double> {
        Binding(
            get: { self.layerPerformanceSettings[layerName]?[keyPath: keyPath] ?? LayerPerformanceSettings.default(for: layerName)[keyPath: keyPath] },
            set: { newValue in
                var settings = self.layerPerformanceSettings[layerName] ?? LayerPerformanceSettings.default(for: layerName)
                settings[keyPath: keyPath] = newValue
                self.layerPerformanceSettings[layerName] = settings
                self.persistLayerPerformanceSettings()
                self.configureStandaloneSelection()
            }
        )
    }

    func layerMIDIIntBinding(
        for layerName: String,
        keyPath: WritableKeyPath<LayerMIDIRoutingSettings, Int>
    ) -> Binding<Int> {
        Binding(
            get: { self.layerMIDIRoutingSettings[layerName]?[keyPath: keyPath] ?? LayerMIDIRoutingSettings.default(for: layerName)[keyPath: keyPath] },
            set: { newValue in
                var settings = self.layerMIDIRoutingSettings[layerName] ?? LayerMIDIRoutingSettings.default(for: layerName)
                settings[keyPath: keyPath] = newValue
                self.layerMIDIRoutingSettings[layerName] = settings
                self.persistLayerMIDIRoutingSettings()
                self.syncMIDIRoutingSettings()
                self.configureStandaloneSelection()
            }
        )
    }

    func layerMIDIDoubleBinding(
        for layerName: String,
        keyPath: WritableKeyPath<LayerMIDIRoutingSettings, Double>
    ) -> Binding<Double> {
        Binding(
            get: { self.layerMIDIRoutingSettings[layerName]?[keyPath: keyPath] ?? LayerMIDIRoutingSettings.default(for: layerName)[keyPath: keyPath] },
            set: { newValue in
                var settings = self.layerMIDIRoutingSettings[layerName] ?? LayerMIDIRoutingSettings.default(for: layerName)
                settings[keyPath: keyPath] = newValue
                self.layerMIDIRoutingSettings[layerName] = settings
                self.persistLayerMIDIRoutingSettings()
                self.syncMIDIRoutingSettings()
            }
        )
    }

    func layerLibraryTargetBinding(for layerName: String) -> Binding<String> {
        Binding(
            get: { self.layerLibraryTargetIDs[layerName] ?? "" },
            set: { newValue in
                self.layerLibraryTargetIDs[layerName] = newValue
                self.layerLibraryFollowArticulation[layerName] = false
                self.persistLayerLibraryFollowArticulation()
                self.persistLayerLibraryTargets()
                self.configureStandaloneSelection()
            }
        )
    }

    func layerLibraryFollowBinding(for layerName: String) -> Binding<Bool> {
        Binding(
            get: { self.layerLibraryFollowArticulation[layerName] ?? true },
            set: { newValue in
                self.layerLibraryFollowArticulation[layerName] = newValue
                self.persistLayerLibraryFollowArticulation()
                self.normalizeLayerLibraryTargets()
                self.configureStandaloneSelection()
            }
        )
    }

    func instrumentOptions(including instrumentID: String? = nil) -> [InstrumentDescriptor] {
        var instruments = filteredInstruments
        if let instrumentID,
           instruments.contains(where: { $0.id == instrumentID }) == false,
           let selected = availableInstruments.first(where: { $0.id == instrumentID }) {
            instruments.insert(selected, at: 0)
        }
        return instruments
    }

    func layerInstrumentOptions(for layerName: String) -> [InstrumentDescriptor] {
        instrumentOptions(including: layerAssignedInstrumentIDs[layerName])
    }

    func currentLayerInstrument(for layerName: String) -> InstrumentDescriptor? {
        let instrumentID = layerAssignedInstrumentIDs[layerName] ?? ""
        return availableInstruments.first(where: { $0.id == instrumentID })
    }

    func layerLibraryTargetOptions(for layerName: String) -> [SampleLibraryPlayableTarget] {
        guard let instrument = currentLayerInstrument(for: layerName), instrument.format == .sampleLibrary else {
            return []
        }
        return standaloneCatalogService.sampleLibraryPlayableTargets(for: instrument.id)
    }

    func selectedLayerLibraryTarget(for layerName: String) -> SampleLibraryPlayableTarget? {
        let targetOptions = layerLibraryTargetOptions(for: layerName)
        let selectedTargetID = layerLibraryTargetIDs[layerName] ?? ""
        return targetOptions.first(where: { $0.id == selectedTargetID }) ?? targetOptions.first
    }

    func layerAssignmentSummary(for layerName: String) -> String {
        let instrumentID = layerAssignedInstrumentIDs[layerName] ?? ""
        guard instrumentID.isEmpty == false else {
            return "Unassigned"
        }
        return standaloneCatalogService.standaloneCapabilitySummary(for: instrumentID)
    }

    func loadedLayerTopologyText(for layerName: String) -> String? {
        standaloneLayerTopologyText[layerName]
    }

    func isLayerAssignmentHostable(_ layerName: String) -> Bool {
        let instrumentID = layerAssignedInstrumentIDs[layerName] ?? ""
        return standaloneCatalogService.isStandalonePlayable(instrumentID)
    }

    func instrumentCatalogLine(for instrument: InstrumentDescriptor) -> String {
        standaloneCatalogService.catalogLine(for: instrument)
    }

    func layerOutputSummary(for layerName: String) -> String {
        (layerOutputSettings[layerName] ?? LayerOutputSettings.default(for: layerName)).summaryText
    }

    func layerPerformanceSummary(for layerName: String) -> String {
        (layerPerformanceSettings[layerName] ?? LayerPerformanceSettings.default(for: layerName)).summaryText
    }

    func layerMIDIRoutingSummary(for layerName: String) -> String {
        (layerMIDIRoutingSettings[layerName] ?? LayerMIDIRoutingSettings.default(for: layerName)).summaryText
    }

    func layerLibraryTargetSummary(for layerName: String) -> String? {
        selectedLayerLibraryTarget(for: layerName)?.detailText
    }

    func isLayerLibraryFollowingArticulation(_ layerName: String) -> Bool {
        layerLibraryFollowArticulation[layerName] ?? true
    }

    func selectScenePreset(id: String) {
        selectedScenePresetID = id
        if let preset = selectedScenePreset {
            scenePresetName = preset.name
        }
    }

    func startLiveTracking() {
        liveTrackingService.start()
    }

    func stopLiveTracking() {
        liveTrackingService.stop()
    }

    func refreshMIDIDestinations() {
        midiBridgeService.refreshDestinations()
    }

    func silenceMIDINotes() {
        midiBridgeService.silenceAllNotes()
    }

    func silenceStandaloneNotes() {
        standaloneHostService.silenceAllNotes()
    }

    func unloadStandaloneAssignments() {
        standaloneHostService.unloadAll()
    }

    func refreshStandaloneInstruments() {
        standaloneCatalogService.refresh()
    }

    func addLibraryFolder() {
        standaloneCatalogService.addLibraryFolder()
    }

    func removeLibraryFolder(id: String) {
        standaloneCatalogService.removeLibraryFolder(id: id)
    }

    func pauseLoopPlayback() {
        isLoopPlaybackSuspended = true
        stopLoopPlayback(shouldSilence: true)
        loopTransportStatusText = isLoopAvailable ? "Loop paused" : "No loop captured"
    }

    func restartLoopPlayback() {
        guard isLoopAvailable else {
            loopTransportStatusText = "No loop captured"
            return
        }

        isLoopPlaybackSuspended = false
        startLoopPlayback(using: performanceState.loopBuffer, force: true)
    }

    func clearLoop() {
        isLoopPlaybackSuspended = false
        stopLoopPlayback(shouldSilence: true)
        engine.clearLoopBuffer()
        performanceState = engine.state
        loopTransportStatusText = "Loop cleared"
    }

    func assignSelectedInstrumentToAllLayers() {
        guard selectedInstrumentID.isEmpty == false else { return }
        for layerName in PerformanceLayerPlanner.layerNames {
            layerAssignedInstrumentIDs[layerName] = selectedInstrumentID
        }
        persistLayerAssignments()
        normalizeLayerLibraryTargets()
        configureStandaloneSelection()
    }

    func clearLayerAssignments() {
        layerAssignedInstrumentIDs = Dictionary(
            uniqueKeysWithValues: PerformanceLayerPlanner.layerNames.map { ($0, "") }
        )
        layerLibraryFollowArticulation = Self.defaultLayerLibraryFollowArticulation
        layerLibraryTargetIDs = Dictionary(
            uniqueKeysWithValues: PerformanceLayerPlanner.layerNames.map { ($0, "") }
        )
        persistLayerAssignments()
        persistLayerLibraryFollowArticulation()
        persistLayerLibraryTargets()
        configureStandaloneSelection()
    }

    func resetLayerOutputRouting() {
        layerOutputSettings = Self.defaultLayerOutputSettings
        persistLayerOutputSettings()
        configureStandaloneSelection()
    }

    func resetLayerPerformanceSettings() {
        layerPerformanceSettings = Self.defaultLayerPerformanceSettings
        persistLayerPerformanceSettings()
        configureStandaloneSelection()
    }

    func resetLayerMIDIRoutingSettings() {
        layerMIDIRoutingSettings = Self.defaultLayerMIDIRoutingSettings
        persistLayerMIDIRoutingSettings()
        syncMIDIRoutingSettings()
        configureStandaloneSelection()
    }

    func resetCalibration() {
        calibration = GestureCalibration()
    }

    func exportLoopAsMIDI() {
        do {
            let url = try loopExportService.export(
                loopBuffer: performanceState.loopBuffer,
                layers: effectiveLayers,
                options: exportOptions,
                performanceSettingsByLayer: layerPerformanceSettings,
                midiRoutingSettingsByLayer: layerMIDIRoutingSettings
            )
            exportStatusText = "Exported layer-aware MIDI to \(url.lastPathComponent)"
        } catch ExportError.cancelled {
            exportStatusText = "MIDI export cancelled"
        } catch {
            exportStatusText = error.localizedDescription
        }
    }

    func saveNewScenePreset() {
        let trimmedName = scenePresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? defaultScenePresetName() : trimmedName
        let preset = PerformanceScenePreset(
            name: name,
            updatedAt: .now,
            snapshot: capturedSceneSnapshot()
        )
        scenePresets.insert(preset, at: 0)
        selectedScenePresetID = preset.id.uuidString
        scenePresetName = preset.name
        persistScenePresets()
    }

    func updateSelectedScenePreset() {
        guard let selectedIndex = scenePresets.firstIndex(where: { $0.id.uuidString == selectedScenePresetID }) else {
            saveNewScenePreset()
            return
        }

        let trimmedName = scenePresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        scenePresets[selectedIndex].name = trimmedName.isEmpty ? scenePresets[selectedIndex].name : trimmedName
        scenePresets[selectedIndex].updatedAt = .now
        scenePresets[selectedIndex].snapshot = capturedSceneSnapshot()
        scenePresetName = scenePresets[selectedIndex].name
        persistScenePresets()
    }

    func loadSelectedScenePreset() {
        guard let preset = selectedScenePreset else { return }
        applyScenePreset(preset)
    }

    func deleteSelectedScenePreset() {
        guard let selectedPreset = selectedScenePreset else { return }
        scenePresets.removeAll { $0.id == selectedPreset.id }
        if let nextPreset = scenePresets.first {
            selectedScenePresetID = nextPreset.id.uuidString
            scenePresetName = nextPreset.name
        } else {
            selectedScenePresetID = ""
            scenePresetName = ""
        }
        persistScenePresets()
    }

    func pulseCommit() {
        pulse(
            engage: {
                $0.rightPinch = 0.95
                $0.rightOpenness = .open
            },
            release: { $0.rightPinch = 0.18 }
        )
    }

    func pulseLoopToggle() {
        pulse(
            engage: {
                $0.leftPinch = 0.95
                $0.rightPinch = 0.95
            },
            release: {
                $0.leftPinch = 0.18
                $0.rightPinch = 0.18
            }
        )
    }

    func pulseDownbeat() {
        pulse(
            engage: {
                $0.rightOpenness = .open
                $0.rightVerticalVelocity = -1.0
            },
            release: { $0.rightVerticalVelocity = 0.0 }
        )
    }

    func pulseStop() {
        pulse(
            engage: {
                $0.rightOpenness = .closed
                $0.rightPinch = 0.82
            },
            release: {
                $0.rightOpenness = .relaxed
                $0.rightPinch = 0.18
            }
        )
    }

    private func pulse(
        engage: (inout DebugGestureState) -> Void,
        release: (inout DebugGestureState) -> Void
    ) {
        guard trackingMode == .simulator else { return }

        var onState = debugState
        engage(&onState)
        debugState = onState

        var offState = debugState
        release(&offState)
        debugState = offState
    }

    private func bindLiveTracking() {
        liveTrackingService.$latestSnapshot
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self, self.trackingMode == .liveCamera else { return }
                self.apply(snapshot: snapshot)
            }
            .store(in: &cancellables)
    }

    private func bindMIDIBridge() {
        midiBridgeService.$destinations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] destinations in
                self?.midiDestinations = destinations
            }
            .store(in: &cancellables)

        midiBridgeService.$statusText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] statusText in
                self?.midiStatusText = statusText
            }
            .store(in: &cancellables)

        midiBridgeService.$selectedDestinationID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedDestinationID in
                self?.selectedMIDIDestinationID = selectedDestinationID
            }
            .store(in: &cancellables)

        midiBridgeService.$sendToVirtualSource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sendToVirtualSource in
                self?.sendToVirtualMIDISource = sendToVirtualSource
            }
            .store(in: &cancellables)
    }

    private func bindStandaloneCatalog() {
        standaloneCatalogService.$instruments
            .receive(on: DispatchQueue.main)
            .sink { [weak self] instruments in
                guard let self else { return }
                self.availableInstruments = instruments
                if instruments.contains(where: { $0.id == self.selectedInstrumentID }) == false {
                    self.selectedInstrumentID = instruments.first?.id ?? ""
                }
                self.normalizeLayerAssignments()
                self.normalizeLayerLibraryTargets()
                self.configureStandaloneSelection()
            }
            .store(in: &cancellables)

        standaloneCatalogService.$libraryFolders
            .receive(on: DispatchQueue.main)
            .sink { [weak self] libraryFolders in
                self?.libraryFolders = libraryFolders
            }
            .store(in: &cancellables)

        standaloneCatalogService.$statusText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] statusText in
                self?.instrumentCatalogStatusText = statusText
            }
            .store(in: &cancellables)

        standaloneHostService.$statusText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] statusText in
                self?.standaloneHostStatusText = statusText
            }
            .store(in: &cancellables)

        standaloneHostService.$supportText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] supportText in
                self?.standaloneSupportText = supportText
            }
            .store(in: &cancellables)

        standaloneHostService.$loadedInstrumentName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loadedInstrumentName in
                self?.standaloneLoadedInstrumentName = loadedInstrumentName
            }
            .store(in: &cancellables)

        standaloneHostService.$loadedLayerNames
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loadedLayerNames in
                self?.standaloneLoadedLayerNames = loadedLayerNames
            }
            .store(in: &cancellables)

        standaloneHostService.$layerTopologyText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] layerTopologyText in
                self?.standaloneLayerTopologyText = layerTopologyText
            }
            .store(in: &cancellables)

        standaloneHostService.$isEngineRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEngineRunning in
                self?.isStandaloneEngineRunning = isEngineRunning
            }
            .store(in: &cancellables)

        standaloneHostService.$isInstrumentLoaded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isInstrumentLoaded in
                self?.isStandaloneInstrumentLoaded = isInstrumentLoaded
            }
            .store(in: &cancellables)
    }

    private func handleTrackingModeChange() {
        switch trackingMode {
        case .simulator:
            liveTrackingService.stop()
            refreshFromDebugGesture()
        case .liveCamera:
            performanceState.activityText = "Live camera ready"
        }
    }

    private func handleRoutingModeChange() {
        switch routingMode {
        case .standaloneHost:
            configureStandaloneSelection()
            if performanceState.loopBuffer.isPlaying {
                startLoopPlayback(using: performanceState.loopBuffer)
            } else {
                standaloneHostService.silenceAllNotes()
            }
        case .logicBridge:
            standaloneHostService.silenceAllNotes()
            midiBridgeService.refreshDestinations()
            if performanceState.loopBuffer.isPlaying {
                startLoopPlayback(using: performanceState.loopBuffer)
            }
        }
    }

    private func refreshCurrentInput() {
        switch trackingMode {
        case .simulator:
            refreshFromDebugGesture()
        case .liveCamera:
            if let snapshot = liveTrackingService.latestSnapshot {
                apply(snapshot: snapshot)
            }
        }
    }

    private func refreshFromDebugGesture() {
        guard trackingMode == .simulator else { return }

        frameClock += 0.12

        let snapshot = GestureSnapshot(
            leftHand: HandState(
                position: debugState.leftPosition,
                pinch: debugState.leftPinch,
                openness: debugState.leftOpenness,
                verticalVelocity: debugState.leftVerticalVelocity,
                horizontalVelocity: 0,
                spread: simulatedSpread(for: debugState.leftOpenness, pinch: debugState.leftPinch),
                roll: debugState.leftPosition.x * 0.4,
                downbeatConfidence: simulatedDownbeatConfidence(
                    openness: debugState.leftOpenness,
                    verticalVelocity: debugState.leftVerticalVelocity,
                    spread: simulatedSpread(for: debugState.leftOpenness, pinch: debugState.leftPinch)
                )
            ),
            rightHand: HandState(
                position: debugState.rightPosition,
                pinch: debugState.rightPinch,
                openness: debugState.rightOpenness,
                verticalVelocity: debugState.rightVerticalVelocity,
                horizontalVelocity: 0,
                spread: simulatedSpread(for: debugState.rightOpenness, pinch: debugState.rightPinch),
                roll: debugState.rightPosition.x * 0.4,
                downbeatConfidence: simulatedDownbeatConfidence(
                    openness: debugState.rightOpenness,
                    verticalVelocity: debugState.rightVerticalVelocity,
                    spread: simulatedSpread(for: debugState.rightOpenness, pinch: debugState.rightPinch)
                )
            ),
            timestamp: frameClock
        )

        apply(snapshot: snapshot)
    }

    private func apply(snapshot: GestureSnapshot) {
        let calibratedSnapshot = calibration.apply(to: snapshot)
        updateLiveDiagnostics(from: calibratedSnapshot)
        let events = engine.handle(snapshot: calibratedSnapshot)
        performanceState = engine.state
        updateLoopTransportStatus()
        processPerformanceEvents(events)
    }

    private func processPerformanceEvents(_ events: [PerformanceEvent]) {
        guard events.isEmpty == false else { return }

        for event in events {
            switch event {
            case .chordCommitted(let chord, let interval, let dynamics, _):
                playToActiveRoute(
                    chord: chord,
                    interval: interval,
                    dynamics: dynamics
                )
            case .transportChanged(let isPerforming, _):
                if isPerforming == false {
                    stopLoopPlayback(shouldSilence: true)
                }
            case .loopStateChanged(let loopBuffer, _):
                updateLoopTransportStatus(using: loopBuffer)
                if loopBuffer.isPlaying {
                    isLoopPlaybackSuspended = false
                    startLoopPlayback(using: loopBuffer, force: true)
                } else {
                    stopLoopPlayback(shouldSilence: true)
                }
            }
        }
    }

    private func startLoopPlayback(using loopBuffer: LoopBuffer, force: Bool = false) {
        stopLoopPlayback()

        guard loopBuffer.phrase.isEmpty == false else { return }
        guard force || isLoopPlaybackSuspended == false else {
            loopTransportStatusText = "Loop paused"
            return
        }

        let duration = loopDuration(for: loopBuffer)
        loopPlaybackGeneration += 1
        let generation = loopPlaybackGeneration
        scheduleLoopCycle(
            using: loopBuffer,
            generation: generation,
            cycleDuration: duration
        )
        loopTransportStatusText = "Looping \(loopBuffer.phrase.count) events over \(String(format: "%.2f", duration))s"
    }

    private func scheduleLoopCycle(
        using loopBuffer: LoopBuffer,
        generation: Int,
        cycleDuration: TimeInterval
    ) {
        loopPlaybackWorkItems.removeAll(keepingCapacity: true)
        let loopStart = loopBuffer.startTimestamp ?? loopBuffer.phrase.first?.timestamp ?? 0.0

        for phraseEvent in loopBuffer.phrase {
            let offset = min(
                max(phraseEvent.timestamp - loopStart, 0.0),
                max(cycleDuration - 0.01, 0.0)
            )

            let workItem = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self, self.loopPlaybackGeneration == generation else { return }
                    self.playLoopPhraseEvent(phraseEvent)
                }
            }

            loopPlaybackWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + offset, execute: workItem)
        }

        let cycleWorkItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.loopPlaybackGeneration == generation else { return }
                guard self.isLoopPlaybackSuspended == false else { return }
                self.scheduleLoopCycle(
                    using: loopBuffer,
                    generation: generation,
                    cycleDuration: cycleDuration
                )
            }
        }

        loopCycleWorkItem = cycleWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + cycleDuration, execute: cycleWorkItem)
    }

    private func playLoopPhraseEvent(_ phraseEvent: LoopPhraseEvent) {
        playToActiveRoute(
            chord: phraseEvent.chord,
            interval: phraseEvent.interval,
            dynamics: phraseEvent.dynamics
        )
    }

    private func stopLoopPlayback(shouldSilence: Bool = false) {
        loopPlaybackGeneration += 1
        loopPlaybackWorkItems.forEach { $0.cancel() }
        loopPlaybackWorkItems.removeAll()
        loopCycleWorkItem?.cancel()
        loopCycleWorkItem = nil

        if shouldSilence {
            midiBridgeService.silenceAllNotes()
            standaloneHostService.silenceAllNotes()
        }
    }

    private func playToActiveRoute(
        chord: ChordSelection,
        interval: IntervalChoice,
        dynamics: Double
    ) {
        switch routingMode {
        case .standaloneHost:
            standaloneHostService.send(
                chord: chord,
                interval: interval,
                dynamics: dynamics,
                layers: effectiveLayers,
                performanceSettingsByLayer: layerPerformanceSettings,
                midiRoutingSettingsByLayer: layerMIDIRoutingSettings
            )
        case .logicBridge:
            midiBridgeService.send(
                chord: chord,
                interval: interval,
                dynamics: dynamics,
                layers: effectiveLayers,
                performanceSettingsByLayer: layerPerformanceSettings,
                midiRoutingSettingsByLayer: layerMIDIRoutingSettings
            )
        }
    }

    private func handleSelectedInstrumentChange() {
        if layerAssignedInstrumentIDs.values.allSatisfy({ $0.isEmpty }) && selectedInstrumentID.isEmpty == false {
            for layerName in PerformanceLayerPlanner.layerNames {
                layerAssignedInstrumentIDs[layerName] = selectedInstrumentID
            }
            persistLayerAssignments()
        }
        normalizeLayerLibraryTargets()
        configureStandaloneSelection()
    }

    private func configureStandaloneSelection() {
        normalizeLayerLibraryTargets()

        let selections = PerformanceLayerPlanner.layerNames.map { layerName in
            let instrumentID = layerAssignedInstrumentIDs[layerName] ?? ""
            let instrument = availableInstruments.first(where: { $0.id == instrumentID })
            let audioUnitDescription = instrument.flatMap {
                standaloneCatalogService.audioUnitDescription(for: $0.id)
            }
            let sampleLibraryLoadPlan = instrument.flatMap {
                standaloneCatalogService.sampleLibraryLoadPlan(
                    for: $0.id,
                    selectedTargetID: effectiveLayerLibraryTargetID(for: layerName)
                )
            }
            let supportSummary = instrumentID.isEmpty
                ? "No standalone target assigned"
                : standaloneCatalogService.standaloneCapabilitySummary(for: instrumentID)
            let performanceSettings = layerPerformanceSettings[layerName] ?? LayerPerformanceSettings.default(for: layerName)
            let midiRoutingSettings = layerMIDIRoutingSettings[layerName] ?? LayerMIDIRoutingSettings.default(for: layerName)
            let outputSettings = layerOutputSettings[layerName] ?? LayerOutputSettings.default(for: layerName)
            let selectionSignature: String
            if let instrument, instrument.format == .sampleLibrary, let sampleLibraryLoadPlan {
                selectionSignature = "\(instrument.id)::\(sampleLibraryLoadPlan.target.id)"
            } else if let instrument {
                selectionSignature = instrument.id
            } else {
                selectionSignature = "\(layerName)::unassigned"
            }

            return LayerHostedInstrumentSelection(
                layerName: layerName,
                instrument: instrument,
                selectionSignature: selectionSignature,
                audioUnitDescription: audioUnitDescription,
                sampleLibraryLoadPlan: sampleLibraryLoadPlan,
                performanceSettings: performanceSettings,
                midiRoutingSettings: midiRoutingSettings,
                outputSettings: outputSettings,
                capabilitySummary: supportSummary
            )
        }

        syncMIDIRoutingSettings()
        standaloneHostService.configureAssignments(selections)
    }

    private func loopDuration(for loopBuffer: LoopBuffer) -> TimeInterval {
        let capturedDuration: TimeInterval
        if let startTimestamp = loopBuffer.startTimestamp, let endTimestamp = loopBuffer.endTimestamp {
            capturedDuration = max(endTimestamp - startTimestamp, 0.0)
        } else {
            capturedDuration = 0.0
        }

        let phraseSpan: TimeInterval
        if let firstEvent = loopBuffer.phrase.first, let lastEvent = loopBuffer.phrase.last {
            phraseSpan = max(lastEvent.timestamp - firstEvent.timestamp, 0.0)
        } else {
            phraseSpan = 0.0
        }

        let fallbackDuration = max(Double(max(loopBuffer.phrase.count, 1)) * 0.75, phraseSpan + 0.45)
        return max(capturedDuration, fallbackDuration, 0.45)
    }

    private func updateLoopTransportStatus(using loopBuffer: LoopBuffer? = nil) {
        let loopBuffer = loopBuffer ?? performanceState.loopBuffer

        if loopBuffer.isRecording {
            loopTransportStatusText = "Recording loop"
        } else if loopBuffer.isPlaying {
            loopTransportStatusText = isLoopPlaybackSuspended
                ? "Loop paused"
                : "Looping \(loopBuffer.phrase.count) events"
        } else if loopBuffer.phrase.isEmpty {
            loopTransportStatusText = "No loop captured"
        } else {
            loopTransportStatusText = "Loop ready with \(loopBuffer.phrase.count) events"
        }
    }

    private func persistCalibration() {
        guard let data = try? JSONEncoder().encode(calibration) else { return }
        UserDefaults.standard.set(data, forKey: Self.calibrationDefaultsKey)
    }

    private func persistExportOptions() {
        guard let data = try? JSONEncoder().encode(exportOptions) else { return }
        UserDefaults.standard.set(data, forKey: Self.exportOptionsDefaultsKey)
    }

    private func persistLayerControls() {
        UserDefaults.standard.set(layerMixMultipliers, forKey: Self.layerMixDefaultsKey)
        UserDefaults.standard.set(layerManualEnabled, forKey: Self.layerEnabledDefaultsKey)
    }

    private func persistLayerAssignments() {
        UserDefaults.standard.set(layerAssignedInstrumentIDs, forKey: Self.layerAssignmentsDefaultsKey)
    }

    private func persistLayerPerformanceSettings() {
        guard let data = try? JSONEncoder().encode(layerPerformanceSettings) else { return }
        UserDefaults.standard.set(data, forKey: Self.layerPerformanceSettingsDefaultsKey)
    }

    private func persistLayerMIDIRoutingSettings() {
        guard let data = try? JSONEncoder().encode(layerMIDIRoutingSettings) else { return }
        UserDefaults.standard.set(data, forKey: Self.layerMIDIRoutingSettingsDefaultsKey)
    }

    private func persistLayerLibraryFollowArticulation() {
        UserDefaults.standard.set(layerLibraryFollowArticulation, forKey: Self.layerLibraryFollowArticulationDefaultsKey)
    }

    private func persistLayerLibraryTargets() {
        UserDefaults.standard.set(layerLibraryTargetIDs, forKey: Self.layerLibraryTargetsDefaultsKey)
    }

    private func persistLayerOutputSettings() {
        guard let data = try? JSONEncoder().encode(layerOutputSettings) else { return }
        UserDefaults.standard.set(data, forKey: Self.layerOutputSettingsDefaultsKey)
    }

    private func persistScenePresets() {
        guard let data = try? JSONEncoder().encode(scenePresets) else { return }
        UserDefaults.standard.set(data, forKey: Self.scenePresetsDefaultsKey)
    }

    private static func loadCalibration() -> GestureCalibration {
        guard
            let data = UserDefaults.standard.data(forKey: calibrationDefaultsKey),
            let calibration = try? JSONDecoder().decode(GestureCalibration.self, from: data)
        else {
            return GestureCalibration()
        }

        return calibration
    }

    private static func loadLayerMixMultipliers() -> [String: Double] {
        var merged = defaultLayerMixMultipliers
        let stored = UserDefaults.standard.dictionary(forKey: layerMixDefaultsKey) as? [String: Double] ?? [:]
        merged.merge(stored) { _, stored in stored }
        return merged
    }

    private static func loadLayerManualEnabled() -> [String: Bool] {
        var merged = defaultLayerManualEnabled
        let stored = UserDefaults.standard.dictionary(forKey: layerEnabledDefaultsKey) as? [String: Bool] ?? [:]
        merged.merge(stored) { _, stored in stored }
        return merged
    }

    private static func loadLayerAssignments() -> [String: String] {
        var merged = Dictionary(
            uniqueKeysWithValues: PerformanceLayerPlanner.layerNames.map { ($0, "") }
        )
        let stored = UserDefaults.standard.dictionary(forKey: layerAssignmentsDefaultsKey) as? [String: String] ?? [:]
        merged.merge(stored) { _, stored in stored }
        return merged
    }

    private static func loadLayerPerformanceSettings() -> [String: LayerPerformanceSettings] {
        var merged = defaultLayerPerformanceSettings
        if let data = UserDefaults.standard.data(forKey: layerPerformanceSettingsDefaultsKey),
           let stored = try? JSONDecoder().decode([String: LayerPerformanceSettings].self, from: data) {
            merged.merge(stored) { _, stored in stored }
        }
        return merged
    }

    private static func loadLayerMIDIRoutingSettings() -> [String: LayerMIDIRoutingSettings] {
        var merged = defaultLayerMIDIRoutingSettings
        if let data = UserDefaults.standard.data(forKey: layerMIDIRoutingSettingsDefaultsKey),
           let stored = try? JSONDecoder().decode([String: LayerMIDIRoutingSettings].self, from: data) {
            merged.merge(stored) { _, stored in stored }
        }
        return merged
    }

    private static func loadLayerLibraryFollowArticulation() -> [String: Bool] {
        var merged = defaultLayerLibraryFollowArticulation
        let stored = UserDefaults.standard.dictionary(forKey: layerLibraryFollowArticulationDefaultsKey) as? [String: Bool] ?? [:]
        merged.merge(stored) { _, stored in stored }
        return merged
    }

    private static func loadLayerLibraryTargets() -> [String: String] {
        var merged = Dictionary(
            uniqueKeysWithValues: PerformanceLayerPlanner.layerNames.map { ($0, "") }
        )
        let stored = UserDefaults.standard.dictionary(forKey: layerLibraryTargetsDefaultsKey) as? [String: String] ?? [:]
        merged.merge(stored) { _, stored in stored }
        return merged
    }

    private static func loadLayerOutputSettings() -> [String: LayerOutputSettings] {
        var merged = defaultLayerOutputSettings
        if let data = UserDefaults.standard.data(forKey: layerOutputSettingsDefaultsKey),
           let stored = try? JSONDecoder().decode([String: LayerOutputSettings].self, from: data) {
            merged.merge(stored) { _, stored in stored }
        }
        return merged
    }

    private static func loadExportOptions() -> MIDIExportOptions {
        guard
            let data = UserDefaults.standard.data(forKey: exportOptionsDefaultsKey),
            let options = try? JSONDecoder().decode(MIDIExportOptions.self, from: data)
        else {
            return .default
        }
        return options
    }

    private static func loadScenePresets() -> [PerformanceScenePreset] {
        guard
            let data = UserDefaults.standard.data(forKey: scenePresetsDefaultsKey),
            let presets = try? JSONDecoder().decode([PerformanceScenePreset].self, from: data)
        else {
            return []
        }

        return presets.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func normalizeLayerAssignments() {
        let validIDs = Set(availableInstruments.map(\.id))
        for layerName in PerformanceLayerPlanner.layerNames {
            let assignedInstrumentID = layerAssignedInstrumentIDs[layerName] ?? ""
            if assignedInstrumentID.isEmpty == false, validIDs.contains(assignedInstrumentID) == false {
                layerAssignedInstrumentIDs[layerName] = ""
            }
        }

        if layerAssignedInstrumentIDs.values.allSatisfy({ $0.isEmpty }), selectedInstrumentID.isEmpty == false {
            for layerName in PerformanceLayerPlanner.layerNames {
                layerAssignedInstrumentIDs[layerName] = selectedInstrumentID
            }
        }

        persistLayerAssignments()
    }

    private func normalizeLayerLibraryTargets() {
        for layerName in PerformanceLayerPlanner.layerNames {
            guard let instrument = currentLayerInstrument(for: layerName), instrument.format == .sampleLibrary else {
                layerLibraryFollowArticulation[layerName] = true
                layerLibraryTargetIDs[layerName] = ""
                continue
            }

            let targetOptions = standaloneCatalogService.sampleLibraryPlayableTargets(for: instrument.id)
            let isFollowing = layerLibraryFollowArticulation[layerName] ?? true
            if isFollowing,
               let articulation = layerPerformanceSettings[layerName]?.articulation,
               let recommendedTarget = standaloneCatalogService.recommendedSampleLibraryTarget(
                   for: instrument.id,
                   articulation: articulation
               ) {
                layerLibraryTargetIDs[layerName] = recommendedTarget.id
            } else {
                let selectedTargetID = layerLibraryTargetIDs[layerName] ?? ""
                if targetOptions.contains(where: { $0.id == selectedTargetID }) == false {
                    layerLibraryTargetIDs[layerName] = targetOptions.first?.id ?? ""
                }
            }
        }

        persistLayerLibraryFollowArticulation()
        persistLayerLibraryTargets()
    }

    private func effectiveLayerLibraryTargetID(for layerName: String) -> String? {
        let storedTargetID = layerLibraryTargetIDs[layerName]
        guard isLayerLibraryFollowingArticulation(layerName),
              let instrument = currentLayerInstrument(for: layerName),
              instrument.format == .sampleLibrary
        else {
            return storedTargetID
        }

        let articulation = layerPerformanceSettings[layerName]?.articulation ?? LayerPerformanceSettings.default(for: layerName).articulation
        return standaloneCatalogService.recommendedSampleLibraryTarget(for: instrument.id, articulation: articulation)?.id
            ?? storedTargetID
    }

    private func syncMIDIRoutingSettings() {
        midiBridgeService.setMIDIRoutingSettings(layerMIDIRoutingSettings)
    }

    private func capturedSceneSnapshot() -> PerformanceSceneSnapshot {
        PerformanceSceneSnapshot(
            routingMode: routingMode,
            trackingMode: trackingMode,
            keyCenter: keyCenter,
            selectedInstrumentID: selectedInstrumentID,
            sendToVirtualMIDISource: sendToVirtualMIDISource,
            calibration: calibration,
            exportOptions: exportOptions,
            layerMixMultipliers: layerMixMultipliers,
            layerManualEnabled: layerManualEnabled,
            layerAssignedInstrumentIDs: layerAssignedInstrumentIDs,
            layerPerformanceSettings: layerPerformanceSettings,
            layerMIDIRoutingSettings: layerMIDIRoutingSettings,
            layerLibraryFollowArticulation: layerLibraryFollowArticulation,
            layerLibraryTargetIDs: layerLibraryTargetIDs,
            layerOutputSettings: layerOutputSettings
        )
    }

    private func applyScenePreset(_ preset: PerformanceScenePreset) {
        let snapshot = preset.snapshot
        scenePresetName = preset.name
        selectedScenePresetID = preset.id.uuidString

        trackingMode = snapshot.trackingMode
        routingMode = snapshot.routingMode
        keyCenter = snapshot.keyCenter
        selectedInstrumentID = snapshot.selectedInstrumentID
        sendToVirtualMIDISource = snapshot.sendToVirtualMIDISource
        calibration = snapshot.calibration
        exportOptions = snapshot.exportOptions
        layerMixMultipliers = Self.defaultLayerMixMultipliers.merging(snapshot.layerMixMultipliers) { _, stored in stored }
        layerManualEnabled = Self.defaultLayerManualEnabled.merging(snapshot.layerManualEnabled) { _, stored in stored }
        layerAssignedInstrumentIDs = Dictionary(
            uniqueKeysWithValues: PerformanceLayerPlanner.layerNames.map { layerName in
                (layerName, snapshot.layerAssignedInstrumentIDs[layerName] ?? "")
            }
        )
        layerPerformanceSettings = Self.defaultLayerPerformanceSettings.merging(snapshot.layerPerformanceSettings) { _, stored in stored }
        layerMIDIRoutingSettings = Self.defaultLayerMIDIRoutingSettings.merging(snapshot.layerMIDIRoutingSettings) { _, stored in stored }
        layerLibraryFollowArticulation = Self.defaultLayerLibraryFollowArticulation.merging(snapshot.layerLibraryFollowArticulation) { _, stored in stored }
        layerLibraryTargetIDs = Dictionary(
            uniqueKeysWithValues: PerformanceLayerPlanner.layerNames.map { layerName in
                (layerName, snapshot.layerLibraryTargetIDs[layerName] ?? "")
            }
        )
        layerOutputSettings = Self.defaultLayerOutputSettings.merging(snapshot.layerOutputSettings) { _, stored in stored }

        persistLayerControls()
        persistLayerAssignments()
        persistLayerPerformanceSettings()
        persistLayerMIDIRoutingSettings()
        persistLayerLibraryFollowArticulation()
        persistLayerLibraryTargets()
        persistLayerOutputSettings()
        syncMIDIRoutingSettings()
        normalizeLayerAssignments()
        normalizeLayerLibraryTargets()
        configureStandaloneSelection()
        refreshCurrentInput()
    }

    private func defaultScenePresetName() -> String {
        "Scene \(scenePresets.count + 1)"
    }

    private static var defaultLayerMixMultipliers: [String: Double] {
        Dictionary(uniqueKeysWithValues: PerformanceLayerPlanner.layerChannels.map { ($0.name, 1.0) })
    }

    private static var defaultLayerManualEnabled: [String: Bool] {
        Dictionary(uniqueKeysWithValues: PerformanceLayerPlanner.layerChannels.map { ($0.name, true) })
    }

    private static var defaultLayerOutputSettings: [String: LayerOutputSettings] {
        Dictionary(uniqueKeysWithValues: PerformanceLayerPlanner.layerNames.map {
            ($0, LayerOutputSettings.default(for: $0))
        })
    }

    private static var defaultLayerPerformanceSettings: [String: LayerPerformanceSettings] {
        Dictionary(uniqueKeysWithValues: PerformanceLayerPlanner.layerNames.map {
            ($0, LayerPerformanceSettings.default(for: $0))
        })
    }

    private static var defaultLayerMIDIRoutingSettings: [String: LayerMIDIRoutingSettings] {
        Dictionary(uniqueKeysWithValues: PerformanceLayerPlanner.layerNames.map {
            ($0, LayerMIDIRoutingSettings.default(for: $0))
        })
    }

    private static var defaultLayerLibraryFollowArticulation: [String: Bool] {
        Dictionary(uniqueKeysWithValues: PerformanceLayerPlanner.layerNames.map { ($0, true) })
    }

    private func simulatedSpread(for openness: HandOpenness, pinch: Double) -> Double {
        let base: Double
        switch openness {
        case .closed:
            base = 0.18
        case .relaxed:
            base = 0.48
        case .open:
            base = 0.82
        }
        return min(max(base - (pinch * 0.18), 0.0), 1.0)
    }

    private func simulatedDownbeatConfidence(
        openness: HandOpenness,
        verticalVelocity: Double,
        spread: Double
    ) -> Double {
        let opennessLift: Double
        switch openness {
        case .open:
            opennessLift = 0.14
        case .relaxed:
            opennessLift = 0.06
        case .closed:
            opennessLift = 0.0
        }

        return min(max((max(0.0, -verticalVelocity) * 0.58) + (spread * 0.18) + opennessLift, 0.0), 1.0)
    }

    private func updateLiveDiagnostics(from snapshot: GestureSnapshot) {
        guard let rightHand = snapshot.rightHand else {
            liveBeatConfidence = 0
            liveRightHandVelocity = 0
            liveRightHandPinch = 0
            liveRightHandSpread = 0
            liveGestureIntentText = "No right hand detected"
            return
        }

        liveBeatConfidence = rightHand.downbeatConfidence
        liveRightHandVelocity = rightHand.verticalVelocity
        liveRightHandPinch = rightHand.pinch
        liveRightHandSpread = rightHand.spread

        if (snapshot.leftHand?.pinch ?? 0) > 0.88 && rightHand.pinch > 0.88 {
            liveGestureIntentText = "Loop toggle armed"
        } else if rightHand.downbeatConfidence > 0.76 && rightHand.openness == .open {
            liveGestureIntentText = "Downbeat intent ready"
        } else if rightHand.pinch > 0.82 {
            liveGestureIntentText = "Commit gesture armed"
        } else {
            liveGestureIntentText = "Tracking harmonic preview"
        }
    }
}
