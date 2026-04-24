import Foundation

struct LayerMIDIRoutingSettings: Codable, Equatable, Sendable {
    var channelNumber: Int
    var expressionDepth: Double
    var modulationDepth: Double

    static func `default`(for layerName: String) -> LayerMIDIRoutingSettings {
        switch layerName {
        case "Strings":
            return LayerMIDIRoutingSettings(channelNumber: 1, expressionDepth: 0.96, modulationDepth: 0.88)
        case "Brass":
            return LayerMIDIRoutingSettings(channelNumber: 2, expressionDepth: 0.82, modulationDepth: 0.54)
        case "Woods":
            return LayerMIDIRoutingSettings(channelNumber: 3, expressionDepth: 0.74, modulationDepth: 0.42)
        case "Pulse":
            return LayerMIDIRoutingSettings(channelNumber: 4, expressionDepth: 0.36, modulationDepth: 0.18)
        default:
            return LayerMIDIRoutingSettings(channelNumber: 1, expressionDepth: 0.75, modulationDepth: 0.5)
        }
    }

    var clampedChannel: UInt8 {
        UInt8(max(0, min(15, channelNumber - 1)))
    }

    var summaryText: String {
        "ch \(channelNumber) · expr \(Int(expressionDepth * 100))% · mod \(Int(modulationDepth * 100))%"
    }
}
