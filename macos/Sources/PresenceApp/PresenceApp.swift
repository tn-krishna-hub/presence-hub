import SwiftUI
import PresenceCore

@main
struct PresenceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = PresenceModel()

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(model)
        } label: {
            Image(systemName: model.state == .away ? "person.fill.viewfinder" : "dot.radiowaves.left.and.right")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}