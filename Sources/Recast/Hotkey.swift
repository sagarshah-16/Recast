import Foundation
import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    static let `default` = Shortcut(
        keyCode: UInt32(kVK_ANSI_R),
        carbonModifiers: UInt32(cmdKey | shiftKey),
        display: "⌘⇧R"
    )

    static func from(event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty else { return nil }

        var carbon: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); symbols += "⌘" }

        let key = event.charactersIgnoringModifiers?.uppercased() ?? "?"
        return Shortcut(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: carbon,
            display: symbols + key
        )
    }
}

/// Registers system-wide hotkeys via Carbon: one main shortcut (popup flow)
/// plus one optional shortcut per rewrite style (silent quick-apply).
@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()
    private static let defaultsKey = "rewriteShortcut"

    @Published private(set) var shortcut: Shortcut

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .default
        }
        installEventHandler()
    }

    func updateMain(_ newShortcut: Shortcut) {
        shortcut = newShortcut
        if let data = try? JSONEncoder().encode(newShortcut) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        reload()
    }

    /// Re-registers every hotkey from current settings. Call after the main
    /// shortcut or any category shortcut changes.
    func reload() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        actions.removeAll()

        var id: UInt32 = 1
        register(shortcut, id: id) {
            RewritePipeline.shared.run()
        }
        for category in CategoriesStore.shared.categories {
            guard let categoryShortcut = category.shortcut else { continue }
            id += 1
            register(categoryShortcut, id: id) {
                RewritePipeline.shared.run(quick: category)
            }
        }
    }

    fileprivate func fire(id: UInt32) {
        actions[id]?()
    }

    private func register(_ shortcut: Shortcut, id: UInt32, action: @escaping () -> Void) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x43464D54), id: id) // "CFMT"
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            Log.write("hotkey: failed to register \(shortcut.display) (status \(status))")
            return
        }
        hotKeyRefs.append(ref)
        actions[id] = action
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let id = hotKeyID.id
                Task { @MainActor in
                    HotkeyManager.shared.fire(id: id)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }
}

// MARK: - Recorder control

import SwiftUI

/// Records a shortcut on the next keypress. Used for both the main shortcut
/// and per-style shortcuts (which can also be cleared).
struct ShortcutField: View {
    var shortcut: Shortcut?
    var allowsClear = false
    var onChange: (Shortcut?) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Press keys…" : (shortcut?.display ?? "None"))
                    .frame(minWidth: 70)
            }
            if allowsClear, shortcut != nil, !isRecording {
                Button {
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove shortcut")
            }
            if isRecording {
                Button("Cancel") { stopRecording() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            if let recorded = Shortcut.from(event: event) {
                onChange(recorded)
                stopRecording()
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
