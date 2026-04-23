import AppKit
import AVFoundation
import AudioToolbox
import ConductorCore
import Foundation

struct LibraryFolderDescriptor: Identifiable, Equatable {
    let path: String
    let candidateFileCount: Int

    var id: String { path }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var summaryText: String {
        candidateFileCount == 0
            ? "No indexed sample or preset files yet"
            : "\(candidateFileCount) indexed sample or preset files"
    }
}

@MainActor
final class StandaloneInstrumentCatalogService: ObservableObject {
    @Published private(set) var instruments: [InstrumentDescriptor] = []
    @Published private(set) var libraryFolders: [LibraryFolderDescriptor] = []
    @Published private(set) var statusText = "Standalone catalog idle"

    private let defaultsKey = "TheConductor.libraryFolders"
    private let fileManager = FileManager.default
    private var audioUnitComponentsByID: [String: AVAudioUnitComponent] = [:]
    private let libraryCandidateExtensions: Set<String> = [
        "wav", "aif", "aiff", "caf", "mp3", "m4a",
        "nki", "nkm", "exs", "sfz", "sf2", "aupreset",
    ]

    init() {
        loadLibraryFolders()
        refresh()
    }

    func refresh() {
        let audioUnits = discoverAudioUnits()
        let vsts = discoverFilesystemPlugins(format: .vst3, directories: vst3Directories, suffix: "vst3")
        let legacyVSTs = discoverFilesystemPlugins(format: .vst3, directories: vstDirectories, suffix: "vst")
        let indexedLibraryFolders = libraryFolders.map { folder in
            LibraryFolderDescriptor(
                path: folder.path,
                candidateFileCount: countLibraryCandidates(at: folder.path)
            )
        }
        libraryFolders = indexedLibraryFolders

        let libraryDescriptors = indexedLibraryFolders.map {
            InstrumentDescriptor(
                id: "library-\($0.path)",
                name: $0.displayName,
                format: .sampleLibrary,
                source: $0.path
            )
        }

        instruments = deduplicated(audioUnits + vsts + legacyVSTs + libraryDescriptors)
            .sorted { lhs, rhs in
                if lhs.format != rhs.format {
                    return lhs.format.rawValue < rhs.format.rawValue
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        let indexedLibraryFiles = indexedLibraryFolders.reduce(0) { $0 + $1.candidateFileCount }
        statusText = "Discovered \(audioUnits.count) AU, \(vsts.count + legacyVSTs.count) VST, \(libraryDescriptors.count) library targets · indexed \(indexedLibraryFiles) files"
    }

    func audioUnitDescription(for instrumentID: String) -> AudioComponentDescription? {
        audioUnitComponentsByID[instrumentID]?.audioComponentDescription
    }

    func standaloneCapabilitySummary(for instrumentID: String) -> String {
        guard let instrument = instruments.first(where: { $0.id == instrumentID }) else {
            return "No instrument selected"
        }

        switch instrument.format {
        case .audioUnit:
            return "Hostable now in standalone mode · \(audioUnitTypeLabel(for: instrumentID))"
        case .vst3:
            return "Discovered, but VST hosting is not implemented yet"
        case .sampleLibrary:
            if let folder = libraryFolders.first(where: { "library-\($0.path)" == instrumentID }) {
                return "\(folder.summaryText) · indexed for future sample hosting"
            }
            return "Indexed for future sample hosting, but not directly playable yet"
        }
    }

    func isHostableAudioUnit(_ instrumentID: String) -> Bool {
        audioUnitComponentsByID[instrumentID] != nil
    }

    func catalogLine(for instrument: InstrumentDescriptor) -> String {
        switch instrument.format {
        case .audioUnit:
            return "\(instrument.format.rawValue) · \(audioUnitTypeLabel(for: instrument.id)) · hostable now · \(instrument.source)"
        case .vst3:
            return "\(instrument.format.rawValue) · discovery only · \(instrument.source)"
        case .sampleLibrary:
            return "\(instrument.format.rawValue) · \(standaloneCapabilitySummary(for: instrument.id))"
        }
    }

    func addLibraryFolder() {
        let panel = NSOpenPanel()
        panel.prompt = "Add Library Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = "Choose a sample or instrument library folder"

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            guard libraryFolders.contains(where: { $0.path == path }) == false else {
                statusText = "Library folder already added"
                return
            }

            libraryFolders.append(LibraryFolderDescriptor(path: path, candidateFileCount: 0))
            persistLibraryFolders()
            refresh()
        }
    }

    func removeLibraryFolder(id: String) {
        libraryFolders.removeAll { $0.id == id }
        persistLibraryFolders()
        refresh()
    }

    private func loadLibraryFolders() {
        let storedPaths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        libraryFolders = storedPaths.map { LibraryFolderDescriptor(path: $0, candidateFileCount: 0) }
    }

    private func persistLibraryFolders() {
        UserDefaults.standard.set(libraryFolders.map(\.path), forKey: defaultsKey)
    }

    private func discoverAudioUnits() -> [InstrumentDescriptor] {
        let manager = AVAudioUnitComponentManager.shared()
        let descriptions = [
            AudioComponentDescription(
                componentType: kAudioUnitType_MusicDevice,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            ),
            AudioComponentDescription(
                componentType: kAudioUnitType_Generator,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            ),
        ]

        let components = descriptions.flatMap { manager.components(matching: $0) }
        audioUnitComponentsByID = [:]

        return components.map { component in
            let descriptor = InstrumentDescriptor(
                id: "au-\(component.audioComponentDescription.componentManufacturer)-\(component.audioComponentDescription.componentSubType)-\(component.name)",
                name: component.name,
                format: .audioUnit,
                source: component.manufacturerName
            )
            audioUnitComponentsByID[descriptor.id] = component
            return descriptor
        }
    }

    private func discoverFilesystemPlugins(
        format: InstrumentFormat,
        directories: [URL],
        suffix: String
    ) -> [InstrumentDescriptor] {
        directories.flatMap { directory in
            guard let children = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return [InstrumentDescriptor]()
            }

            return children.compactMap { url in
                guard url.pathExtension.lowercased() == suffix else { return nil }
                let name = url.deletingPathExtension().lastPathComponent
                return InstrumentDescriptor(
                    id: "\(suffix)-\(url.path)",
                    name: name,
                    format: format,
                    source: directory.path
                )
            }
        }
    }

    private func deduplicated(_ descriptors: [InstrumentDescriptor]) -> [InstrumentDescriptor] {
        var seen = Set<String>()
        return descriptors.filter { descriptor in
            let key = "\(descriptor.name.lowercased())::\(descriptor.format.rawValue)"
            return seen.insert(key).inserted
        }
    }

    private var vst3Directories: [URL] {
        standardPluginDirectories(named: "VST3")
    }

    private var vstDirectories: [URL] {
        standardPluginDirectories(named: "VST")
    }

    private func standardPluginDirectories(named folderName: String) -> [URL] {
        let local = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/\(folderName)")
        let home = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Audio/Plug-Ins/\(folderName)")
        return [local, home]
    }

    private func audioUnitTypeLabel(for instrumentID: String) -> String {
        guard let component = audioUnitComponentsByID[instrumentID] else {
            return "Audio Unit"
        }

        switch component.audioComponentDescription.componentType {
        case kAudioUnitType_MusicDevice:
            return "Music Device"
        case kAudioUnitType_Generator:
            return "Generator"
        default:
            return "Audio Unit"
        }
    }

    private func countLibraryCandidates(at path: String) -> Int {
        let url = URL(fileURLWithPath: path)
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }

        var count = 0
        for case let fileURL as URL in enumerator {
            guard count < 5_000 else { break }
            let fileExtension = fileURL.pathExtension.lowercased()
            if libraryCandidateExtensions.contains(fileExtension) {
                count += 1
            }
        }
        return count
    }
}
