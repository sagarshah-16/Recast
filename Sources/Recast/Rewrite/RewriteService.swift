import Foundation

/// Calls the Anthropic Messages API with the Claude OAuth token. One request
/// per style: the popup flow fires them in parallel so the first style can be
/// applied as soon as it lands, and quick-apply shortcuts only pay for one.
struct RewriteService {
    static let models: [(id: String, label: String)] = [
        ("claude-haiku-4-5", "Haiku 4.5 — fastest"),
        ("claude-sonnet-4-6", "Sonnet 4.6 — balanced"),
        ("claude-opus-4-8", "Opus 4.8 — most capable"),
    ]

    static func rewrite(text: String, category: RewriteCategory, model: String) async throws -> RewriteVariant {
        let accessToken = try await ClaudeAuth.shared.validAccessToken()

        let instruction = """
        Rewrite the text below. Instruction: \(category.prompt)

        Rules:
        - Keep the same language as the original text.
        - Preserve the meaning and any formatting (line breaks, lists, mentions, links).
        - Respond with ONLY the rewritten text — no explanations, no quotes, no preamble.

        Text to rewrite:
        <text>
        \(text)
        </text>
        """

        // Output is roughly the input length; cap generously but don't ask
        // for more than needed (keeps latency down).
        let maxTokens = max(1024, min(8000, text.count))

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": [
                ["type": "text", "text": "You are Claude Code, Anthropic's official CLI for Claude."],
            ],
            "messages": [
                ["role": "user", "content": instruction],
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
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !answer.isEmpty else {
            throw RecastError.apiError("Claude returned an empty rewrite.")
        }
        return RewriteVariant(category: category.name, text: answer)
    }
}
