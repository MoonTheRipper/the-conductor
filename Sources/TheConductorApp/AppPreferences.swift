import Foundation

final class AppPreferences: ObservableObject {
    enum Keys: String {
        case launchSection = "TheConductor.preferences.launchSection"
        case showGestureGuideByDefault = "TheConductor.preferences.showGestureGuideByDefault"
        case showCalibrationByDefault = "TheConductor.preferences.showCalibrationByDefault"
        case showMIDISummaryByDefault = "TheConductor.preferences.showMIDISummaryByDefault"
        case showSignalPathsByDefault = "TheConductor.preferences.showSignalPathsByDefault"
        case compactInspector = "TheConductor.preferences.compactInspector"
    }

    @Published var launchSection: WorkspaceSection {
        didSet {
            defaults.set(launchSection.rawValue, forKey: Keys.launchSection.rawValue)
            guard launchSection != oldValue else { return }
            DebugEventFeed.shared.log("preferences", "Launch section -> \(launchSection.title)")
        }
    }

    @Published var showGestureGuideByDefault: Bool {
        didSet {
            defaults.set(showGestureGuideByDefault, forKey: Keys.showGestureGuideByDefault.rawValue)
            guard showGestureGuideByDefault != oldValue else { return }
            DebugEventFeed.shared.log("preferences", "Gesture guide default -> \(showGestureGuideByDefault)")
        }
    }

    @Published var showCalibrationByDefault: Bool {
        didSet {
            defaults.set(showCalibrationByDefault, forKey: Keys.showCalibrationByDefault.rawValue)
            guard showCalibrationByDefault != oldValue else { return }
            DebugEventFeed.shared.log("preferences", "Calibration default -> \(showCalibrationByDefault)")
        }
    }

    @Published var showMIDISummaryByDefault: Bool {
        didSet {
            defaults.set(showMIDISummaryByDefault, forKey: Keys.showMIDISummaryByDefault.rawValue)
            guard showMIDISummaryByDefault != oldValue else { return }
            DebugEventFeed.shared.log("preferences", "MIDI summary default -> \(showMIDISummaryByDefault)")
        }
    }

    @Published var showSignalPathsByDefault: Bool {
        didSet {
            defaults.set(showSignalPathsByDefault, forKey: Keys.showSignalPathsByDefault.rawValue)
            guard showSignalPathsByDefault != oldValue else { return }
            DebugEventFeed.shared.log("preferences", "Signal paths default -> \(showSignalPathsByDefault)")
        }
    }

    @Published var compactInspector: Bool {
        didSet {
            defaults.set(compactInspector, forKey: Keys.compactInspector.rawValue)
            guard compactInspector != oldValue else { return }
            DebugEventFeed.shared.log("preferences", "Compact inspector -> \(compactInspector)")
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.launchSection = defaults.string(forKey: Keys.launchSection.rawValue).flatMap(WorkspaceSection.init(rawValue:)) ?? .dashboard
        self.showGestureGuideByDefault = defaults.object(forKey: Keys.showGestureGuideByDefault.rawValue) as? Bool ?? true
        self.showCalibrationByDefault = defaults.object(forKey: Keys.showCalibrationByDefault.rawValue) as? Bool ?? false
        self.showMIDISummaryByDefault = defaults.object(forKey: Keys.showMIDISummaryByDefault.rawValue) as? Bool ?? false
        self.showSignalPathsByDefault = defaults.object(forKey: Keys.showSignalPathsByDefault.rawValue) as? Bool ?? false
        self.compactInspector = defaults.object(forKey: Keys.compactInspector.rawValue) as? Bool ?? false
        DebugEventFeed.shared.log("preferences", "Loaded app preferences")
    }
}
