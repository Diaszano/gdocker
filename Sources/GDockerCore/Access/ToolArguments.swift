import Foundation

/// A problem the AI can fix itself: bad arguments, an unknown container, a Docker error. Becomes an `isError` result.
struct ToolFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// The arguments of one tool call, checked against the tool's `ToolSpec` before anything else happens.
struct ToolArguments {
    private let values: [String: JSONValue]
    let reason: String?

    init(spec: ToolSpec, raw: [String: JSONValue]) throws {
        for parameter in spec.parameters {
            guard let value = raw[parameter.name], value != .null else {
                if parameter.required { throw ToolFailure("Missing required argument '\(parameter.name)'.") }
                continue
            }
            try Self.check(value, against: parameter)
        }
        if let reason = raw["reason"], reason != .null {
            guard case .string(let text) = reason else {
                throw ToolFailure("Invalid argument 'reason': expected a string.")
            }
            self.reason = text
        } else {
            reason = nil
        }
        values = raw
    }

    private static func check(_ value: JSONValue, against parameter: ToolParameter) throws {
        let invalid = ToolFailure("Invalid argument '\(parameter.name)': expected \(parameter.kind.expectation).")
        switch (parameter.kind, value) {
        case (.string, .string(let text)):
            if parameter.required && text.isEmpty { throw ToolFailure("Argument '\(parameter.name)' must not be empty.") }
        case (.integer, .int): break
        case (.integer, .double(let number)) where number == number.rounded(): break
        case (.boolean, .bool): break
        case (.stringArray, .array(let items)):
            let strings = items.compactMap { item -> String? in
                if case .string(let text) = item { return text }
                return nil
            }
            guard strings.count == items.count else { throw invalid }
            if parameter.required && (strings.isEmpty || strings[0].isEmpty) {
                throw ToolFailure("Argument '\(parameter.name)' must not be empty.")
            }
        default: throw invalid
        }
    }

    func string(_ name: String) -> String? {
        if case .string(let text)? = values[name] { return text }
        return nil
    }

    func bool(_ name: String) -> Bool? {
        if case .bool(let flag)? = values[name] { return flag }
        return nil
    }

    func int(_ name: String) -> Int? {
        switch values[name] {
        case .int(let number)?: return number
        case .double(let number)?: return Int(number)
        default: return nil
        }
    }

    func strings(_ name: String) -> [String]? {
        guard case .array(let items)? = values[name] else { return nil }
        return items.compactMap { item in
            if case .string(let text) = item { return text }
            return nil
        }
    }

    /// One line for the activity log: `key=value` pairs, sorted, `reason` last.
    var summary: String {
        var parts = values.filter { $0.key != "reason" }.sorted { $0.key < $1.key }
            .map { "\($0.key)=\(Self.render($0.value))" }
        if let reason { parts.append("reason=\(reason)") }
        return parts.joined(separator: ", ")
    }

    static func render(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let flag): return String(flag)
        case .int(let number): return String(number)
        case .double(let number): return String(number)
        case .string(let text): return text
        case .array(let items): return items.map(render).joined(separator: " ")
        case .object: return "{…}"
        }
    }

    /// An argv shown as a command line; items with spaces are quoted so the user sees the real boundaries.
    static func displayCommand(_ argv: [String]) -> String {
        argv.map { $0.contains(where: \.isWhitespace) ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }
}

private extension ToolParameter.Kind {
    var expectation: String {
        switch self {
        case .string: "a string"
        case .integer: "an integer"
        case .boolean: "a boolean"
        case .stringArray: "an array of strings"
        }
    }
}
