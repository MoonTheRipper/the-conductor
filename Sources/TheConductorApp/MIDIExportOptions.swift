import Foundation

struct MIDIExportOptions: Codable, Equatable, Sendable {
    var clipName: String
    var tempoBPM: Double
    var repeatCount: Int

    static let `default` = MIDIExportOptions(
        clipName: "The Conductor Loop",
        tempoBPM: 120,
        repeatCount: 1
    )
}
