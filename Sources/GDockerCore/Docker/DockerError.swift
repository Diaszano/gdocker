import Foundation

public enum DockerError: Error, Equatable, LocalizedError {
    case socketNotFound
    case notFound(String)
    case conflict(String)
    case server(status: Int, message: String)
    case transport(String)

    /// `nil` for success. 304 (already started/stopped) counts as success.
    static func from(status: Int, body: Data) -> DockerError? {
        if (200..<300).contains(status) || status == 304 { return nil }
        let message = message(in: body)
        switch status {
        case 404: return .notFound(message)
        case 409: return .conflict(message)
        default: return .server(status: status, message: message)
        }
    }

    private static func message(in body: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let message = json["message"] as? String
        {
            return message
        }
        return String(decoding: body, as: UTF8.self)
    }

    public var errorDescription: String? {
        switch self {
        case .socketNotFound: return "Docker socket not found"
        case .notFound(let m), .conflict(let m), .transport(let m): return m
        case .server(_, let m): return m
        }
    }
}
