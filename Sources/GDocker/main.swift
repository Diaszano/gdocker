import Foundation

// `--stdio` makes this executable a stdio bridge to the running app, for MCP clients that cannot use HTTP.
// It must be decided before SwiftUI starts: the bridge never touches AppKit, so no Dock icon or window appears.
if CommandLine.arguments.contains("--stdio") {
    StdioEntry.run()
} else {
    GDockerApp.main()
}
