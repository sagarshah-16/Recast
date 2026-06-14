import Foundation
import AppKit
import CryptoKit

struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

/// Claude OAuth (PKCE) — the same browser sign-in flow Claude Code uses,
/// so rewrites run on your claude.ai subscription.
@MainActor
final class ClaudeAuth: ObservableObject {
    static let shared = ClaudeAuth()

    @Published var isConnected: Bool = false
    @Published var isSigningIn: Bool = false

    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let authorizeURL = "https://claude.ai/oauth/authorize"
    private static let tokenURL = "https://console.anthropic.com/v1/oauth/token"
    private static let callbackPort: UInt16 = 54545
    private static let redirectURI = "http://localhost:54545/callback"
    private static let scopes = "org:create_api_key user:profile user:inference"
    private static let keychainAccount = "claude-oauth-tokens"

    private var callbackServer: CallbackServer?

    private init() {
        isConnected = loadTokens() != nil
    }

    // MARK: - Sign in

    func signIn() async throws {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }

        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(length: 32)

        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        let server = CallbackServer()
        callbackServer = server

        NSWorkspace.shared.open(components.url!)

        let callback = try await server.waitForCallback(port: Self.callbackPort)
        callbackServer = nil
        guard callback.state == state else {
            throw RecastError.authError("State mismatch — please try again.")
        }

        var body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": callback.code,
            "state": callback.state,
            "client_id": Self.clientID,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
        ]
        let tokens = try await requestTokens(body: &body)
        saveTokens(tokens)
        isConnected = true
    }

    func cancelSignIn() {
        callbackServer?.stop()
        callbackServer = nil
    }

    func signOut() {
        Keychain.delete(account: Self.keychainAccount)
        isConnected = false
    }

    // MARK: - Token access

    /// Returns a valid access token, refreshing if it expires within 2 minutes.
    func validAccessToken() async throws -> String {
        guard var tokens = loadTokens() else { throw RecastError.notConnected }
        if tokens.expiresAt.timeIntervalSinceNow < 120 {
            var body: [String: Any] = [
                "grant_type": "refresh_token",
                "refresh_token": tokens.refreshToken,
                "client_id": Self.clientID,
            ]
            tokens = try await requestTokens(body: &body)
            saveTokens(tokens)
        }
        return tokens.accessToken
    }

    // MARK: - Private

    private func requestTokens(body: inout [String: Any]) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RecastError.authError("No response from token endpoint.")
        }
        guard http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            let detail = String(data: data, encoding: .utf8) ?? "unknown"
            throw RecastError.authError("Token exchange failed (\(http.statusCode)): \(detail)")
        }
        let refreshToken = (json["refresh_token"] as? String)
            ?? (body["refresh_token"] as? String)
            ?? ""
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    private var didReownKeychainItem = false

    private func loadTokens() -> OAuthTokens? {
        var stored = Keychain.load(account: Self.keychainAccount)
        if stored == nil,
           let legacy = Keychain.load(account: Self.keychainAccount, service: Keychain.legacyService) {
            // One-time migration from the pre-rename keychain entry.
            stored = legacy
            Keychain.save(legacy, account: Self.keychainAccount)
            Keychain.delete(account: Self.keychainAccount, service: Keychain.legacyService)
        }
        guard let data = stored else { return nil }
        guard let tokens = try? JSONDecoder().decode(OAuthTokens.self, from: data) else { return nil }
        // Re-save once per launch so the item's access list is owned by the
        // current binary — keeps macOS from prompting for the keychain
        // password after the app is rebuilt.
        if !didReownKeychainItem {
            didReownKeychainItem = true
            saveTokens(tokens)
        }
        return tokens
    }

    private func saveTokens(_ tokens: OAuthTokens) {
        if let data = try? JSONEncoder().encode(tokens) {
            Keychain.save(data, account: Self.keychainAccount)
        }
    }

    private static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64URLEncodedString().prefix(length).description
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
