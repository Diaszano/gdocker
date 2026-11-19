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
    ("list_images", .read, .allow),
    ("list_volumes", .read, .allow),
    ("list_networks", .read, .allow),
    ("remove_image", .destructive, .deny),
    ("remove_volume", .destructive, .deny),
    ("remove_network", .destructive, .deny),
    ("system_prune", .destructive, .deny),
    ("list_compose_projects", .read, .allow),
    ("compose_up", .control, .ask),
    ("compose_down", .control, .ask),
])
func catalogHasSpecDefaults(name: String, group: ToolGroup, permission: Permission) throws {
    let spec = try #require(ToolCatalog.spec(named: name))
    #expect(spec.group == group)
    #expect(spec.defaultPermission == permission)
}

@Test func catalogHasExactlyThePlannedTools() {
    #expect(ToolCatalog.all.count == 20)
}

@Test func namesAreUniqueAndOnlyExecAndComposeDownForbidAlways() {
    let names = ToolCatalog.all.map(\.name)
    #expect(Set(names).count == names.count)
    #expect(Set(ToolCatalog.all.filter { !$0.allowsAlways }.map(\.name)) == Set(["exec_in_container", "compose_down"]))
}

@Test func containerToolsRequireAContainerArgument() throws {
    for name in [
        "inspect_container", "get_logs", "get_stats", "get_container_env", "start_container",
        "restart_container", "stop_container", "exec_in_container", "remove_container",
    ] {
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

@Test func resourceToolsDeclareExpectedParameters() throws {
    let removeImg = try #require(ToolCatalog.spec(named: "remove_image"))
    let imgParam = try #require(removeImg.parameters.first { $0.name == "image" })
    #expect(imgParam.required && imgParam.kind == .string)
    let imgForce = try #require(removeImg.parameters.first { $0.name == "force" })
    #expect(!imgForce.required && imgForce.kind == .boolean)

    let removeVol = try #require(ToolCatalog.spec(named: "remove_volume"))
    let volParam = try #require(removeVol.parameters.first { $0.name == "volume" })
    #expect(volParam.required && volParam.kind == .string)
    let volForce = try #require(removeVol.parameters.first { $0.name == "force" })
    #expect(!volForce.required && volForce.kind == .boolean)

    let removeNet = try #require(ToolCatalog.spec(named: "remove_network"))
    let netParam = try #require(removeNet.parameters.first { $0.name == "network" })
    #expect(netParam.required && netParam.kind == .string)

    let prune = try #require(ToolCatalog.spec(named: "system_prune"))
    let pruneAll = try #require(prune.parameters.first { $0.name == "all" })
    #expect(!pruneAll.required && pruneAll.kind == .boolean)
    let pruneVols = try #require(prune.parameters.first { $0.name == "volumes" })
    #expect(!pruneVols.required && pruneVols.kind == .boolean)

    for listTool in ["list_images", "list_volumes", "list_networks"] {
        let spec = try #require(ToolCatalog.spec(named: listTool))
        #expect(spec.parameters.isEmpty)
    }
}

@Test func composeToolsDeclareExpectedParameters() throws {
    let listCompose = try #require(ToolCatalog.spec(named: "list_compose_projects"))
    #expect(listCompose.parameters.isEmpty)

    let composeUp = try #require(ToolCatalog.spec(named: "compose_up"))
    let projectParam = try #require(composeUp.parameters.first { $0.name == "project" })
    #expect(projectParam.required && projectParam.kind == .string)

    let composeDown = try #require(ToolCatalog.spec(named: "compose_down"))
    let downProjectParam = try #require(composeDown.parameters.first { $0.name == "project" })
    #expect(downProjectParam.required && downProjectParam.kind == .string)
    let removeVolsParam = try #require(composeDown.parameters.first { $0.name == "remove_volumes" })
    #expect(!removeVolsParam.required && removeVolsParam.kind == .boolean)
}
