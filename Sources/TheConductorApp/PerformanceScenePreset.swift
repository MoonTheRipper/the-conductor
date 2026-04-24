import ConductorCore
import Foundation

struct PerformanceSceneSnapshot: Codable, Equatable, Sendable {
    var routingMode: RoutingMode
    var trackingMode: TrackingMode
    var keyCenter: PitchClass
    var selectedInstrumentID: String
    var sendToVirtualMIDISource: Bool
    var calibration: GestureCalibration
    var exportOptions: MIDIExportOptions
    var layerMixMultipliers: [String: Double]
    var layerManualEnabled: [String: Bool]
    var layerAssignedInstrumentIDs: [String: String]
    var layerPerformanceSettings: [String: LayerPerformanceSettings]
    var layerMIDIRoutingSettings: [String: LayerMIDIRoutingSettings]
    var layerLibraryFollowArticulation: [String: Bool]
    var layerLibraryTargetIDs: [String: String]
    var layerOutputSettings: [String: LayerOutputSettings]

    init(
        routingMode: RoutingMode,
        trackingMode: TrackingMode,
        keyCenter: PitchClass,
        selectedInstrumentID: String,
        sendToVirtualMIDISource: Bool,
        calibration: GestureCalibration,
        exportOptions: MIDIExportOptions,
        layerMixMultipliers: [String: Double],
        layerManualEnabled: [String: Bool],
        layerAssignedInstrumentIDs: [String: String],
        layerPerformanceSettings: [String: LayerPerformanceSettings],
        layerMIDIRoutingSettings: [String: LayerMIDIRoutingSettings],
        layerLibraryFollowArticulation: [String: Bool],
        layerLibraryTargetIDs: [String: String],
        layerOutputSettings: [String: LayerOutputSettings]
    ) {
        self.routingMode = routingMode
        self.trackingMode = trackingMode
        self.keyCenter = keyCenter
        self.selectedInstrumentID = selectedInstrumentID
        self.sendToVirtualMIDISource = sendToVirtualMIDISource
        self.calibration = calibration
        self.exportOptions = exportOptions
        self.layerMixMultipliers = layerMixMultipliers
        self.layerManualEnabled = layerManualEnabled
        self.layerAssignedInstrumentIDs = layerAssignedInstrumentIDs
        self.layerPerformanceSettings = layerPerformanceSettings
        self.layerMIDIRoutingSettings = layerMIDIRoutingSettings
        self.layerLibraryFollowArticulation = layerLibraryFollowArticulation
        self.layerLibraryTargetIDs = layerLibraryTargetIDs
        self.layerOutputSettings = layerOutputSettings
    }

    enum CodingKeys: String, CodingKey {
        case routingMode
        case trackingMode
        case keyCenter
        case selectedInstrumentID
        case sendToVirtualMIDISource
        case calibration
        case exportOptions
        case layerMixMultipliers
        case layerManualEnabled
        case layerAssignedInstrumentIDs
        case layerPerformanceSettings
        case layerMIDIRoutingSettings
        case layerLibraryFollowArticulation
        case layerLibraryTargetIDs
        case layerOutputSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        routingMode = try container.decode(RoutingMode.self, forKey: .routingMode)
        trackingMode = try container.decode(TrackingMode.self, forKey: .trackingMode)
        keyCenter = try container.decode(PitchClass.self, forKey: .keyCenter)
        selectedInstrumentID = try container.decodeIfPresent(String.self, forKey: .selectedInstrumentID) ?? ""
        sendToVirtualMIDISource = try container.decodeIfPresent(Bool.self, forKey: .sendToVirtualMIDISource) ?? true
        calibration = try container.decodeIfPresent(GestureCalibration.self, forKey: .calibration) ?? GestureCalibration()
        exportOptions = try container.decodeIfPresent(MIDIExportOptions.self, forKey: .exportOptions) ?? .default
        layerMixMultipliers = try container.decodeIfPresent([String: Double].self, forKey: .layerMixMultipliers) ?? [:]
        layerManualEnabled = try container.decodeIfPresent([String: Bool].self, forKey: .layerManualEnabled) ?? [:]
        layerAssignedInstrumentIDs = try container.decodeIfPresent([String: String].self, forKey: .layerAssignedInstrumentIDs) ?? [:]
        layerPerformanceSettings = try container.decodeIfPresent([String: LayerPerformanceSettings].self, forKey: .layerPerformanceSettings) ?? [:]
        layerMIDIRoutingSettings = try container.decodeIfPresent([String: LayerMIDIRoutingSettings].self, forKey: .layerMIDIRoutingSettings) ?? [:]
        layerLibraryFollowArticulation = try container.decodeIfPresent([String: Bool].self, forKey: .layerLibraryFollowArticulation) ?? [:]
        layerLibraryTargetIDs = try container.decodeIfPresent([String: String].self, forKey: .layerLibraryTargetIDs) ?? [:]
        layerOutputSettings = try container.decodeIfPresent([String: LayerOutputSettings].self, forKey: .layerOutputSettings) ?? [:]
    }
}

struct PerformanceScenePreset: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var updatedAt: Date
    var snapshot: PerformanceSceneSnapshot

    init(
        id: UUID = UUID(),
        name: String,
        updatedAt: Date = .now,
        snapshot: PerformanceSceneSnapshot
    ) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
        self.snapshot = snapshot
    }

    var summaryText: String {
        "\(snapshot.routingMode.rawValue) · \(snapshot.keyCenter.displayName) · \(snapshot.trackingMode.rawValue)"
    }
}
