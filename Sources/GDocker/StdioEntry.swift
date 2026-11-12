import Foundation
import GDockerCore
import GDockerMCP

enum StdioEntry {
    /// Runs the bridge on stdin/stdout until stdin closes, then exits. Reads the token but never creates one: a
    /// token only exists once the app has been opened at least once.
    static func run() -> Never {
        let store = KeychainSecretStore()
        let bridge = StdioBridge(
            endpoint: { McpEndpoint.read() },
            token: { try store.read(account: McpTokenProvider.defaultAccount) })
        Task {
            await bridge.run(input: .standardInput, output: .standardOutput)
            exit(0)
        }
        dispatchMain()
    }
}
