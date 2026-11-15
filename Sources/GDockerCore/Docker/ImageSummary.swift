import Foundation

public struct ImageSummary: Identifiable, Sendable, Decodable, Equatable {
    public let id: String
    public let repoTags: [String]
    public let size: Int64
    public let created: Int64

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case repoTags = "RepoTags"
        case size = "Size"
        case created = "Created"
    }

    public init(id: String, repoTags: [String], size: Int64, created: Int64) {
        self.id = id
        self.repoTags = repoTags
        self.size = size
        self.created = created
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        repoTags = try c.decodeIfPresent([String].self, forKey: .repoTags) ?? []
        size = try c.decode(Int64.self, forKey: .size)
        created = try c.decode(Int64.self, forKey: .created)
    }
}
