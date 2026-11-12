import Foundation

/// Lets clients that only speak stdio (Claude Desktop, for example) use the running app: each JSON-RPC line on
/// `input` is POSTed to the app's MCP endpoint with the bearer token, and every reply becomes one line on `output`.
///
/// shortcut: only replies to POSTs are relayed. Server-initiated messages (the standalone GET stream) are not,
/// because gdocker's server never sends any; add a GET stream here if it starts to.
public struct StdioBridge: Sendable {
    private let endpoint: @Sendable () -> URL?
    private let token: @Sendable () throws -> String?

    public init(endpoint: @escaping @Sendable () -> URL?, token: @escaping @Sendable () throws -> String?) {
        self.endpoint = endpoint
        self.token = token
    }

    private actor LineWriter {
        private let handle: FileHandle
        init(_ handle: FileHandle) { self.handle = handle }
        func write(_ line: String) { try? handle.write(contentsOf: Data((line + "\n").utf8)) }
    }

    private actor SessionState {
        private(set) var id: String?
        func set(_ id: String) { self.id = id }
    }

    /// Returns when `input` reaches end of file, after every request in flight has been answered.
    public func run(input: FileHandle, output: FileHandle) async {
        let writer = LineWriter(output)
        let session = SessionState()
        let configuration = URLSessionConfiguration.ephemeral
        // An approval prompt can keep a tool call open for minutes, so the default 60 s idle timeout is far too short.
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 3600
        let urlSession = URLSession(configuration: configuration)
        defer { urlSession.invalidateAndCancel() }

        await withTaskGroup(of: Void.self) { group in
            do {
                for try await line in input.bytes.lines {
                    let text = line.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { continue }
                    if Self.fields(of: text).method == "initialize" {
                        // Everything after `initialize` needs the session id it returns, so wait for it.
                        await forward(text, writer, session, urlSession)
                    } else {
                        group.addTask { await self.forward(text, writer, session, urlSession) }
                    }
                }
            } catch {
                // Reading stdin failed: treat it like end of file.
            }
            await group.waitForAll()
        }
        await endSession(session, urlSession)
    }

    // MARK: - Forwarding

    private func forward(_ text: String, _ writer: LineWriter, _ session: SessionState, _ urlSession: URLSession) async {
        let id = Self.fields(of: text).id
        func fail(_ code: Int, _ message: String) async {
            // A notification has no id, so there is nobody to answer.
            if let id { await writer.write(Self.errorLine(id: id, code: code, message: message)) }
        }
        guard let url = endpoint() else {
            await fail(-32000, "gdocker is not running: open the GDocker app")
            return
        }
        guard let bearer = (try? token()) ?? nil else {
            await fail(-32001, "Authentication failed: copy the config again from GDocker")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(text.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let sessionID = await session.id { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                await fail(-32000, "gdocker is not running: open the GDocker app")
                return
            }
            if let sessionID = http.value(forHTTPHeaderField: "Mcp-Session-Id") { await session.set(sessionID) }
            switch http.statusCode {
            case 200..<300:
                let type = http.value(forHTTPHeaderField: "Content-Type") ?? ""
                for line in Self.lines(in: data, isEventStream: type.contains("text/event-stream")) {
                    await writer.write(line)
                }
            case 401:
                await fail(-32001, "Authentication failed: copy the config again from GDocker")
            default:
                await fail(-32002, "GDocker answered with HTTP \(http.statusCode)")
            }
        } catch {
            await fail(-32000, "gdocker is not running: open the GDocker app")
        }
    }

    /// Tells the server this client is gone, so the app's client count goes back down.
    private func endSession(_ session: SessionState, _ urlSession: URLSession) async {
        guard let sessionID = await session.id, let url = endpoint(), let bearer = (try? token()) ?? nil else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 3
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        _ = try? await urlSession.data(for: request)
    }

    // MARK: - JSON-RPC helpers

    private static func fields(of text: String) -> (method: String?, id: Any?) {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
            return (nil, nil)
        }
        let id = object["id"]
        return (object["method"] as? String, id is NSNull ? nil : id)
    }

    private static func errorLine(id: Any, code: Int, message: String) -> String {
        let object: [String: Any] = ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// One compact line per JSON message: the body itself, or each `data:` event of an SSE body.
    private static func lines(in data: Data, isEventStream: Bool) -> [String] {
        let text = String(decoding: data, as: UTF8.self)
        let payloads = isEventStream
            ? text.split(separator: "\n").compactMap { line -> String? in
                line.hasPrefix("data:") ? String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces) : nil
            }
            : [text.trimmingCharacters(in: .whitespacesAndNewlines)]
        return payloads.filter { !$0.isEmpty }.map { payload in
            guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)),
                  let compact = try? JSONSerialization.data(withJSONObject: object)
            else { return payload.replacingOccurrences(of: "\n", with: " ") }
            return String(decoding: compact, as: UTF8.self)
        }
    }
}
