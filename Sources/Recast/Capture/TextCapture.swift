import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Captures the text the user is editing and writes the rewrite back.
///
/// Strategy:
///  1. Accessibility API fast path — read the focused element's selected text
///     (or whole value), and write back in place with no clipboard flicker.
///  2. Clipboard fallback for apps with poor AX support — synthesizes
///     ⌘C / ⌘A+⌘C to read and ⌘V to write, preserving the user's clipboard.
@MainActor
final class TextCapture {

    enum ReplaceTarget {
        case ax(element: AXUIElement, mode: CaptureMode)
        case clipboard(mode: CaptureMode)
    }

    private(set) var lastTarget: ReplaceTarget?
    private(set) var lastAppliedText: String?

    static func hasAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Capture

    func capture() async throws -> CapturedText {
        guard !IsSecureEventInputEnabled() else { throw RecastError.secureInput }
        guard Self.hasAccessibilityPermission(promptIfNeeded: true) else {
            Log.write("capture: accessibility NOT granted")
            throw RecastError.accessibilityDenied
        }

        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        Log.write("capture: frontmost app = \(appName)")

        if let result = captureViaAX(appName: appName) {
            return result
        }
        Log.write("capture: AX path unavailable, trying clipboard fallback")
        return try await captureViaClipboard(appName: appName)
    }

    private func captureViaAX(appName: String) -> CapturedText? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else { return nil }
        let element = focusedRef as! AXUIElement

        var selectedRef: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef)
        let selected = (selectedStatus == .success) ? (selectedRef as? String ?? "") : ""

        if !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var settable = DarwinBoolean(false)
            AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
            guard settable.boolValue else { return nil }
            lastTarget = .ax(element: element, mode: .selection)
            return CapturedText(text: selected, mode: .selection, usedAX: true, appName: appName)
        }

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        guard settable.boolValue else { return nil }

        lastTarget = .ax(element: element, mode: .wholeField)
        return CapturedText(text: value, mode: .wholeField, usedAX: true, appName: appName)
    }

    private func captureViaClipboard(appName: String) async throws -> CapturedText {
        let pasteboard = NSPasteboard.general
        let savedItems = Self.snapshotPasteboard(pasteboard)
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                Self.restorePasteboard(pasteboard, items: savedItems)
            }
        }

        // Try copying the current selection first.
        pasteboard.clearContents()
        let changeCount = pasteboard.changeCount
        KeySynth.copy()
        try await Task.sleep(for: .milliseconds(180))

        if pasteboard.changeCount != changeCount,
           let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastTarget = .clipboard(mode: .selection)
            return CapturedText(text: text, mode: .selection, usedAX: false, appName: appName)
        }

        // No selection — select the whole field and copy.
        KeySynth.selectAll()
        try await Task.sleep(for: .milliseconds(120))
        pasteboard.clearContents()
        let changeCount2 = pasteboard.changeCount
        KeySynth.copy()
        try await Task.sleep(for: .milliseconds(180))

        guard pasteboard.changeCount != changeCount2,
              let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecastError.nothingCaptured
        }
        lastTarget = .clipboard(mode: .wholeField)
        return CapturedText(text: text, mode: .wholeField, usedAX: false, appName: appName)
    }

    // MARK: - Replace

    /// Applies `text` to the captured target. Safe to call repeatedly —
    /// swapping between variants replaces the previously applied text.
    func apply(_ text: String) async throws {
        guard let target = lastTarget else { return }
        switch target {
        case .ax(let element, let mode):
            switch mode {
            case .selection:
                AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            case .wholeField:
                AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
            }
        case .clipboard(let mode):
            // If we already pasted a variant, undo it first so swaps replace
            // rather than append.
            if lastAppliedText != nil {
                KeySynth.undo()
                try await Task.sleep(for: .milliseconds(120))
            } else if mode == .wholeField {
                KeySynth.selectAll()
                try await Task.sleep(for: .milliseconds(100))
            }
            try await pasteText(text)
        }
        lastAppliedText = text
    }

    /// Restores the user's original text (Esc / dismiss).
    func revert(to original: String) async throws {
        guard let target = lastTarget, lastAppliedText != nil else { return }
        switch target {
        case .ax(let element, let mode):
            switch mode {
            case .selection:
                AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, original as CFTypeRef)
            case .wholeField:
                AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, original as CFTypeRef)
            }
        case .clipboard:
            KeySynth.undo()
            try await Task.sleep(for: .milliseconds(120))
        }
        lastAppliedText = nil
    }

    func finish() {
        lastTarget = nil
        lastAppliedText = nil
    }

    private func pasteText(_ text: String) async throws {
        let pasteboard = NSPasteboard.general
        let savedItems = Self.snapshotPasteboard(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        KeySynth.paste()
        try await Task.sleep(for: .milliseconds(300))
        Self.restorePasteboard(pasteboard, items: savedItems)
    }

    // MARK: - Pasteboard preservation

    private static func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy[type] = data
                }
            }
            return copy
        }
    }

    private static func restorePasteboard(_ pasteboard: NSPasteboard, items: [[NSPasteboard.PasteboardType: Data]]) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        let restored = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
