import GDockerCore
import MCP

enum SchemaConversion {
    /// JSON Schema for a tool's arguments. Every tool also accepts an optional `reason`, shown to the user in the
    /// approval prompt.
    static func inputSchema(for spec: ToolSpec) -> Value {
        var properties: [String: Value] = [:]
        var required: [Value] = []
        for parameter in spec.parameters {
            properties[parameter.name] = schema(for: parameter)
            if parameter.required { required.append(.string(parameter.name)) }
        }
        properties["reason"] = .object([
            "type": .string("string"),
            "description": .string("Optional: why you are calling this tool. Shown to the user when approval is needed."),
        ])
        return .object(["type": .string("object"), "properties": .object(properties), "required": .array(required)])
    }

    private static func schema(for parameter: ToolParameter) -> Value {
        var fields: [String: Value] = ["description": .string(parameter.summary)]
        switch parameter.kind {
        case .string: fields["type"] = .string("string")
        case .integer: fields["type"] = .string("integer")
        case .boolean: fields["type"] = .string("boolean")
        case .stringArray:
            fields["type"] = .string("array")
            fields["items"] = .object(["type": .string("string")])
        }
        return .object(fields)
    }

    static func arguments(from values: [String: Value]?) -> [String: JSONValue] {
        (values ?? [:]).mapValues(json)
    }

    private static func json(_ value: Value) -> JSONValue {
        switch value {
        case .null: return .null
        case .bool(let flag): return .bool(flag)
        case .int(let number): return .int(number)
        case .double(let number): return .double(number)
        case .string(let text): return .string(text)
        case .data: return .null
        case .array(let items): return .array(items.map(json))
        case .object(let fields): return .object(fields.mapValues(json))
        }
    }
}
