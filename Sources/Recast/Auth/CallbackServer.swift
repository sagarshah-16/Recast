import Foundation
import Network

/// Minimal one-shot HTTP server that waits for the OAuth redirect on localhost
/// and hands back the `code` and `state` query parameters.
final class CallbackServer {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<(code: String, state: String), Error>?

    func waitForCallback(port: UInt16) async throws -> (code: String, state: String) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            do {
                let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
                self.listener = listener
                listener.newConnectionHandler = { [weak self] connection in
                    connection.start(queue: .main)
                    self?.receive(on: connection)
                }
                listener.start(queue: .main)
            } catch {
                continuation.resume(throwing: error)
                self.continuation = nil
            }
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
            guard let firstLine = request.split(separator: "\r\n").first,
                  firstLine.hasPrefix("GET ") else {
                self.respond(connection, body: "Bad request")
                return
            }
            let path = firstLine.split(separator: " ")[1]
            guard let components = URLComponents(string: String(path)),
                  components.path == "/callback",
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                  let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
                self.respond(connection, body: "Missing authorization code. You can close this tab.")
                return
            }
            self.respond(connection, body: "Recast is connected to Claude. You can close this tab and return to the app.")
            self.continuation?.resume(returning: (code, state))
            self.continuation = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.stop()
            }
        }
    }

    private func respond(_ connection: NWConnection, body: String) {
        let html = "<html><body style=\"font-family:-apple-system;padding:40px\"><h2>\(body)</h2></body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    func stop() {
        listener?.cancel()
        listener = nil
        continuation?.resume(throwing: RecastError.authError("Sign-in was cancelled."))
        continuation = nil
    }
}
