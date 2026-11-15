import Foundation

public struct VolumeSummary: Identifiable, Sendable, Decodable, Equatable {
    public var id: String { name }
    public let name: String
    public let driver: String
    public let scope: String
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case driver = "Driver"
        case scope = "Scope"
        case createdAt = "CreatedAt"
    }

    public init(name: String, driver: String, scope: String, createdAt: String? = nil) {
        self.name = name
        self.driver = driver
        self.scope = scope
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        driver = try c.decode(String.self, forKey: .driver)
        scope = try c.decode(String.self, forKey: .scope)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}
