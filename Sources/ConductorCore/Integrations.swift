import Foundation

public enum RoutingMode: String, CaseIterable, Identifiable, Sendable {
    case standaloneHost = "Standalone Host"
    case logicBridge = "Logic Bridge"

    public var id: String { rawValue }
}

public enum InstrumentFormat: String, CaseIterable, Identifiable, Sendable {
    case audioUnit = "AU"
    case vst3 = "VST3"
    case sampleLibrary = "Library"

    public var id: String { rawValue }
}

public struct InstrumentDescriptor: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var format: InstrumentFormat
    public var source: String

    public init(id: String, name: String, format: InstrumentFormat, source: String) {
        self.id = id
        self.name = name
        self.format = format
        self.source = source
    }
}

public protocol InstrumentCatalog: Sendable {
    func availableInstruments() -> [InstrumentDescriptor]
}

public protocol MIDIOutputRouting: Sendable {
    func availableDestinations() -> [String]
    func send(
        chord: ChordSelection,
        interval: IntervalChoice,
        dynamics: Double
    )
}

public protocol GestureTrackingBackend: Sendable {
    var displayName: String { get }
    func start()
    func stop()
}

public struct DemoInstrumentCatalog: InstrumentCatalog {
    public init() {}

    public func availableInstruments() -> [InstrumentDescriptor] {
        [
            InstrumentDescriptor(
                id: "kontakt8",
                name: "Kontakt 8",
                format: .vst3,
                source: "Third-Party Host"
            ),
            InstrumentDescriptor(
                id: "massive",
                name: "Massive",
                format: .vst3,
                source: "Third-Party Host"
            ),
            InstrumentDescriptor(
                id: "orchestra-strings",
                name: "Orchestra Strings",
                format: .sampleLibrary,
                source: "Library Slot"
            ),
            InstrumentDescriptor(
                id: "hybrid-choir",
                name: "Hybrid Choir",
                format: .sampleLibrary,
                source: "Library Slot"
            ),
        ]
    }
}
