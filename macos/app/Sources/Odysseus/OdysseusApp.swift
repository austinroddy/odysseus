// OdysseusApp.swift — app entry point. Starts the embedded backend on
// launch and stops it cleanly on quit, via a plain AppKit delegate (SwiftUI
// has no direct "app is quitting" hook of its own).
import SwiftUI
import AppKit

@main
struct OdysseusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.backend)
                .task {
                    await appDelegate.backend.start()
                }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let backend = BackendManager()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        backend.stop()
    }
}
