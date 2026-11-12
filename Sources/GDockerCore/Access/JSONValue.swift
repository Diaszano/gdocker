/// Tool arguments as plain JSON, so `GDockerCore` stays independent of the MCP SDK's own value type.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}
