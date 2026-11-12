import Testing
@testable import GDockerCore

@Test(arguments: [
    ("list_containers", ToolGroup.read, Permission.allow),
    ("inspect_container", .read, .allow),
    ("get_logs", .read, .allow),
    ("get_stats", .read, .allow),
    ("get_container_env", .sensitiveRead, .ask),
    ("start_container", .control, .allow),
    ("restart_container", .control, .allow),
    ("stop_container", .control, .ask),
    ("exec_in_container", .control, .ask),
    ("remove_container", .destructive, .ask),
])
func catalogHasSpecDefaults(name: String, group: ToolGroup, permission: Permission) throws {
    let spec = try #require(ToolCatalog.spec(named: name))
    #expect(spec.group == group)
    #expect(spec.defaultPermission == permission)
}

@Test func catalogHasExactlyThePlannedTools() {
    #expect(ToolCatalog.all.count == 10)
}

@Test func namesAreUniqueAndOnlyExecForbidsAlways() {
    let names = ToolCatalog.all.map(\.name)
    #expect(Set(names).count == names.count)
    #expect(ToolCatalog.all.filter { !$0.allowsAlways }.map(\.name) == ["exec_in_container"])
}

@Test func containerToolsRequireAContainerArgument() throws {
    for name in ["inspect_container", "get_logs", "get_stats", "get_container_env", "start_container",
                 "restart_container", "stop_container", "exec_in_container", "remove_container"] {
        let spec = try #require(ToolCatalog.spec(named: name))
        let container = try #require(spec.parameters.first { $0.name == "container" })
        #expect(container.required && container.kind == .string)
    }
    let exec = try #require(ToolCatalog.spec(named: "exec_in_container"))
    #expect(exec.parameters.contains { $0.name == "command" && $0.required && $0.kind == .stringArray })
}

@Test func reasonIsNotADeclaredParameter() {
    #expect(!ToolCatalog.all.contains { $0.parameters.contains { $0.name == "reason" } })
}
