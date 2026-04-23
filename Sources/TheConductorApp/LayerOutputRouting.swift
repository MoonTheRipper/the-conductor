import Foundation

enum LayerOutputBus: String, CaseIterable, Identifiable, Codable, Sendable {
    case core = "Core"
    case halo = "Halo"
    case drive = "Drive"

    var id: String { rawValue }

    var summaryText: String {
        switch self {
        case .core:
            return "Focused and direct"
        case .halo:
            return "Wide and atmospheric"
        case .drive:
            return "Rhythmic and forward"
        }
    }
}

struct LayerOutputSettings: Codable, Equatable, Sendable {
    var bus: LayerOutputBus
    var pan: Double
    var reverbMix: Double
    var delayMix: Double
    var delayTime: Double

    static func `default`(for layerName: String) -> LayerOutputSettings {
        switch layerName {
        case "Strings":
            return LayerOutputSettings(bus: .halo, pan: -0.12, reverbMix: 34, delayMix: 8, delayTime: 0.22)
        case "Brass":
            return LayerOutputSettings(bus: .core, pan: 0.08, reverbMix: 16, delayMix: 4, delayTime: 0.18)
        case "Woods":
            return LayerOutputSettings(bus: .halo, pan: 0.18, reverbMix: 28, delayMix: 10, delayTime: 0.24)
        case "Pulse":
            return LayerOutputSettings(bus: .drive, pan: 0.0, reverbMix: 6, delayMix: 18, delayTime: 0.31)
        default:
            return LayerOutputSettings(bus: .core, pan: 0.0, reverbMix: 20, delayMix: 8, delayTime: 0.24)
        }
    }

    var summaryText: String {
        "\(bus.rawValue) · pan \(Int(pan * 100)) · space \(Int(reverbMix))% · echo \(Int(delayMix))%"
    }
}
