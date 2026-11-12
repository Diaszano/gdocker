public enum Permission: String, Codable, CaseIterable, Sendable { case allow, ask, deny }

public enum ToolGroup: String, CaseIterable, Sendable { case read, sensitiveRead, control, destructive }
