import SwiftUI

@main
struct TheConductorApp: App {
    var body: some Scene {
        WindowGroup("The Conductor") {
            ContentView()
                .frame(minWidth: 1320, minHeight: 860)
        }
        .windowToolbarStyle(.unified)
    }
}
