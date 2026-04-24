import Foundation

enum SampleLibraryArticulationFamily: String, CaseIterable, Identifiable, Codable, Sendable {
    case sustain
    case legato
    case accent
    case staccato
    case pulse
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sustain:
            return "Sustain"
        case .legato:
            return "Legato"
        case .accent:
            return "Accent"
        case .staccato:
            return "Short"
        case .pulse:
            return "Pulse"
        case .unknown:
            return "Generic"
        }
    }

    static func preferredFamily(for articulation: LayerArticulationStyle) -> SampleLibraryArticulationFamily {
        switch articulation {
        case .sustain:
            return .sustain
        case .legato:
            return .legato
        case .accent:
            return .accent
        case .staccato:
            return .staccato
        case .pulse:
            return .pulse
        }
    }
}

enum SampleLibraryArticulationMatcher {
    static func classify(displayName: String, detailText: String) -> SampleLibraryArticulationFamily {
        let haystack = "\(displayName) \(detailText)".lowercased()

        if containsAny(in: haystack, keywords: ["legato", "slur", "portamento", "porta"]) {
            return .legato
        }
        if containsAny(in: haystack, keywords: ["ostinato", "ost", "pulse", "arp", "arpeggio", "rhythm", "rhythmic", "pattern", "drive"]) {
            return .pulse
        }
        if containsAny(in: haystack, keywords: ["spicc", "stacc", "pizz", "pluck", "short", "shorts", "detache", "détaché"]) {
            return .staccato
        }
        if containsAny(in: haystack, keywords: ["marc", "accent", "sfz", "sforz", "stab", "hit"]) {
            return .accent
        }
        if containsAny(in: haystack, keywords: ["sustain", "sus", "long", "longs", "arco", "pad", "vib", "vibrato", "non vib", "warm"]) {
            return .sustain
        }

        return .unknown
    }

    static func recommendedTarget(
        from targets: [SampleLibraryPlayableTarget],
        for articulation: LayerArticulationStyle
    ) -> SampleLibraryPlayableTarget? {
        let preferredFamily = SampleLibraryArticulationFamily.preferredFamily(for: articulation)
        return targets.min { lhs, rhs in
            let leftScore = score(lhs.articulationFamily, preferred: preferredFamily)
            let rightScore = score(rhs.articulationFamily, preferred: preferredFamily)
            if leftScore != rightScore {
                return leftScore < rightScore
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func containsAny(in haystack: String, keywords: [String]) -> Bool {
        keywords.contains { haystack.contains($0) }
    }

    private static func score(
        _ family: SampleLibraryArticulationFamily,
        preferred: SampleLibraryArticulationFamily
    ) -> Int {
        if family == preferred {
            return 0
        }

        switch (preferred, family) {
        case (.legato, .sustain), (.sustain, .legato):
            return 1
        case (.accent, .staccato), (.staccato, .accent):
            return 1
        case (_, .unknown):
            return 2
        case (.pulse, .staccato), (.staccato, .pulse):
            return 2
        default:
            return 3
        }
    }
}
