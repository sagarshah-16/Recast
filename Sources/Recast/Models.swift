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

/// One suggested reply to a message the user selected.
struct ReplyOption: Identifiable, Equatable {
    var id: UUID = UUID()
    /// Short description of the approach, e.g. "Warm" or "Ask for details".
    var label: String
    var text: String
}

enum HistoryKind: String, Codable {
    case rewrite
    case reply
}

struct HistoryEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var kind: HistoryKind = .rewrite
    var date: Date
    var appName: String
    var original: String
    var variants: [RewriteVariant]
    var pickedCategory: String?
}

extension HistoryEntry {
    // Hand-rolled so entries written before `kind` existed still decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(HistoryKind.self, forKey: .kind) ?? .rewrite
        date = try container.decode(Date.self, forKey: .date)
        appName = try container.decode(String.self, forKey: .appName)
        original = try container.decode(String.self, forKey: .original)
        variants = try container.decode([RewriteVariant].self, forKey: .variants)
        pickedCategory = try container.decodeIfPresent(String.self, forKey: .pickedCategory)
    }
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
    case noSelection
    case apiError(String)
    case authError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to Claude. Open the menu and connect first."
        case .accessibilityDenied: return "Accessibility permission is required. Grant it in System Settings → Privacy & Security → Accessibility."
        case .secureInput: return "Can't rewrite text in a secure field (like a password box)."
        case .nothingCaptured: return "No text found in the focused field."
        case .noSelection: return "Select the message you want to reply to first, then press the shortcut."
        case .apiError(let m): return "Claude API error: \(m)"
        case .authError(let m): return "Sign-in failed: \(m)"
        }
    }
}
