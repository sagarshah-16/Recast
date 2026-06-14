import Foundation

struct RewriteCategory: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var prompt: String
    /// Optional global shortcut that applies this style directly, with no popup.
    var shortcut: Shortcut?

    static let defaults: [RewriteCategory] = [
        RewriteCategory(
            name: "Fixed",
            prompt: "Correct all grammar, spelling, and punctuation mistakes. Keep the wording, tone, and meaning as close to the original as possible."
        ),
        RewriteCategory(
            name: "Concise",
            prompt: "Rewrite the text to be shorter and clearer while keeping the full meaning. Remove filler words and redundancy."
        ),
        RewriteCategory(
            name: "Professional",
            prompt: "Rewrite the text in a polished, professional tone suitable for workplace communication."
        ),
    ]
}

struct RewriteVariant: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var category: String
    var text: String

    enum CodingKeys: String, CodingKey {
        case category, text
    }
}

struct HistoryEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var appName: String
    var original: String
    var variants: [RewriteVariant]
    var pickedCategory: String?
}

enum CaptureMode {
    case selection
    case wholeField
}

struct CapturedText {
    var text: String
    var mode: CaptureMode
    var usedAX: Bool
    var appName: String
}

enum RecastError: LocalizedError {
    case notConnected
    case accessibilityDenied
    case secureInput
    case nothingCaptured
    case apiError(String)
    case authError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to Claude. Open the menu and connect first."
        case .accessibilityDenied: return "Accessibility permission is required. Grant it in System Settings → Privacy & Security → Accessibility."
        case .secureInput: return "Can't rewrite text in a secure field (like a password box)."
        case .nothingCaptured: return "No text found in the focused field."
        case .apiError(let m): return "Claude API error: \(m)"
        case .authError(let m): return "Sign-in failed: \(m)"
        }
    }
}
