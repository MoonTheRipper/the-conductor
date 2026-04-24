import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                generalPane
            }

            Tab("Workspace", systemImage: "sidebar.left") {
                workspacePane
            }
        }
        .padding(20)
        .frame(width: 520, height: 320)
    }

    private var generalPane: some View {
        Form {
            Section("Launch") {
                Picker("Open To", selection: $preferences.launchSection) {
                    ForEach(WorkspaceSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }

                Toggle("Use compact inspector width", isOn: $preferences.compactInspector)
            }

            Section("Defaults") {
                Text("These preferences shape the starting workspace without cluttering the main window.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var workspacePane: some View {
        Form {
            Section("Disclosures") {
                Toggle("Show gesture vocabulary by default", isOn: $preferences.showGestureGuideByDefault)
                Toggle("Show calibration controls by default", isOn: $preferences.showCalibrationByDefault)
                Toggle("Show MIDI channel summary by default", isOn: $preferences.showMIDISummaryByDefault)
                Toggle("Show standalone signal paths by default", isOn: $preferences.showSignalPathsByDefault)
            }

            Section("Why") {
                Text("Apple’s settings guidance favors a dedicated preferences window for app-wide defaults, keeping session controls in the main workspace focused on the current task.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
