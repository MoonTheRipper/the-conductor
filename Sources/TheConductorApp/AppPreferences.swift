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
        didSet { defaults.set(launchSection.rawValue, forKey: Keys.launchSection.rawValue) }
    }

    @Published var showGestureGuideByDefault: Bool {
        didSet { defaults.set(showGestureGuideByDefault, forKey: Keys.showGestureGuideByDefault.rawValue) }
    }

    @Published var showCalibrationByDefault: Bool {
        didSet { defaults.set(showCalibrationByDefault, forKey: Keys.showCalibrationByDefault.rawValue) }
    }

    @Published var showMIDISummaryByDefault: Bool {
        didSet { defaults.set(showMIDISummaryByDefault, forKey: Keys.showMIDISummaryByDefault.rawValue) }
    }

    @Published var showSignalPathsByDefault: Bool {
        didSet { defaults.set(showSignalPathsByDefault, forKey: Keys.showSignalPathsByDefault.rawValue) }
    }

    @Published var compactInspector: Bool {
        didSet { defaults.set(compactInspector, forKey: Keys.compactInspector.rawValue) }
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
    }
}
