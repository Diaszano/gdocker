import Foundation
import Security

/// The bearer token every MCP request must carry. Created on first use and kept in the secret store.
public actor McpTokenProvider {
    /// The keychain account of the token; the `--stdio` bridge reads it without ever creating one.
    public static let defaultAccount = "mcp-token"

    private let store: any SecretStore
    private let account: String

    public init(store: any SecretStore, account: String = McpTokenProvider.defaultAccount) {
        self.store = store
        self.account = account
    }

    public func token() throws -> String {
        if let existing = try store.read(account: account), !existing.isEmpty { return existing }
        return try regenerate()
    }

    /// Replaces the token. Whatever used the old one stops working at its next request.
    public func regenerate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try store.write(token, account: account)
        return token
    }
}

/// Compares in time that does not depend on where the strings differ. An empty string never matches.
public func tokensMatch(_ a: String, _ b: String) -> Bool {
    let left = Array(a.utf8)
    let right = Array(b.utf8)
    guard !left.isEmpty, !right.isEmpty else { return false }
    var difference = left.count ^ right.count
    for index in 0..<max(left.count, right.count) {
        let l = index < left.count ? left[index] : 0
        let r = index < right.count ? right[index] : 0
        difference |= Int(l ^ r)
    }
    return difference == 0
}
