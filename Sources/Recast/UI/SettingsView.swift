import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            CategoriesSettingsView()
                .tabItem { Label("Rewrite styles", systemImage: "wand.and.stars") }
        }
        .frame(width: 520, height: 420)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var auth = ClaudeAuth.shared
    @ObservedObject var hotkeys = HotkeyManager.shared
    @AppStorage("rewriteModel") private var model = "claude-haiku-4-5"

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Rewrite shortcut:") {
                    ShortcutField(shortcut: hotkeys.shortcut) { newShortcut in
                        if let newShortcut { HotkeyManager.shared.updateMain(newShortcut) }
                    }
                }
                Text("Press this anywhere to rewrite the text you're typing and see all suggestions. Each style can also get its own quick-apply shortcut in the Rewrite styles tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Model") {
                Picker("Claude model:", selection: $model) {
                    ForEach(RewriteService.models, id: \.id) { item in
                        Text(item.label).tag(item.id)
                    }
                }
                Text("Haiku is recommended — rewrites land in about a second.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Account") {
                if auth.isConnected {
                    LabeledContent("Claude") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Connected")
                        }
                    }
                    Button("Disconnect") { auth.signOut() }
                } else {
                    Button(auth.isSigningIn ? "Waiting for browser…" : "Connect with Claude…") {
                        Task { try? await auth.signIn() }
                    }
                    .disabled(auth.isSigningIn)
                }
            }

            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if TextCapture.hasAccessibilityPermission(promptIfNeeded: false) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Granted")
                        }
                    } else {
                        Button("Grant access…") {
                            _ = TextCapture.hasAccessibilityPermission(promptIfNeeded: true)
                        }
                    }
                }
                Text("Needed to read and replace the text you're editing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CategoriesSettingsView: View {
    @ObservedObject var store = CategoriesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Each style produces one suggestion. The first style is applied automatically when you press the main shortcut. A style with its own shortcut is applied instantly with no popup.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach($store.categories) { $category in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Name", text: $category.name)
                                .font(.headline)
                                .textFieldStyle(.plain)
                            Spacer()
                            ShortcutField(shortcut: category.shortcut, allowsClear: true) { newShortcut in
                                category.shortcut = newShortcut
                            }
                            .help("Quick-apply shortcut: rewrites with this style instantly, no popup.")
                        }
                        TextField("Prompt", text: $category.prompt, axis: .vertical)
                            .lineLimit(2...4)
                            .font(.callout)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onMove { from, to in
                    store.categories.move(fromOffsets: from, toOffset: to)
                }
                .onDelete { offsets in
                    store.categories.remove(atOffsets: offsets)
                }
            }

            HStack {
                Button {
                    store.categories.append(RewriteCategory(name: "New style", prompt: "Describe how to rewrite the text."))
                } label: {
                    Label("Add style", systemImage: "plus")
                }
                Spacer()
                Button("Reset to defaults") { store.resetToDefaults() }
            }
        }
        .padding()
    }
}
