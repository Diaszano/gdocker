import Foundation
import Testing
@testable import GDockerCore

final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]

    func read(account: String) throws -> String? { lock.withLock { items[account] } }
    func write(_ value: String, account: String) throws { lock.withLock { items[account] = value } }
    func delete(account: String) throws { lock.withLock { items[account] = nil } }
}

@Test func firstTokenIsCreatedAndStable() async throws {
    let store = InMemorySecretStore()
    let provider = McpTokenProvider(store: store)
    let token = try await provider.token()
    #expect(token.count == 64)
    #expect(token.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    #expect(try await provider.token() == token)
    #expect(try await McpTokenProvider(store: store).token() == token)
}

@Test func regenerateChangesAndPersists() async throws {
    let store = InMemorySecretStore()
    let provider = McpTokenProvider(store: store)
    let first = try await provider.token()
    let second = try await provider.regenerate()
    #expect(second != first && second.count == 64)
    #expect(try await provider.token() == second)
    #expect(try await McpTokenProvider(store: store).token() == second)
}

@Test func tokensMatchBehaviour() {
    #expect(tokensMatch("abc123", "abc123"))
    #expect(!tokensMatch("abc123", "abc124"))
    #expect(!tokensMatch("abc123", "abc12"))
    #expect(!tokensMatch("abc12", "abc123"))
    #expect(!tokensMatch("", "abc"))
    #expect(!tokensMatch("", ""))
}

@Test func keychainRoundTrip() throws {
    let store = KeychainSecretStore(service: "com.diaszano.gdocker.test.\(UUID().uuidString)")
    defer { try? store.delete(account: "t") }
    #expect(try store.read(account: "t") == nil)
    try store.write("v1", account: "t")
    #expect(try store.read(account: "t") == "v1")
    try store.write("v2", account: "t")
    #expect(try store.read(account: "t") == "v2")
    try store.delete(account: "t")
    #expect(try store.read(account: "t") == nil)
    try store.delete(account: "t")
}
