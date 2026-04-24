import ConductorCore
import Foundation

struct LayerMIDIControlValues: Equatable, Sendable {
    let modulation: UInt8
    let expression: UInt8
}

enum LayerMIDIControlPlanner {
    static func controlValues(
        layer: LayerState,
        dynamics: Double,
        performanceSettings: LayerPerformanceSettings,
        midiRoutingSettings: LayerMIDIRoutingSettings
    ) -> LayerMIDIControlValues {
        let blend = min(max((dynamics * 0.68) + (layer.mix * 0.32), 0.0), 1.0)
        let articulationLift: Double
        switch performanceSettings.articulation {
        case .sustain:
            articulationLift = 0.72
        case .legato:
            articulationLift = 0.86
        case .accent:
            articulationLift = 0.64
        case .staccato:
            articulationLift = 0.42
        case .pulse:
            articulationLift = 0.26
        }

        let expressionValue = UInt8(
            max(
                0,
                min(
                    127,
                    Int((18 + (blend * 109)) * midiRoutingSettings.expressionDepth)
                )
            )
        )
        let modulationBlend = min(max((dynamics * articulationLift) + (layer.mix * 0.18), 0.0), 1.0)
        let modulationValue = UInt8(
            max(
                0,
                min(
                    127,
                    Int((modulationBlend * 127) * midiRoutingSettings.modulationDepth)
                )
            )
        )

        return LayerMIDIControlValues(
            modulation: modulationValue,
            expression: expressionValue
        )
    }
}
