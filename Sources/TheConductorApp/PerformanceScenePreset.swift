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
    var layerLibraryTargetIDs: [String: String]
    var layerOutputSettings: [String: LayerOutputSettings]
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
