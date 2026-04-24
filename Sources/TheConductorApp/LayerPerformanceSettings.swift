import Foundation

enum LayerArticulationStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case sustain = "Sustain"
    case legato = "Legato"
    case accent = "Accent"
    case staccato = "Staccato"
    case pulse = "Pulse"

    var id: String { rawValue }

    var summaryText: String {
        switch self {
        case .sustain:
            return "Balanced hold for broad voicings"
        case .legato:
            return "Longer phrase overlap for pads and lines"
        case .accent:
            return "Sharper attacks with extra push"
        case .staccato:
            return "Short, separated chord statements"
        case .pulse:
            return "Tight rhythmic note lengths"
        }
    }

    var holdMultiplier: Double {
        switch self {
        case .sustain:
            return 1.0
        case .legato:
            return 1.4
        case .accent:
            return 0.82
        case .staccato:
            return 0.45
        case .pulse:
            return 0.28
        }
    }

    var velocityMultiplier: Double {
        switch self {
        case .sustain:
            return 1.0
        case .legato:
            return 0.92
        case .accent:
            return 1.14
        case .staccato:
            return 1.02
        case .pulse:
            return 0.96
        }
    }
}

struct LayerPerformanceSettings: Codable, Equatable, Sendable {
    var articulation: LayerArticulationStyle
    var octaveShift: Int
    var maxVoices: Int
    var velocityBias: Double
    var holdScale: Double

    static func `default`(for layerName: String) -> LayerPerformanceSettings {
        switch layerName {
        case "Strings":
            return LayerPerformanceSettings(
                articulation: .legato,
                octaveShift: 0,
                maxVoices: 4,
                velocityBias: 0,
                holdScale: 1.08
            )
        case "Brass":
            return LayerPerformanceSettings(
                articulation: .accent,
                octaveShift: 0,
                maxVoices: 4,
                velocityBias: 6,
                holdScale: 0.9
            )
        case "Woods":
            return LayerPerformanceSettings(
                articulation: .sustain,
                octaveShift: 1,
                maxVoices: 3,
                velocityBias: -4,
                holdScale: 1.0
            )
        case "Pulse":
            return LayerPerformanceSettings(
                articulation: .pulse,
                octaveShift: -1,
                maxVoices: 2,
                velocityBias: 0,
                holdScale: 0.72
            )
        default:
            return LayerPerformanceSettings(
                articulation: .sustain,
                octaveShift: 0,
                maxVoices: 3,
                velocityBias: 0,
                holdScale: 1.0
            )
        }
    }

    var summaryText: String {
        let octaveText = octaveShift == 0 ? "0 oct" : "\(octaveShift > 0 ? "+" : "")\(octaveShift) oct"
        return "\(articulation.rawValue) · \(octaveText) · \(maxVoices) voices · vel \(Int(velocityBias)) · len x\(String(format: "%.2f", holdScale))"
    }

    var topologyText: String {
        "\(articulation.rawValue.lowercased()) · \(octaveShift > 0 ? "+" : "")\(octaveShift) oct · \(maxVoices) voices"
    }
}
