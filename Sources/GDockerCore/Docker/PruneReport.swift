import Foundation

public struct PruneReport: Sendable, Codable, Equatable {
    public let containersDeleted: Int
    public let imagesDeleted: Int
    public let networksDeleted: Int
    public let volumesDeleted: Int
    public let spaceReclaimed: Int64

    public init(
        containersDeleted: Int,
        imagesDeleted: Int,
        networksDeleted: Int,
        volumesDeleted: Int,
        spaceReclaimed: Int64
    ) {
        self.containersDeleted = containersDeleted
        self.imagesDeleted = imagesDeleted
        self.networksDeleted = networksDeleted
        self.volumesDeleted = volumesDeleted
        self.spaceReclaimed = spaceReclaimed
    }
}
