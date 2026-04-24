import ConductorCore
import CoreMIDI
import Foundation

struct MIDIDestinationDescriptor: Identifiable, Equatable {
    let id: String
    let name: String
    let isLikelyLogicInput: Bool
}

@MainActor
final class LogicMIDIBridgeService: ObservableObject {
    static let noDestinationID = "none"

    @Published private(set) var destinations: [MIDIDestinationDescriptor] = []
    @Published private(set) var selectedDestinationID = noDestinationID
    @Published var sendToVirtualSource = true {
        didSet { updateStatusText() }
    }
    @Published private(set) var statusText = "MIDI bridge ready"

    let virtualSourceName = "The Conductor"

    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var virtualSource = MIDIEndpointRef()
    private var endpointByID: [String: MIDIEndpointRef] = [:]
    private var noteGeneration = 0

    init() {
        setupMIDI()
        refreshDestinations()
    }

    deinit {
        if outputPort != 0 {
            MIDIPortDispose(outputPort)
        }
        if virtualSource != 0 {
            MIDIEndpointDispose(virtualSource)
        }
        if client != 0 {
            MIDIClientDispose(client)
        }
    }

    var channelMapDescription: [String] {
        PerformanceLayerPlanner.channelMapDescription
    }

    func refreshDestinations() {
        var refreshed: [MIDIDestinationDescriptor] = []
        endpointByID.removeAll()

        let count = MIDIGetNumberOfDestinations()
        for index in 0..<count {
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { continue }

            let name = midiObjectName(for: endpoint, fallback: "Destination \(index + 1)")
            let uniqueID = midiObjectUniqueID(for: endpoint, fallback: Int32(index + 1))
            let identifier = String(uniqueID)

            endpointByID[identifier] = endpoint
            refreshed.append(
                MIDIDestinationDescriptor(
                    id: identifier,
                    name: name,
                    isLikelyLogicInput: name.localizedCaseInsensitiveContains("logic")
                )
            )
        }

        destinations = refreshed.sorted {
            if $0.isLikelyLogicInput != $1.isLikelyLogicInput {
                return $0.isLikelyLogicInput && !$1.isLikelyLogicInput
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        if endpointByID[selectedDestinationID] == nil {
            selectedDestinationID = destinations.first(where: \.isLikelyLogicInput)?.id ?? Self.noDestinationID
        }

        updateStatusText()
    }

    func setSelectedDestination(id: String) {
        selectedDestinationID = endpointByID[id] == nil ? Self.noDestinationID : id
        updateStatusText()
    }

    func silenceAllNotes() {
        noteGeneration += 1
        emitAllNotesOff()
        statusText = "Sent all-notes-off"
    }

    func send(
        chord: ChordSelection,
        interval: IntervalChoice,
        dynamics: Double,
        layers: [LayerState],
        performanceSettingsByLayer: [String: LayerPerformanceSettings]
    ) {
        guard hasOutputTarget else {
            statusText = "No MIDI target selected"
            return
        }

        let payloads = PerformanceLayerPlanner.payloads(
            chord: chord,
            interval: interval,
            dynamics: dynamics,
            layers: layers,
            performanceSettingsByLayer: performanceSettingsByLayer
        )

        guard payloads.isEmpty == false else {
            statusText = "No enabled layers to send"
            return
        }

        noteGeneration += 1
        let generation = noteGeneration

        emitAllNotesOff()

        for payload in payloads {
            let bytes = payload.notes.flatMap { note in
                [UInt8(0x90 | payload.channel), note, payload.velocity]
            }
            dispatch(bytes: bytes)

            let noteOffBytes = payload.notes.flatMap { note in
                [UInt8(0x80 | payload.channel), note, 0]
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + payload.holdDuration) { [weak self] in
                guard let self, self.noteGeneration == generation else { return }
                self.dispatch(bytes: noteOffBytes)
            }
        }

        let cleanupDuration = (payloads.map(\.holdDuration).max() ?? (0.45 + (dynamics * 0.65))) + 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + cleanupDuration) { [weak self] in
            guard let self, self.noteGeneration == generation else { return }
            self.emitAllNotesOff()
        }

        statusText = "Sent \(chord.symbol) to \(routingSummary(payloadCount: payloads.count))"
    }

    private var hasOutputTarget: Bool {
        sendToVirtualSource || selectedEndpoint != nil
    }

    private var selectedEndpoint: MIDIEndpointRef? {
        endpointByID[selectedDestinationID]
    }

    private func setupMIDI() {
        let clientStatus = MIDIClientCreate("The Conductor" as CFString, nil, nil, &client)
        guard clientStatus == noErr else {
            statusText = "Failed to create MIDI client (\(clientStatus))"
            return
        }

        let portStatus = MIDIOutputPortCreate(client, "The Conductor Output" as CFString, &outputPort)
        guard portStatus == noErr else {
            statusText = "Failed to create MIDI output port (\(portStatus))"
            return
        }

        let sourceStatus = MIDISourceCreate(client, virtualSourceName as CFString, &virtualSource)
        guard sourceStatus == noErr else {
            statusText = "Failed to create virtual MIDI source (\(sourceStatus))"
            return
        }
    }

    private func emitAllNotesOff() {
        for layer in PerformanceLayerPlanner.layerChannels {
            dispatch(bytes: [UInt8(0xB0 | layer.channel), 123, 0])
            dispatch(bytes: [UInt8(0xB0 | layer.channel), 120, 0])
        }
    }

    private func dispatch(bytes: [UInt8]) {
        guard bytes.isEmpty == false else { return }

        withPacketList(bytes: bytes) { packetList in
            if sendToVirtualSource, virtualSource != 0 {
                MIDIReceived(virtualSource, packetList)
            }

            if let endpoint = selectedEndpoint, outputPort != 0 {
                MIDISend(outputPort, endpoint, packetList)
            }
        }
    }

    private func withPacketList(
        bytes: [UInt8],
        perform: (UnsafeMutablePointer<MIDIPacketList>) -> Void
    ) {
        let bufferSize = 1024
        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferSize,
            alignment: MemoryLayout<MIDIPacketList>.alignment
        )

        defer { rawPointer.deallocate() }

        let packetList = rawPointer.bindMemory(to: MIDIPacketList.self, capacity: 1)
        let packet = MIDIPacketListInit(packetList)

        bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            _ = MIDIPacketListAdd(packetList, bufferSize, packet, 0, buffer.count, baseAddress)
            perform(packetList)
        }
    }
    private func routingSummary(payloadCount: Int) -> String {
        let directTarget = selectedEndpoint.flatMap { _ in
            destinations.first(where: { $0.id == selectedDestinationID })?.name
        }

        switch (sendToVirtualSource, directTarget) {
        case (true, .some(let name)):
            return "\(virtualSourceName) and \(name) (\(payloadCount) layers)"
        case (true, .none):
            return "\(virtualSourceName) (\(payloadCount) layers)"
        case (false, .some(let name)):
            return "\(name) (\(payloadCount) layers)"
        case (false, .none):
            return "no target"
        }
    }

    private func updateStatusText() {
        let directTarget = destinations.first(where: { $0.id == selectedDestinationID })?.name ?? "None"
        let virtualState = sendToVirtualSource ? "On" : "Off"
        statusText = "Virtual source: \(virtualState) · Direct destination: \(directTarget)"
    }

    private func midiObjectName(for object: MIDIObjectRef, fallback: String) -> String {
        var unmanagedName: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &unmanagedName)
        if status == noErr, let unmanagedName {
            return unmanagedName.takeRetainedValue() as String
        }
        return fallback
    }

    private func midiObjectUniqueID(for object: MIDIObjectRef, fallback: Int32) -> Int32 {
        var uniqueID = MIDIUniqueID()
        let status = MIDIObjectGetIntegerProperty(object, kMIDIPropertyUniqueID, &uniqueID)
        return status == noErr ? uniqueID : fallback
    }
}
