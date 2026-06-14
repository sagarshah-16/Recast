import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// Synthesizes keyboard shortcuts (⌘A, ⌘C, ⌘V, ⌘Z) for the clipboard-based
/// capture/replace fallback path.
enum KeySynth {
    static func commandKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }

    static func selectAll() { commandKey(CGKeyCode(kVK_ANSI_A)) }
    static func copy() { commandKey(CGKeyCode(kVK_ANSI_C)) }
    static func paste() { commandKey(CGKeyCode(kVK_ANSI_V)) }
    static func undo() { commandKey(CGKeyCode(kVK_ANSI_Z)) }
}
