import Foundation
import simd

public enum PitchClass: Int, CaseIterable, Identifiable, Sendable {
    case c = 0
    case cSharp
    case d
    case eFlat
    case e
    case f
    case fSharp
    case g
    case aFlat
    case a
    case bFlat
    case b

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .c: return "C"
        case .cSharp: return "C#"
        case .d: return "D"
        case .eFlat: return "Eb"
        case .e: return "E"
        case .f: return "F"
        case .fSharp: return "F#"
        case .g: return "G"
        case .aFlat: return "Ab"
        case .a: return "A"
        case .bFlat: return "Bb"
        case .b: return "B"
        }
    }

    public func transposed(by semitones: Int) -> PitchClass {
        let wrapped = (rawValue + semitones % 12 + 12) % 12
        return PitchClass(rawValue: wrapped) ?? .c
    }
}

public enum ChordQuality: String, CaseIterable, Identifiable, Sendable {
    case major9
    case minor9
    case dominant13
    case suspended2
    case suspended4
    case diminished7
    case halfDiminished
    case major7Sharp11
    case major6Add9
    case minor6

    public var id: String { rawValue }

    public var symbolSuffix: String {
        switch self {
        case .major9: return "maj9"
        case .minor9: return "m9"
        case .dominant13: return "13"
        case .suspended2: return "sus2"
        case .suspended4: return "sus4"
        case .diminished7: return "dim7"
        case .halfDiminished: return "m7b5"
        case .major7Sharp11: return "maj7#11"
        case .major6Add9: return "6/9"
        case .minor6: return "m6"
        }
    }

    public var displayName: String {
        switch self {
        case .major9: return "Major 9"
        case .minor9: return "Minor 9"
        case .dominant13: return "Dominant 13"
        case .suspended2: return "Sus 2"
        case .suspended4: return "Sus 4"
        case .diminished7: return "Diminished 7"
        case .halfDiminished: return "Half-Diminished"
        case .major7Sharp11: return "Major 7 #11"
        case .major6Add9: return "6/9"
        case .minor6: return "Minor 6"
        }
    }
}

public enum HarmonicFunction: String, CaseIterable, Identifiable, Sendable {
    case tonic = "Tonic"
    case predominant = "Predominant"
    case dominant = "Dominant"
    case borrowed = "Borrowed"
    case color = "Color"

    public var id: String { rawValue }
}

public enum IntervalChoice: Int, CaseIterable, Identifiable, Sendable {
    case root = 0
    case third = 4
    case fifth = 7
    case seventh = 11
    case ninth = 14
    case eleventh = 17
    case thirteenth = 21

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .root: return "1"
        case .third: return "3"
        case .fifth: return "5"
        case .seventh: return "7"
        case .ninth: return "9"
        case .eleventh: return "11"
        case .thirteenth: return "13"
        }
    }

    public var spokenName: String {
        switch self {
        case .root: return "Root"
        case .third: return "Third"
        case .fifth: return "Fifth"
        case .seventh: return "Seventh"
        case .ninth: return "Ninth"
        case .eleventh: return "Eleventh"
        case .thirteenth: return "Thirteenth"
        }
    }
}

public enum HandOpenness: String, CaseIterable, Identifiable, Sendable {
    case closed
    case relaxed
    case open

    public var id: String { rawValue }
}

public struct HandState: Equatable, Sendable {
    public var position: SIMD2<Double>
    public var pinch: Double
    public var openness: HandOpenness
    public var verticalVelocity: Double

    public init(
        position: SIMD2<Double>,
        pinch: Double,
        openness: HandOpenness,
        verticalVelocity: Double
    ) {
        self.position = position
        self.pinch = pinch
        self.openness = openness
        self.verticalVelocity = verticalVelocity
    }
}

public struct GestureSnapshot: Sendable {
    public var leftHand: HandState?
    public var rightHand: HandState?
    public var timestamp: TimeInterval

    public init(
        leftHand: HandState?,
        rightHand: HandState?,
        timestamp: TimeInterval
    ) {
        self.leftHand = leftHand
        self.rightHand = rightHand
        self.timestamp = timestamp
    }
}

public struct ChordSelection: Equatable, Identifiable, Sendable {
    public var root: PitchClass
    public var quality: ChordQuality
    public var function: HarmonicFunction

    public init(
        root: PitchClass,
        quality: ChordQuality,
        function: HarmonicFunction
    ) {
        self.root = root
        self.quality = quality
        self.function = function
    }

    public var id: String { symbol }

    public var symbol: String {
        root.displayName + quality.symbolSuffix
    }
}

public struct LoopPhraseEvent: Equatable, Identifiable, Sendable {
    public var chord: ChordSelection
    public var interval: IntervalChoice
    public var dynamics: Double
    public var timestamp: TimeInterval

    public init(
        chord: ChordSelection,
        interval: IntervalChoice,
        dynamics: Double,
        timestamp: TimeInterval
    ) {
        self.chord = chord
        self.interval = interval
        self.dynamics = dynamics
        self.timestamp = timestamp
    }

    public var id: String {
        "\(timestamp)-\(chord.symbol)-\(interval.rawValue)"
    }
}

public struct PlotPosition: Equatable, Sendable {
    public var angle: Double
    public var radius: Double
    public var normalized: SIMD2<Double>

    public init(angle: Double, radius: Double, normalized: SIMD2<Double>) {
        self.angle = angle
        self.radius = radius
        self.normalized = normalized
    }
}

public struct LoopBuffer: Equatable, Sendable {
    public var phrase: [LoopPhraseEvent]
    public var isRecording: Bool
    public var isPlaying: Bool
    public var startTimestamp: TimeInterval?
    public var endTimestamp: TimeInterval?

    public init(
        phrase: [LoopPhraseEvent] = [],
        isRecording: Bool = false,
        isPlaying: Bool = false,
        startTimestamp: TimeInterval? = nil,
        endTimestamp: TimeInterval? = nil
    ) {
        self.phrase = phrase
        self.isRecording = isRecording
        self.isPlaying = isPlaying
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
    }

    public var statusLabel: String {
        if isRecording {
            return "Recording"
        }

        if isPlaying {
            return "Looping"
        }

        return phrase.isEmpty ? "Idle" : "Ready"
    }
}

public enum PerformanceEvent: Equatable, Sendable {
    case chordCommitted(
        chord: ChordSelection,
        interval: IntervalChoice,
        dynamics: Double,
        timestamp: TimeInterval
    )
    case transportChanged(
        isPerforming: Bool,
        timestamp: TimeInterval
    )
    case loopStateChanged(
        loopBuffer: LoopBuffer,
        timestamp: TimeInterval
    )
}

public struct LayerState: Identifiable, Equatable, Sendable {
    public var name: String
    public var mix: Double
    public var isEnabled: Bool

    public init(name: String, mix: Double, isEnabled: Bool) {
        self.name = name
        self.mix = mix
        self.isEnabled = isEnabled
    }

    public var id: String { name }
}

public struct PerformanceState: Equatable, Sendable {
    public var currentChord: ChordSelection
    public var previewChord: ChordSelection
    public var interval: IntervalChoice
    public var dynamics: Double
    public var isPerforming: Bool
    public var loopBuffer: LoopBuffer
    public var layers: [LayerState]
    public var chordPlot: PlotPosition
    public var intervalPlot: PlotPosition
    public var activityText: String

    public init(
        currentChord: ChordSelection,
        previewChord: ChordSelection,
        interval: IntervalChoice,
        dynamics: Double,
        isPerforming: Bool,
        loopBuffer: LoopBuffer,
        layers: [LayerState],
        chordPlot: PlotPosition,
        intervalPlot: PlotPosition,
        activityText: String
    ) {
        self.currentChord = currentChord
        self.previewChord = previewChord
        self.interval = interval
        self.dynamics = dynamics
        self.isPerforming = isPerforming
        self.loopBuffer = loopBuffer
        self.layers = layers
        self.chordPlot = chordPlot
        self.intervalPlot = intervalPlot
        self.activityText = activityText
    }
}
