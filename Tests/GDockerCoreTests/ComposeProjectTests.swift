import Testing
@testable import GDockerCore

@Suite("ComposeProjectTests")
struct ComposeProjectTests {

    private func project(_ name: String, status: ComposeStatus, services: [String] = ["web"]) -> ComposeProject {
        ComposeProject(
            name: name,
            workingDir: "/Users/dev/\(name)",
            configFiles: ["docker-compose.yml"],
            services: services.map { ComposeServiceSummary(name: $0) },
            status: status
        )
    }

    @Test func isActiveOnlyForRunningOrPartiallyRunning() {
        #expect(project("a", status: .running).isActive)
        #expect(project("b", status: .partiallyRunning).isActive)
        #expect(!project("c", status: .stopped).isActive)
        #expect(!project("d", status: .down).isActive)
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(project("shop", status: .down).matches(""))
        #expect(project("shop", status: .down).matches("   "))
    }

    @Test func matchesNameServiceAndDirectoryCaseInsensitively() {
        let shop = project("shop", status: .running, services: ["postgres", "api"])
        #expect(shop.matches("SHOP"))
        #expect(shop.matches("Postgres"))
        #expect(shop.matches("/users/dev"))
        #expect(!shop.matches("redis"))
    }
}
