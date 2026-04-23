import Foundation

enum TrackingMode: String, CaseIterable, Identifiable {
    case simulator = "Simulator"
    case liveCamera = "Live Camera"

    var id: String { rawValue }
}
