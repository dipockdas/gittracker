import SwiftUI

@main
struct GitTrackerApp: App {
    @StateObject private var viewModel = WorkflowViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 420, minHeight: 220)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    viewModel.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
