import Foundation

/// Asks Claude for three different replies to a message the user selected.
/// One request (not three): the options only feel useful if they're written
/// against each other, so the model sees all three at once.
struct ReplyService {
    static let optionCount = 3

    static func suggestReplies(to message: String, tone: String, model: String) async throws -> [ReplyOption] {
        let accessToken = try await ClaudeAuth.shared.validAccessToken()

        let toneLine = tone.trimmingCharacters(in: .whitespacesAndNewlines)
        let guidance = toneLine.isEmpty ? "" : "\n- How the user likes to sound: \(toneLine)"

        let instruction = """
        The user received the message below and isn't sure how to respond. Write \(optionCount) different replies they could send.

        Rules:
        - Make the \(optionCount) replies genuinely different in approach — for example one warm and agreeable, one short and direct, one that asks a question or pushes back politely. Pick whichever approaches actually fit this message.
        - Write in the first person, as the user, ready to send as-is.
        - Match the language, tone, and formality of the message. Reply in the same language it was written in.
        - Keep each reply roughly as long as the message unless it clearly needs more.
        - No placeholders like [name] or [date] — if a detail is unknown, write around it.
        - Give each reply a label of 1–3 words describing its approach.\(guidance)

        Respond with ONLY a JSON array, no markdown fences and no commentary:
        [{"label": "...", "text": "..."}]

        Message to reply to:
        <message>
        \(message)
        </message>
        """

        // Three replies, each potentially longer than the message itself.
        let maxTokens = max(1500, min(8000, message.count * 4))

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": [
                ["type": "text", "text": "You are Claude Code, Anthropic's official CLI for Claude."],
            ],
            "messages": [
                ["role": "user", "content": instruction],
                // Prefill the opening bracket so the model can't preamble.
                ["role": "assistant", "content": "["],
            ],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RecastError.apiError("No response.")
        }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "unknown error"
            throw RecastError.apiError("HTTP \(http.statusCode): \(detail)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw RecastError.apiError("Unexpected response shape.")
        }
        let answer = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()

        // The prefill isn't echoed back, but re-add it only if the model
        // didn't open the array itself.
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = parseOptions(trimmed.hasPrefix("[") ? trimmed : "[" + trimmed)
        guard !options.isEmpty else {
            throw RecastError.apiError("Claude didn't return any replies.")
        }
        return Array(options.prefix(optionCount))
    }

    /// Pulls the JSON array out of the response — tolerant of stray prose or
    /// a ```json fence around it.
    static func parseOptions(_ raw: String) -> [ReplyOption] {
        guard let start = raw.firstIndex(of: "["),
              let end = raw.lastIndex(of: "]"), start < end else { return [] }
        let slice = String(raw[start...end])

        guard let data = slice.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        return array.enumerated().compactMap { index, item in
            guard let text = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            let label = (item["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ReplyOption(label: label.isEmpty ? "Option \(index + 1)" : label, text: text)
        }
    }
}
