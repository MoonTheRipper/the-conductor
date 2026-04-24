import Foundation

enum TrackingMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case simulator = "Simulator"
    case liveCamera = "Live Camera"

    var id: String { rawValue }
}
