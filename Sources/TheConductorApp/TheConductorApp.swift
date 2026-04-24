import SwiftUI

@main
struct TheConductorApp: App {
    @StateObject private var viewModel = SessionViewModel()
    @StateObject private var workspace = WorkspaceState()
    @StateObject private var preferences = AppPreferences()

    var body: some Scene {
        WindowGroup("The Conductor") {
            ContentView(
                viewModel: viewModel,
                workspace: workspace,
                preferences: preferences
            )
                .frame(minWidth: 1320, minHeight: 860)
        }
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()

            CommandMenu("Navigate") {
                Button("Dashboard") {
                    workspace.navigate(to: .dashboard)
                }
                .keyboardShortcut("1")

                Button("Sound") {
                    workspace.navigate(to: .sound)
                }
                .keyboardShortcut("2")

                Button("Layers") {
                    workspace.navigate(to: .layers)
                }
                .keyboardShortcut("3")

                Button("Tracking") {
                    workspace.navigate(to: .tracking)
                }
                .keyboardShortcut("4")

                Button("Library") {
                    workspace.navigate(to: .library)
                }
                .keyboardShortcut("5")

                Button("Scenes") {
                    workspace.navigate(to: .scenes)
                }
                .keyboardShortcut("6")

                Button("Loop") {
                    workspace.navigate(to: .loop)
                }
                .keyboardShortcut("7")
            }

            CommandMenu("Performance") {
                Button("Save Scene") {
                    viewModel.saveNewScenePreset()
                }
                .keyboardShortcut("S", modifiers: [.command, .shift])

                Button("Export MIDI") {
                    viewModel.exportLoopAsMIDI()
                }
                .keyboardShortcut("E", modifiers: [.command, .shift])
                .disabled(viewModel.isLoopAvailable == false)

                Button("Restart Loop") {
                    viewModel.restartLoopPlayback()
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
                .disabled(viewModel.isLoopAvailable == false)

                Divider()

                Button("Panic") {
                    if viewModel.routingMode == .logicBridge {
                        viewModel.silenceMIDINotes()
                    } else {
                        viewModel.silenceStandaloneNotes()
                    }
                }
                .keyboardShortcut(".", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView(preferences: preferences)
        }
        .windowToolbarStyle(.unifiedCompact)
    }
}
