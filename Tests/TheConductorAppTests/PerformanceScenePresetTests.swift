import ConductorCore
import Foundation
import Testing
@testable import TheConductorApp

struct PerformanceScenePresetTests {
    @Test
    func scenePresetRoundTripsThroughJSON() throws {
        let snapshot = PerformanceSceneSnapshot(
            routingMode: .logicBridge,
            trackingMode: .liveCamera,
            keyCenter: .eFlat,
            selectedInstrumentID: "library-/tmp/strings",
            sendToVirtualMIDISource: false,
            calibration: GestureCalibration(centerX: 0.1, centerY: -0.08, horizontalReach: 1.2, verticalReach: 0.9, pinchFloor: 0.14, pinchCeiling: 0.9, velocityScale: 1.1),
            exportOptions: MIDIExportOptions(clipName: "Cue A", tempoBPM: 98, repeatCount: 3),
            layerMixMultipliers: ["Strings": 1.1],
            layerManualEnabled: ["Strings": true, "Pulse": false],
            layerAssignedInstrumentIDs: ["Strings": "au-demo"],
            layerPerformanceSettings: ["Strings": LayerPerformanceSettings.default(for: "Strings")],
            layerLibraryTargetIDs: ["Strings": "preset::/tmp/legato.exs"],
            layerOutputSettings: ["Strings": LayerOutputSettings.default(for: "Strings")]
        )
        let preset = PerformanceScenePreset(
            name: "Film Cue",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            snapshot: snapshot
        )

        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(PerformanceScenePreset.self, from: data)

        #expect(decoded == preset)
        #expect(decoded.summaryText == "Logic Bridge · Eb · Live Camera")
    }
}
