import SwiftUI

@main
struct RealLocalTransApp: App {

    @StateObject private var settings    = AppSettings()
    @StateObject private var audioRouter = AudioRouterService()

    var body: some Scene {

        WindowGroup {
            ContentViewWrapper()
                .environmentObject(settings)
                .environmentObject(audioRouter)
                .frame(minWidth: 680, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }   // hide File > New
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(audioRouter)
                .frame(width: 540)
        }
    }
}
