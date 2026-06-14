import SwiftUI

struct MenuView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var auth = ClaudeAuth.shared
    @ObservedObject var pipeline = RewritePipeline.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if auth.isConnected {
            Toggle("Enabled", isOn: $appState.isEnabled)

            Button("Rewrite current text (\(HotkeyManager.shared.shortcut.display))") {
                RewritePipeline.shared.run()
            }
            .disabled(!appState.isEnabled)

            Divider()

            Button("History…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "history")
            }
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }

            Divider()

            Button("Disconnect from Claude") {
                auth.signOut()
            }
        } else {
            Button(auth.isSigningIn ? "Waiting for browser…" : "Connect with Claude…") {
                Task {
                    do { try await ClaudeAuth.shared.signIn() }
                    catch { RewritePipeline.shared.lastError = error.localizedDescription }
                }
            }
            .disabled(auth.isSigningIn)
            if auth.isSigningIn {
                Button("Cancel sign-in") { auth.cancelSignIn() }
            }
        }

        if let error = pipeline.lastError {
            Divider()
            Text(error)
        }

        Divider()
        Button("Quit Recast") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
