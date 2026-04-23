import AppKit
import AVFoundation
import AudioToolbox
import ConductorCore
import Foundation

struct LibraryFolderDescriptor: Identifiable, Equatable {
    let path: String

    var id: String { path }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
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

    init() {
        loadLibraryFolders()
        refresh()
    }

    func refresh() {
        let audioUnits = discoverAudioUnits()
        let vsts = discoverFilesystemPlugins(format: .vst3, directories: vst3Directories, suffix: "vst3")
        let legacyVSTs = discoverFilesystemPlugins(format: .vst3, directories: vstDirectories, suffix: "vst")
        let libraryDescriptors = libraryFolders.map {
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

        statusText = "Discovered \(audioUnits.count) AU, \(vsts.count + legacyVSTs.count) VST, \(libraryDescriptors.count) library targets"
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
            return "Hostable now in standalone mode"
        case .vst3:
            return "Discovered, but VST hosting is not implemented yet"
        case .sampleLibrary:
            return "Indexed for future sample hosting, but not directly playable yet"
        }
    }

    func isHostableAudioUnit(_ instrumentID: String) -> Bool {
        audioUnitComponentsByID[instrumentID] != nil
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

            libraryFolders.append(LibraryFolderDescriptor(path: path))
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
        libraryFolders = storedPaths.map(LibraryFolderDescriptor.init(path:))
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
}
