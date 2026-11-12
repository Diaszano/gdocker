import Foundation

public struct VolumeSummary: Identifiable, Sendable, Codable, Equatable {
    public var id: String { name }
    public let name: String
    public let driver: String
    public let scope: String
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name", altName = "name"
        case driver = "Driver", altDriver = "driver"
        case scope = "Scope", altScope = "scope"
        case createdAt = "CreatedAt", altCreatedAt = "createdAt"
    }

    public init(name: String, driver: String, scope: String, createdAt: String? = nil) {
        self.name = name
        self.driver = driver
        self.scope = scope
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
            ?? c.decode(String.self, forKey: .altName)
        driver = try c.decodeIfPresent(String.self, forKey: .driver)
            ?? c.decode(String.self, forKey: .altDriver)
        scope = try c.decodeIfPresent(String.self, forKey: .scope)
            ?? c.decode(String.self, forKey: .altScope)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            ?? c.decodeIfPresent(String.self, forKey: .altCreatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(driver, forKey: .driver)
        try c.encode(scope, forKey: .scope)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}
