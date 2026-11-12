import Foundation
import Testing
@testable import GDockerCore

private func summary(
    _ name: String, project: String? = nil, state: String = "running", status: String = "Up 1 hour"
) -> ContainerSummary {
    let labels = project.map { ["com.docker.compose.project": $0] } ?? [:]
    return ContainerSummary(
        id: name, names: ["/\(name)"], image: "img", state: state, status: status, labels: labels, ports: [])
}

@Test func decodeFixture() throws {
    let url = try #require(Bundle.module.url(forResource: "containers", withExtension: "json", subdirectory: "Fixtures"))
    let list = try JSONDecoder().decode([ContainerSummary].self, from: Data(contentsOf: url))
    #expect(list.count == 2)
    #expect(list[0].name == "myapp-api-1")
    #expect(list[0].composeProject == "myapp")
    #expect(list[0].ports.count == 2)
    #expect(list[0].ports[0].publicPort == 8080)
    #expect(list[0].ports[1].publicPort == nil)
    #expect(list[1].composeProject == nil)
    #expect(!list.contains { $0.name.hasPrefix("/") })
}

@Test(arguments: [
    ("running", "Up 2 hours", StatusKind.running),
    ("restarting", "Restarting (1) 3 seconds ago", .transitioning),
    ("paused", "Up 1 hour (Paused)", .transitioning),
    ("created", "Created", .transitioning),
    ("exited", "Exited (0) 3 days ago", .stopped),
    ("exited", "Exited (2) 1 week ago", .failed),
    ("dead", "Dead", .failed),
])
func statusKindMapping(state: String, status: String, expected: StatusKind) {
    #expect(summary("c", state: state, status: status).statusKind == expected)
}

@Test func grouping() {
    let groups = groupByCompose([
        summary("postgres", project: "myapp"),
        summary("nginx"),
        summary("web", project: "blog"),
        summary("api", project: "myapp"),
    ])
    #expect(groups.map(\.project) == ["blog", "myapp", nil])
    #expect(groups[1].containers.map(\.name) == ["api", "postgres"])
}
