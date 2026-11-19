public struct ToolParameter: Sendable, Equatable {
    public enum Kind: Sendable { case string, integer, boolean, stringArray }

    public let name: String
    public let kind: Kind
    public let required: Bool
    public let summary: String

    public init(name: String, kind: Kind, required: Bool, summary: String) {
        self.name = name
        self.kind = kind
        self.required = required
        self.summary = summary
    }
}

/// One MCP tool. `reason` is not listed in `parameters`: the layers above add it to every tool.
public struct ToolSpec: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    /// English label for the UI; also the key in the string catalog.
    public let title: String
    public let group: ToolGroup
    public let defaultPermission: Permission
    /// Description the AI reads.
    public let summary: String
    public let parameters: [ToolParameter]
    /// Whether the approval prompt may offer "always allow".
    public let allowsAlways: Bool

    public init(
        name: String, title: String, group: ToolGroup, defaultPermission: Permission, summary: String,
        parameters: [ToolParameter], allowsAlways: Bool = true
    ) {
        self.name = name
        self.title = title
        self.group = group
        self.defaultPermission = defaultPermission
        self.summary = summary
        self.parameters = parameters
        self.allowsAlways = allowsAlways
    }
}
