import AppKit
import AVFoundation
import AudioToolbox
import ConductorCore
import Foundation

struct LibraryFolderDescriptor: Identifiable, Equatable {
    let path: String
    let audioFileCount: Int
    let presetFileCount: Int
    let indexedOnlyFileCount: Int

    var id: String { path }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var summaryText: String {
        if playableFileCount == 0 && indexedOnlyFileCount == 0 {
            return "No indexed sample or preset files yet"
        }

        var parts: [String] = []
        if audioFileCount > 0 {
            parts.append("\(audioFileCount) audio")
        }
        if presetFileCount > 0 {
            parts.append("\(presetFileCount) preset")
        }
        if indexedOnlyFileCount > 0 {
            parts.append("\(indexedOnlyFileCount) indexed-only")
        }
        return parts.joined(separator: " · ")
    }

    var playableFileCount: Int {
        audioFileCount + presetFileCount
    }

    var isPlayableNow: Bool {
        playableFileCount > 0
    }
}

struct SampleLibraryLoadPlan {
    let libraryDisplayName: String
    let target: SampleLibraryPlayableTarget

    var isPlayableNow: Bool {
        target.isPlayableNow
    }

    var displayName: String {
        "\(libraryDisplayName) · \(target.displayName)"
    }

    var targetDisplayName: String {
        target.displayName
    }

    var presetURL: URL? {
        target.presetURL
    }

    var audioFileURLs: [URL] {
        target.audioFileURLs
    }

    var hostSummaryText: String {
        target.hostSummaryText
    }
}

struct SampleLibraryPlayableTarget: Identifiable, Equatable {
    enum Kind: String {
        case preset
        case audioBatch
    }

    let id: String
    let kind: Kind
    let displayName: String
    let detailText: String
    let articulationFamily: SampleLibraryArticulationFamily
    let presetURL: URL?
    let audioFileURLs: [URL]

    var isPlayableNow: Bool {
        presetURL != nil || audioFileURLs.isEmpty == false
    }

    var hostSummaryText: String {
        switch kind {
        case .preset:
            return presetURL.map { "Sampler preset: \($0.lastPathComponent)" } ?? detailText
        case .audioBatch:
            if let firstAudio = audioFileURLs.first {
                return audioFileURLs.count == 1
                    ? "Single audio sample: \(firstAudio.lastPathComponent)"
                    : "\(audioFileURLs.count) audio samples starting with \(firstAudio.lastPathComponent)"
            }
            return detailText
        }
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
    private let audioSampleExtensions: Set<String> = [
        "wav", "aif", "aiff", "caf", "mp3", "m4a",
    ]
    private let playablePresetExtensions: Set<String> = [
        "aupreset", "exs", "sf2", "dls",
    ]
    private let indexedOnlyExtensions: Set<String> = [
        "nki", "nkm", "sfz",
    ]
    private var playableTargetsByLibraryPath: [String: [SampleLibraryPlayableTarget]] = [:]

    init() {
        loadLibraryFolders()
        refresh()
    }

    func refresh() {
        playableTargetsByLibraryPath = [:]
        let audioUnits = discoverAudioUnits()
        let vsts = discoverFilesystemPlugins(format: .vst3, directories: vst3Directories, suffix: "vst3")
        let legacyVSTs = discoverFilesystemPlugins(format: .vst3, directories: vstDirectories, suffix: "vst")
        let indexedLibraryFolders = libraryFolders.map { folder in
            indexedLibraryFolder(at: folder.path)
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

        let indexedLibraryFiles = indexedLibraryFolders.reduce(0) {
            $0 + $1.playableFileCount + $1.indexedOnlyFileCount
        }
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
            if isHostableAudioUnit(instrumentID) {
                return "Hostable now in standalone mode · \(audioUnitTypeLabel(for: instrumentID))"
            }
            return "Discovered, but direct hosting is only implemented for MIDI-playable Audio Units"
        case .vst3:
            return "Discovered, but VST hosting is not implemented yet"
        case .sampleLibrary:
            if let folder = libraryFolders.first(where: { "library-\($0.path)" == instrumentID }) {
                let targetCount = sampleLibraryPlayableTargets(for: instrumentID).count
                return folder.isPlayableNow
                    ? "\(folder.summaryText) · \(targetCount) playable target\(targetCount == 1 ? "" : "s")"
                    : "\(folder.summaryText) · indexed for future sample hosting"
            }
            return "Indexed for future sample hosting, but not directly playable yet"
        }
    }

    func isHostableAudioUnit(_ instrumentID: String) -> Bool {
        guard let component = audioUnitComponentsByID[instrumentID] else {
            return false
        }

        switch component.audioComponentDescription.componentType {
        case kAudioUnitType_MusicDevice, kAudioUnitType_MIDIProcessor:
            return true
        default:
            return false
        }
    }

    func isStandalonePlayable(_ instrumentID: String) -> Bool {
        if isHostableAudioUnit(instrumentID) {
            return true
        }

        return sampleLibraryLoadPlan(for: instrumentID)?.isPlayableNow == true
    }

    func catalogLine(for instrument: InstrumentDescriptor) -> String {
        switch instrument.format {
        case .audioUnit:
            let hostability = isHostableAudioUnit(instrument.id) ? "hostable now" : "discovery only"
            return "\(instrument.format.rawValue) · \(audioUnitTypeLabel(for: instrument.id)) · \(hostability) · \(instrument.source)"
        case .vst3:
            return "\(instrument.format.rawValue) · discovery only · \(instrument.source)"
        case .sampleLibrary:
            return "\(instrument.format.rawValue) · \(standaloneCapabilitySummary(for: instrument.id))"
        }
    }

    func sampleLibraryLoadPlan(for instrumentID: String, maxAudioFiles: Int = 24) -> SampleLibraryLoadPlan? {
        sampleLibraryLoadPlan(for: instrumentID, selectedTargetID: nil, maxAudioFiles: maxAudioFiles)
    }

    func sampleLibraryPlayableTargets(
        for instrumentID: String,
        maxAudioFilesPerTarget: Int = 24
    ) -> [SampleLibraryPlayableTarget] {
        guard let folder = libraryFolders.first(where: { "library-\($0.path)" == instrumentID }) else {
            return []
        }

        if let cached = playableTargetsByLibraryPath[folder.path] {
            return cached
        }

        let targets = buildPlayableTargets(at: folder.path, maxAudioFilesPerTarget: maxAudioFilesPerTarget)
        playableTargetsByLibraryPath[folder.path] = targets
        return targets
    }

    func recommendedSampleLibraryTarget(
        for instrumentID: String,
        articulation: LayerArticulationStyle
    ) -> SampleLibraryPlayableTarget? {
        let playableTargets = sampleLibraryPlayableTargets(for: instrumentID)
        guard playableTargets.isEmpty == false else { return nil }
        return SampleLibraryArticulationMatcher.recommendedTarget(from: playableTargets, for: articulation)
    }

    func sampleLibraryLoadPlan(
        for instrumentID: String,
        selectedTargetID: String?,
        maxAudioFiles: Int = 24
    ) -> SampleLibraryLoadPlan? {
        guard let folder = libraryFolders.first(where: { "library-\($0.path)" == instrumentID }) else {
            return nil
        }

        let playableTargets = sampleLibraryPlayableTargets(
            for: instrumentID,
            maxAudioFilesPerTarget: maxAudioFiles
        )
        guard playableTargets.isEmpty == false else {
            return nil
        }

        let selectedTarget = selectedTargetID.flatMap { targetID in
            playableTargets.first(where: { $0.id == targetID })
        } ?? playableTargets.first

        guard let selectedTarget else {
            return nil
        }

        return SampleLibraryLoadPlan(
            libraryDisplayName: folder.displayName,
            target: selectedTarget
        )
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

            libraryFolders.append(indexedLibraryFolder(at: path))
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
        libraryFolders = storedPaths.map { indexedLibraryFolder(at: $0) }
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

    private func indexedLibraryFolder(at path: String) -> LibraryFolderDescriptor {
        let assets = collectLibraryAssets(at: path, maxAudioFiles: 0)
        return LibraryFolderDescriptor(
            path: path,
            audioFileCount: assets.audioSampleCount,
            presetFileCount: assets.playablePresetCount,
            indexedOnlyFileCount: assets.indexedOnlyCount
        )
    }

    private func buildPlayableTargets(
        at path: String,
        maxAudioFilesPerTarget: Int
    ) -> [SampleLibraryPlayableTarget] {
        let rootURL = URL(fileURLWithPath: path)
        let assets = collectLibraryAssets(at: path, maxAudioFiles: 0)

        let presetTargets = assets.playablePresetURLs.map { presetURL in
            let displayName = presetURL.deletingPathExtension().lastPathComponent
            let detailText = "Preset · \(relativePath(for: presetURL, inside: rootURL))"
            return SampleLibraryPlayableTarget(
                id: "preset::\(presetURL.path)",
                kind: .preset,
                displayName: displayName,
                detailText: detailText,
                articulationFamily: SampleLibraryArticulationMatcher.classify(displayName: displayName, detailText: detailText),
                presetURL: presetURL,
                audioFileURLs: []
            )
        }

        let groupedAudioFiles = Dictionary(grouping: assets.audioSampleURLs) { fileURL in
            fileURL.deletingLastPathComponent().path
        }

        let audioTargets = groupedAudioFiles
            .map { directoryPath, fileURLs -> SampleLibraryPlayableTarget in
                let directoryURL = URL(fileURLWithPath: directoryPath)
                let sortedFiles = fileURLs.sorted {
                    $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
                }
                let clippedFiles = Array(sortedFiles.prefix(maxAudioFilesPerTarget))
                let relativeDirectory = relativeDirectoryName(for: directoryURL, inside: rootURL)
                let displayName: String
                let detailText: String

                if sortedFiles.count == 1, let fileURL = sortedFiles.first {
                    displayName = fileURL.deletingPathExtension().lastPathComponent
                    detailText = "Sample · \(relativePath(for: fileURL, inside: rootURL))"
                } else {
                    displayName = relativeDirectory
                    let clipSuffix = clippedFiles.count < sortedFiles.count
                        ? " · loading first \(clippedFiles.count)"
                        : ""
                    detailText = "\(sortedFiles.count) samples · \(relativeDirectory)\(clipSuffix)"
                }

                return SampleLibraryPlayableTarget(
                    id: "audio::\(directoryPath)",
                    kind: .audioBatch,
                    displayName: displayName,
                    detailText: detailText,
                    articulationFamily: SampleLibraryArticulationMatcher.classify(displayName: displayName, detailText: detailText),
                    presetURL: nil,
                    audioFileURLs: clippedFiles
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        return presetTargets + audioTargets
    }

    private func collectLibraryAssets(at path: String, maxAudioFiles: Int) -> (
        audioSampleURLs: [URL],
        playablePresetURLs: [URL],
        audioSampleCount: Int,
        playablePresetCount: Int,
        indexedOnlyCount: Int
    ) {
        let url = URL(fileURLWithPath: path)
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return ([], [], 0, 0, 0)
        }

        var audioSampleURLs: [URL] = []
        var presetURLs: [URL] = []
        var audioSampleCount = 0
        var playablePresetCount = 0
        var indexedOnlyCount = 0

        for case let fileURL as URL in enumerator {
            let fileExtension = fileURL.pathExtension.lowercased()
            if audioSampleExtensions.contains(fileExtension) {
                audioSampleCount += 1
                if maxAudioFiles == 0 || audioSampleURLs.count < maxAudioFiles {
                    audioSampleURLs.append(fileURL)
                }
            } else if playablePresetExtensions.contains(fileExtension) {
                playablePresetCount += 1
                presetURLs.append(fileURL)
            } else if indexedOnlyExtensions.contains(fileExtension) {
                indexedOnlyCount += 1
            }
        }

        return (
            audioSampleURLs.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending },
            presetURLs.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending },
            audioSampleCount,
            playablePresetCount,
            indexedOnlyCount
        )
    }

    private func relativePath(for url: URL, inside rootURL: URL) -> String {
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        if url.path.hasPrefix(rootPath) {
            return String(url.path.dropFirst(rootPath.count))
        }
        return url.lastPathComponent
    }

    private func relativeDirectoryName(for directoryURL: URL, inside rootURL: URL) -> String {
        if directoryURL.path == rootURL.path {
            return "\(rootURL.lastPathComponent) Samples"
        }
        let relativePath = relativePath(for: directoryURL, inside: rootURL)
        return relativePath.isEmpty ? "\(rootURL.lastPathComponent) Samples" : relativePath
    }
}
