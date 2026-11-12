import Foundation

public struct ImageSummary: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let repoTags: [String]
    public let size: Int64
    public let created: Int64

    enum CodingKeys: String, CodingKey {
        case id = "Id", altId = "id"
        case repoTags = "RepoTags", altRepoTags = "repoTags"
        case size = "Size", altSize = "size"
        case created = "Created", altCreated = "created"
    }

    public init(id: String, repoTags: [String], size: Int64, created: Int64) {
        self.id = id
        self.repoTags = repoTags
        self.size = size
        self.created = created
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
            ?? c.decode(String.self, forKey: .altId)
        repoTags = try c.decodeIfPresent([String].self, forKey: .repoTags)
            ?? c.decodeIfPresent([String].self, forKey: .altRepoTags)
            ?? []
        size = try c.decodeIfPresent(Int64.self, forKey: .size)
            ?? c.decode(Int64.self, forKey: .altSize)
        created = try c.decodeIfPresent(Int64.self, forKey: .created)
            ?? c.decode(Int64.self, forKey: .altCreated)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(repoTags, forKey: .repoTags)
        try c.encode(size, forKey: .size)
        try c.encode(created, forKey: .created)
    }
}
