import ConductorCore
import Foundation
import Testing
@testable import TheConductorApp

struct PerformanceLayerPlannerTests {
    @Test
    func octaveShiftAndVoiceLimitShapeVoicing() {
        let baseLayers = [
            LayerState(name: "Strings", mix: 0.9, isEnabled: true),
        ]

        let defaultPayload = PerformanceLayerPlanner.payloads(
            chord: ChordSelection(root: .c, quality: .major9, function: .tonic),
            interval: .thirteenth,
            dynamics: 0.72,
            layers: baseLayers
        ).first

        let shiftedPayload = PerformanceLayerPlanner.payloads(
            chord: ChordSelection(root: .c, quality: .major9, function: .tonic),
            interval: .thirteenth,
            dynamics: 0.72,
            layers: baseLayers,
            performanceSettingsByLayer: [
                "Strings": LayerPerformanceSettings(
                    articulation: .legato,
                    octaveShift: 1,
                    maxVoices: 2,
                    velocityBias: 0,
                    holdScale: 1.0
                ),
            ]
        ).first

        #expect(defaultPayload != nil)
        #expect(shiftedPayload != nil)
        #expect(shiftedPayload?.notes.count == 2)
        #expect((shiftedPayload?.notes.first ?? 0) >= ((defaultPayload?.notes.first ?? 0) + 12))
    }

    @Test
    func articulationShapesHoldDurationAndVelocity() {
        let activeLayers = [
            LayerState(name: "Brass", mix: 0.85, isEnabled: true),
        ]

        let sustainPayload = PerformanceLayerPlanner.payloads(
            chord: ChordSelection(root: .f, quality: .dominant13, function: .dominant),
            interval: .ninth,
            dynamics: 0.68,
            layers: activeLayers,
            performanceSettingsByLayer: [
                "Brass": LayerPerformanceSettings(
                    articulation: .sustain,
                    octaveShift: 0,
                    maxVoices: 4,
                    velocityBias: 0,
                    holdScale: 1.0
                ),
            ]
        ).first

        let accentPayload = PerformanceLayerPlanner.payloads(
            chord: ChordSelection(root: .f, quality: .dominant13, function: .dominant),
            interval: .ninth,
            dynamics: 0.68,
            layers: activeLayers,
            performanceSettingsByLayer: [
                "Brass": LayerPerformanceSettings(
                    articulation: .accent,
                    octaveShift: 0,
                    maxVoices: 4,
                    velocityBias: 6,
                    holdScale: 0.9
                ),
            ]
        ).first

        let pulsePayload = PerformanceLayerPlanner.payloads(
            chord: ChordSelection(root: .f, quality: .dominant13, function: .dominant),
            interval: .ninth,
            dynamics: 0.68,
            layers: activeLayers,
            performanceSettingsByLayer: [
                "Brass": LayerPerformanceSettings(
                    articulation: .pulse,
                    octaveShift: 0,
                    maxVoices: 4,
                    velocityBias: 0,
                    holdScale: 0.7
                ),
            ]
        ).first

        #expect(sustainPayload != nil)
        #expect(accentPayload != nil)
        #expect(pulsePayload != nil)
        #expect((accentPayload?.velocity ?? 0) > (sustainPayload?.velocity ?? 0))
        #expect((pulsePayload?.holdDuration ?? 0) < (sustainPayload?.holdDuration ?? 0))
    }
}
