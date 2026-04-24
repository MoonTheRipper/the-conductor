import Combine
import Foundation

enum WorkspaceSection: String, CaseIterable, Identifiable, Codable {
    case dashboard
    case sound
    case layers
    case tracking
    case library
    case scenes
    case loop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            "Dashboard"
        case .sound:
            "Sound"
        case .layers:
            "Layers"
        case .tracking:
            "Tracking"
        case .library:
            "Library"
        case .scenes:
            "Scenes"
        case .loop:
            "Loop"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard:
            "Keep the performance state in view and reach the next action quickly."
        case .sound:
            "Choose the routing path and review standalone or Logic bridge status."
        case .layers:
            "Edit one orchestration layer at a time instead of managing all four at once."
        case .tracking:
            "Switch between simulator and camera tracking, then tune calibration only when needed."
        case .library:
            "Browse instruments and library folders with a clearer split between selection and details."
        case .scenes:
            "Save and recall complete session setups without hunting through the full UI."
        case .loop:
            "Capture, replay, and export phrases with transport and export controls grouped together."
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            "circle.grid.2x2"
        case .sound:
            "cable.connector"
        case .layers:
            "slider.horizontal.3"
        case .tracking:
            "hand.raised"
        case .library:
            "music.note.list"
        case .scenes:
            "square.stack"
        case .loop:
            "repeat.circle"
        }
    }
}

final class WorkspaceState: ObservableObject {
    @Published var selectedSection: WorkspaceSection? {
        didSet {
            guard selectedSection != oldValue, let selectedSection else { return }
            DebugEventFeed.shared.log("workspace", "Section -> \(selectedSection.title)")
        }
    }
    @Published var selectedLayerName: String? {
        didSet {
            guard selectedLayerName != oldValue, let selectedLayerName else { return }
            DebugEventFeed.shared.log("workspace", "Layer focus -> \(selectedLayerName)")
        }
    }
    @Published var showsCalibration: Bool {
        didSet {
            guard showsCalibration != oldValue else { return }
            DebugEventFeed.shared.log("workspace", "Calibration disclosure -> \(showsCalibration ? "open" : "closed")")
        }
    }
    @Published var showsGestureGuide: Bool {
        didSet {
            guard showsGestureGuide != oldValue else { return }
            DebugEventFeed.shared.log("workspace", "Gesture guide disclosure -> \(showsGestureGuide ? "open" : "closed")")
        }
    }
    @Published var showsMIDISummary: Bool {
        didSet {
            guard showsMIDISummary != oldValue else { return }
            DebugEventFeed.shared.log("workspace", "MIDI summary disclosure -> \(showsMIDISummary ? "open" : "closed")")
        }
    }
    @Published var showsSignalPaths: Bool {
        didSet {
            guard showsSignalPaths != oldValue else { return }
            DebugEventFeed.shared.log("workspace", "Signal paths disclosure -> \(showsSignalPaths ? "open" : "closed")")
        }
    }

    init() {
        let defaults = UserDefaults.standard
        let storedSection = defaults.string(forKey: AppPreferences.Keys.launchSection.rawValue)
        self.selectedSection = storedSection.flatMap(WorkspaceSection.init(rawValue:)) ?? .dashboard
        self.selectedLayerName = PerformanceLayerPlanner.layerNames.first
        self.showsCalibration = defaults.object(forKey: AppPreferences.Keys.showCalibrationByDefault.rawValue) as? Bool ?? false
        self.showsGestureGuide = defaults.object(forKey: AppPreferences.Keys.showGestureGuideByDefault.rawValue) as? Bool ?? true
        self.showsMIDISummary = defaults.object(forKey: AppPreferences.Keys.showMIDISummaryByDefault.rawValue) as? Bool ?? false
        self.showsSignalPaths = defaults.object(forKey: AppPreferences.Keys.showSignalPathsByDefault.rawValue) as? Bool ?? false
        DebugEventFeed.shared.log("workspace", "Initialized at \(self.selectedSection?.title ?? "Dashboard")")
    }

    func navigate(to section: WorkspaceSection) {
        selectedSection = section
    }

    func selectFirstLayerIfNeeded() {
        if let selectedLayerName, PerformanceLayerPlanner.layerNames.contains(selectedLayerName) {
            return
        }
        selectedLayerName = PerformanceLayerPlanner.layerNames.first
    }
}
