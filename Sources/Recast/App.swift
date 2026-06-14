import SwiftUI
import AppKit

@main
struct RecastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var auth = ClaudeAuth.shared
    @ObservedObject var appState = AppState.shared
    @ObservedObject var pipeline = RewritePipeline.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
        } label: {
            if pipeline.isRunning {
                Image(systemName: "hourglass")
            } else {
                Image(systemName: auth.isConnected && appState.isEnabled ? "wand.and.stars" : "wand.and.stars.inverse")
            }
        }

        Settings {
            SettingsView()
        }

        Window("History", id: "history") {
            HistoryView()
        }
        .defaultSize(width: 640, height: 480)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The most recent app other than us — so a recast://rewrite URL can
    /// hand focus back before capturing.
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Prompt for Accessibility on first launch so the shortcut works.
        _ = TextCapture.hasAccessibilityPermission(promptIfNeeded: true)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self?.previousApp = app
        }
    }

    /// recast://signin | recast://rewrite — lets the sign-in and
    /// rewrite flows be triggered from scripts and the command line.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host {
            case "signin":
                Task { @MainActor in
                    do { try await ClaudeAuth.shared.signIn() }
                    catch { RewritePipeline.shared.lastError = error.localizedDescription }
                }
            case "rewrite":
                Task { @MainActor in
                    // Opening the URL focuses us; give focus back to the app
                    // the user was typing in before capturing.
                    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier,
                       let previous = self.previousApp {
                        previous.activate()
                        try? await Task.sleep(for: .milliseconds(400))
                    }
                    RewritePipeline.shared.run()
                }
            default:
                break
            }
        }
    }
}
