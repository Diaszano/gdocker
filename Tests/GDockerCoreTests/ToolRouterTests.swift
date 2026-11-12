import Foundation
import Testing
@testable import GDockerCore

private struct Harness {
    let router: ToolRouter
    let docker: FakeDocker
    let compose: FakeComposeRunner?
    let registry: ComposeProjectRegistry?
    let permissions: PermissionStore
    let activity: ActivityLog
    let scripted: ScriptedPrompter

    init(
        decisions: [ApprovalDecision] = [],
        prompter: (any ApprovalPrompter)? = nil,
        dockerAvailable: Bool = true,
        composeAvailable: Bool = true,
        compose: FakeComposeRunner? = nil,
        registry: ComposeProjectRegistry? = nil,
        timeout: Duration = .seconds(5)
    ) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gdocker-\(UUID().uuidString)")
        let fake = FakeDocker()
        let fakeCompose = compose ?? FakeComposeRunner()
        let fakeRegistry = registry ?? ComposeProjectRegistry(fileURL: dir.appendingPathComponent("compose_projects.json"))
        let scripted = ScriptedPrompter(decisions)
        let permissions = PermissionStore(fileURL: dir.appendingPathComponent("permissions.json"))
        let activity = ActivityLog(fileURL: dir.appendingPathComponent("activity.jsonl"))
        self.docker = fake
        self.compose = composeAvailable ? fakeCompose : nil
        self.registry = fakeRegistry
        self.scripted = scripted
        self.permissions = permissions
        self.activity = activity
        let composeRunner = composeAvailable ? fakeCompose : nil
        let composeFactory: (@Sendable () async -> (any ComposeOperations)?)?
        if let composeRunner {
            composeFactory = { [composeRunner] in composeRunner }
        } else {
            composeFactory = nil
        }
        self.router = ToolRouter(
            docker: { dockerAvailable ? fake : nil },
            compose: composeFactory,
            registry: fakeRegistry,
            permissions: permissions,
            prompter: prompter ?? scripted,
            activity: activity,
            approvalTimeout: timeout
        )
    }

    func call(_ tool: String, _ arguments: [String: JSONValue] = [:], client: String = "claude") async -> ToolOutput {
        await router.call(tool, arguments: arguments, client: client)
    }

    func lastOutcome() async -> ActivityEntry.Outcome? { await activity.entries().first?.outcome }
}

private func json(_ text: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(text.utf8))
}

private let web = FakeDocker.id("aaa111")

// MARK: - Validation

@Test func unknownToolIsErrorAndRecorded() async {
    let h = Harness()
    let out = await h.call("nope")
    #expect(out.isError && out.text.contains("Unknown tool"))
    #expect(await h.lastOutcome() == .error)
    #expect(await h.docker.calls.isEmpty)
}

@Test func missingRequiredArgumentIsErrorWithoutDockerOrPrompt() async {
    let h = Harness(decisions: [.allowOnce])
    let out = await h.call("stop_container")
    #expect(out.isError && out.text.contains("container"))
    #expect(await h.docker.calls.isEmpty)
    #expect(await h.scripted.requests.isEmpty)
    #expect(await h.lastOutcome() == .error)
}

@Test(arguments: [
    ("exec_in_container", ["container": JSONValue.string("web"), "command": .string("ls")]),
    ("exec_in_container", ["container": .string("web"), "command": .array([])]),
    ("exec_in_container", ["container": .string("web"), "command": .array([.int(1)])]),
    ("get_logs", ["container": .string("web"), "tail": .string("x")]),
    ("start_container", ["container": .int(5)]),
    ("start_container", ["container": .string("web"), "reason": .int(1)]),
])
func wrongTypesAreErrorsWithoutDocker(tool: String, arguments: [String: JSONValue]) async {
    let h = Harness(decisions: [.allowOnce])
    let out = await h.call(tool, arguments)
    #expect(out.isError)
    #expect(await h.docker.calls.isEmpty)
    #expect(await h.scripted.requests.isEmpty)
}

// MARK: - Permissions

@Test func allowRuleExecutesAndRecordsAllowed() async throws {
    let h = Harness()
    let out = await h.call("list_containers")
    #expect(!out.isError)
    let list = try #require(try json(out.text) as? [[String: Any]])
    let web = try #require(list.first { $0["name"] as? String == "web" })
    #expect((web["id"] as? String)?.count == 12)
    #expect(web["state"] as? String == "running")
    #expect(list.first { $0["name"] as? String == "db" }?["project"] as? String == "app")
    #expect(await h.docker.calls == ["listContainers"])
    #expect(await h.lastOutcome() == .allowed)
}

@Test func listContainersAllFalseHidesStopped() async throws {
    let h = Harness()
    let out = await h.call("list_containers", ["all": .bool(false)])
    let names = try #require(try json(out.text) as? [[String: Any]]).compactMap { $0["name"] as? String }
    #expect(!names.contains("web-2") && names.contains("web"))
}

@Test func denyRuleBlocksWithoutDockerCall() async throws {
    let h = Harness(decisions: [.allowOnce])
    try await h.permissions.set(.deny, for: "remove_container")
    let out = await h.call("remove_container", ["container": .string("web")])
    #expect(out.isError && out.text.contains("Blocked"))
    #expect(await h.docker.calls.isEmpty)
    #expect(await h.scripted.requests.isEmpty)
    #expect(await h.lastOutcome() == .denied)
}

@Test func askAllowOnceExecutesAndAsksAgainNextTime() async {
    let h = Harness(decisions: [.allowOnce, .allowOnce])
    let first = await h.call("stop_container", ["container": .string("web")])
    let second = await h.call("stop_container", ["container": .string("web")])
    #expect(!first.isError && !second.isError)
    #expect(await h.scripted.requests.count == 2)
    #expect(await h.docker.calls.filter { $0 == "stop:\(web)" }.count == 2)
    #expect(await h.lastOutcome() == .approved)
}

@Test func askAllowAlwaysFlipsRuleToAllow() async {
    let h = Harness(decisions: [.allowAlways])
    _ = await h.call("stop_container", ["container": .string("web")])
    #expect(await h.permissions.permission(for: "stop_container") == .allow)
    _ = await h.call("stop_container", ["container": .string("web")])
    #expect(await h.scripted.requests.count == 1)
    #expect(await h.lastOutcome() == .allowed)
}

@Test func execNeverOffersOrAppliesAlways() async {
    let h = Harness(decisions: [.allowAlways])
    let out = await h.call("exec_in_container", ["container": .string("web"), "command": .array([.string("ls")])])
    #expect(!out.isError)
    #expect(await h.scripted.requests.first?.allowsAlways == false)
    #expect(await h.permissions.permission(for: "exec_in_container") == .ask)
}

@Test func askDenyDoesNotExecute() async {
    let h = Harness(decisions: [.deny])
    let out = await h.call("stop_container", ["container": .string("web")])
    #expect(out.isError && out.text.contains("denied"))
    #expect(await h.docker.calls.allSatisfy { !$0.hasPrefix("stop:") })
    #expect(await h.lastOutcome() == .denied)
}

@Test func askTimeoutDeniesAndDoesNotExecute() async {
    let h = Harness(prompter: NeverPrompter(), timeout: .milliseconds(50))
    let out = await h.call("stop_container", ["container": .string("web")])
    #expect(out.isError && out.text.contains("timed out"))
    #expect(await h.docker.calls.allSatisfy { !$0.hasPrefix("stop:") })
    #expect(await h.lastOutcome() == .denied)
}

@Test func timeoutRemovesTheRequestFromTheRealQueue() async throws {
    let queue = ApprovalQueue()
    let h = Harness(prompter: queue, timeout: .milliseconds(50))
    let out = await h.call("stop_container", ["container": .string("web")])
    #expect(out.isError)
    for _ in 0..<200 where !(await queue.pending().isEmpty) { try await Task.sleep(for: .milliseconds(5)) }
    #expect(await queue.pending().isEmpty)
}

@Test func dockerUnavailableIsExplainedNotHung() async {
    let h = Harness(dockerAvailable: false)
    let out = await h.call("list_containers")
    #expect(out.isError && out.text.contains("Docker is not connected"))
    #expect(await h.lastOutcome() == .error)
}

// MARK: - Container resolution

@Test func containerResolution() async {
    let h = Harness()
    let byName = await h.call("start_container", ["container": .string("web")])
    #expect(!byName.isError)
    let byPrefix = await h.call("start_container", ["container": .string("bbb")])
    #expect(!byPrefix.isError)
    let calls = await h.docker.calls
    #expect(calls.contains("start:\(web)"))
    #expect(calls.contains("start:\(FakeDocker.id("bbb222"))"))

    let ambiguous = await h.call("start_container", ["container": .string("abc")])
    #expect(ambiguous.isError && ambiguous.text.contains("svc-a") && ambiguous.text.contains("svc-b"))

    let missing = await h.call("start_container", ["container": .string("ghost")])
    #expect(missing.isError && missing.text.contains("No container matches"))
    #expect(await h.docker.calls.filter { $0.hasPrefix("start:") }.count == 2)
}

// MARK: - Outputs

@Test func inspectMasksEnvButGetContainerEnvDoesNot() async {
    let h = Harness(decisions: [.allowOnce])
    let inspected = await h.call("inspect_container", ["container": .string("web")])
    #expect(inspected.text.contains("PLAIN=***") && !inspected.text.contains("hunter2"))
    let env = await h.call("get_container_env", ["container": .string("web")])
    #expect(env.text.contains("SECRET=hunter2") && env.text.contains("PLAIN=1"))
}

@Test func getLogsClampsAndDefaultsTail() async {
    let h = Harness()
    let out = await h.call("get_logs", ["container": .string("web"), "tail": .int(5000)])
    #expect(out.text == "first\nsecond")
    #expect(await h.docker.requestedTail == 2000)
    _ = await h.call("get_logs", ["container": .string("web")])
    #expect(await h.docker.requestedTail == 100)
    _ = await h.call("get_logs", ["container": .string("web"), "tail": .int(0)])
    #expect(await h.docker.requestedTail == 1)
}

@Test func getStatsReturnsNamedFields() async throws {
    let h = Harness()
    let out = await h.call("get_stats", ["container": .string("web")])
    let stats = try #require(try json(out.text) as? [String: Any])
    #expect(stats["cpu_percent"] as? Double == 80)
    #expect(stats["memory_used_bytes"] as? Int == 600)
    #expect(stats["memory_limit_bytes"] as? Int == 1000)
}

@Test func execResultIsFormattedAsJSON() async throws {
    let h = Harness(decisions: [.allowOnce])
    let out = await h.call("exec_in_container", ["container": .string("web"), "command": .array([.string("echo")])])
    let result = try #require(try json(out.text) as? [String: Any])
    #expect(result["exit_code"] as? Int == 0)
    #expect(result["stdout"] as? String == "hi\n")
    #expect(result["truncated"] as? Bool == false)
}

@Test func removeContainerForwardsForce() async {
    let h = Harness(decisions: [.allowOnce, .allowOnce])
    _ = await h.call("remove_container", ["container": .string("web")])
    _ = await h.call("remove_container", ["container": .string("web"), "force": .bool(true)])
    let calls = await h.docker.calls
    #expect(calls.contains("remove:\(web):force=false") && calls.contains("remove:\(web):force=true"))
}

// MARK: - Approval request content

@Test func approvalRequestShowsContainerNameCommandAndReason() async throws {
    let h = Harness(decisions: [.allowOnce])
    _ = await h.call(
        "exec_in_container",
        ["container": .string("web"), "command": .array([.string("ls"), .string("-la"), .string("/my app")]),
         "reason": .string("debugging")],
        client: "Claude Code")
    let request = try #require(await h.scripted.requests.first)
    #expect(request.client == "Claude Code" && request.tool == "exec_in_container")
    #expect(request.reason == "debugging")
    #expect(request.arguments.contains(ApprovalArgument(name: "container", value: "web")))
    #expect(request.arguments.contains(ApprovalArgument(name: "command", value: #"ls -la "/my app""#)))
}

// MARK: - Errors and activity

@Test func dockerErrorBecomesToolError() async {
    let h = Harness()
    await h.docker.setFailure(DockerError.conflict("container is running"))
    let out = await h.call("start_container", ["container": .string("web")])
    #expect(out.isError && out.text.contains("container is running"))
    #expect(await h.lastOutcome() == .error)
}

@Test func activityRecordsClientToolAndArguments() async throws {
    let h = Harness()
    _ = await h.call("get_logs", ["container": .string("web"), "tail": .int(5), "reason": .string("why")],
                     client: "Cursor")
    let entry = try #require(await h.activity.entries().first)
    #expect(entry.client == "Cursor" && entry.tool == "get_logs")
    #expect(entry.arguments.contains("container=web") && entry.arguments.contains("tail=5"))
    #expect(entry.arguments.contains("reason=why"))
}

@Test func reasonIsAcceptedByEveryTool() async throws {
    let h = Harness()
    for spec in ToolCatalog.all { try await h.permissions.set(.allow, for: spec.name) }
    for spec in ToolCatalog.all {
        var arguments: [String: JSONValue] = ["reason": .string("because")]
        for parameter in spec.parameters where parameter.required {
            arguments[parameter.name] = parameter.kind == .stringArray ? .array([.string("echo")]) : (parameter.name == "project" ? .string("app") : .string("web"))
        }
        let out = await h.call(spec.name, arguments)
        #expect(!out.isError, "\(spec.name): \(out.text)")
    }
}

// MARK: - Resource tools (Images, Volumes, Networks, System Prune)

@Test func listImagesAllowedAndOutputsJSON() async throws {
    let h = Harness()
    let out = await h.call("list_images")
    #expect(!out.isError)
    let list = try #require(try json(out.text) as? [[String: Any]])
    #expect(list.count == 3)
    let nginx = try #require(list.first { ($0["repo_tags"] as? [String])?.contains("nginx:latest") == true })
    #expect((nginx["id"] as? String)?.count == 12)
    #expect(nginx["size_bytes"] as? Int64 == 142_000_000 || nginx["size_bytes"] as? Int == 142_000_000)
    #expect(await h.docker.calls == ["listImages"])
    #expect(await h.lastOutcome() == .allowed)
}

@Test func listVolumesAllowedAndOutputsJSON() async throws {
    let h = Harness()
    let out = await h.call("list_volumes")
    #expect(!out.isError)
    let list = try #require(try json(out.text) as? [[String: Any]])
    #expect(list.count == 2)
    let dbVol = try #require(list.first { $0["name"] as? String == "db_data" })
    #expect(dbVol["driver"] as? String == "local")
    #expect(dbVol["scope"] as? String == "local")
    #expect(await h.docker.calls == ["listVolumes"])
    #expect(await h.lastOutcome() == .allowed)
}

@Test func listNetworksAllowedAndOutputsJSON() async throws {
    let h = Harness()
    let out = await h.call("list_networks")
    #expect(!out.isError)
    let list = try #require(try json(out.text) as? [[String: Any]])
    #expect(list.count == 2)
    let bridge = try #require(list.first { $0["name"] as? String == "bridge" })
    #expect((bridge["id"] as? String)?.count == 12)
    #expect(bridge["driver"] as? String == "bridge")
    #expect(bridge["container_count"] as? Int == 2)
    #expect(await h.docker.calls == ["listNetworks"])
    #expect(await h.lastOutcome() == .allowed)
}

@Test func removeImageDenyByDefaultAndAllowExecutesWithForce() async throws {
    let h = Harness()
    let denied = await h.call("remove_image", ["image": .string("img111")])
    #expect(denied.isError && denied.text.contains("Blocked"))
    #expect(await h.docker.calls.isEmpty)
    #expect(await h.lastOutcome() == .denied)

    try await h.permissions.set(.allow, for: "remove_image")
    let out = await h.call("remove_image", ["image": .string("img111"), "force": .bool(true)])
    #expect(!out.isError && out.text.contains("img111"))
    #expect(await h.docker.calls == ["removeImage:img111:force=true"])
    #expect(await h.lastOutcome() == .allowed)
}

@Test func removeVolumePromptsApprovalWhenAsk() async throws {
    let h = Harness(decisions: [.allowOnce])
    try await h.permissions.set(.ask, for: "remove_volume")
    let out = await h.call("remove_volume", ["volume": .string("db_data")], client: "claude")
    #expect(!out.isError && out.text.contains("db_data"))
    #expect(await h.docker.calls == ["removeVolume:db_data:force=false"])
    #expect(await h.lastOutcome() == .approved)

    let req = try #require(await h.scripted.requests.first)
    #expect(req.tool == "remove_volume")
    #expect(req.client == "claude")
    #expect(req.arguments.contains(ApprovalArgument(name: "volume", value: "db_data")))
}

@Test func removeNetworkBlocksDefaultNetworksAndExecutesCustom() async throws {
    let h = Harness()
    let denied = await h.call("remove_network", ["network": .string("custom_net")])
    #expect(denied.isError && denied.text.contains("Blocked"))
    #expect(await h.docker.calls.isEmpty)
    #expect(await h.lastOutcome() == .denied)

    try await h.permissions.set(.allow, for: "remove_network")
    for predefined in ["bridge", "host", "none"] {
        let blocked = await h.call("remove_network", ["network": .string(predefined)])
        #expect(blocked.isError && blocked.text.contains("cannot be removed"))
    }
    #expect(await h.docker.calls.filter { $0.hasPrefix("removeNetwork:") }.isEmpty)

    let out = await h.call("remove_network", ["network": .string("custom_net")])
    #expect(!out.isError && out.text.contains("custom_net"))
    #expect(await h.docker.calls.contains("removeNetwork:\(FakeDocker.id("net222"))"))
    #expect(await h.lastOutcome() == .allowed)

    let shortOut = await h.call("remove_network", ["network": .string("net222")])
    #expect(!shortOut.isError && shortOut.text.contains("net222"))
    #expect(await h.docker.calls.contains("removeNetwork:\(FakeDocker.id("net222"))"))

    let fallbackOut = await h.call("remove_network", ["network": .string("unlisted_net")])
    #expect(!fallbackOut.isError && fallbackOut.text.contains("unlisted_net"))
    #expect(await h.docker.calls.contains("removeNetwork:unlisted_net"))
}

@Test func systemPruneForwardsParametersAndOutputsReport() async throws {
    let h = Harness()
    let denied = await h.call("system_prune")
    #expect(denied.isError && denied.text.contains("Blocked"))
    #expect(await h.docker.calls.isEmpty)
    #expect(await h.lastOutcome() == .denied)

    try await h.permissions.set(.allow, for: "system_prune")
    let out = await h.call("system_prune", ["all": .bool(true), "volumes": .bool(true)])
    #expect(!out.isError)
    #expect(await h.docker.calls.contains("systemPrune:all=true:volumes=true"))
    let report = try #require(try json(out.text) as? [String: Any])
    #expect(report["containers_deleted"] as? Int == 1)
    #expect(report["images_deleted"] as? Int == 1)
    #expect(report["networks_deleted"] as? Int == 1)
    #expect(report["volumes_deleted"] as? Int == 1)
    #expect((report["space_reclaimed_bytes"] as? Int64 ?? (report["space_reclaimed_bytes"] as? Int).map(Int64.init)) == 7168)

    _ = await h.call("system_prune")
    #expect(await h.docker.calls.contains("systemPrune:all=false:volumes=false"))
}

// MARK: - Compose Tools

@Test func listComposeProjectsReturnsFormattedJSON() async throws {
    let registryDir = FileManager.default.temporaryDirectory.appendingPathComponent("reg-\(UUID().uuidString)")
    let registry = ComposeProjectRegistry(fileURL: registryDir.appendingPathComponent("compose_projects.json"))
    let compose = FakeComposeRunner()
    let h = Harness(compose: compose, registry: registry)

    // Ingest a project with working dir and config files into registry
    let containerWithLabels = ContainerSummary(
        id: FakeDocker.id("bbb222"),
        names: ["/db"],
        image: "postgres:16",
        state: "running",
        status: "Up 2 hours",
        labels: [
            "com.docker.compose.project": "app",
            "com.docker.compose.service": "db",
            "com.docker.compose.project.working_dir": "/workspace",
            "com.docker.compose.project.config_files": "docker-compose.yml"
        ],
        ports: []
    )
    await registry.ingest([containerWithLabels])

    let out = await h.call("list_compose_projects")
    #expect(!out.isError)
    let list = try #require(try json(out.text) as? [[String: Any]])
    #expect(!list.isEmpty)
    let project = try #require(list.first { $0["name"] as? String == "app" })
    #expect(project["name"] as? String == "app")
    #expect(project["status"] as? String == "running")
    #expect(project["working_dir"] as? String == "/workspace")
    #expect(project["config_files"] as? [String] == ["docker-compose.yml"])
    let services = try #require(project["services"] as? [[String: Any]])
    #expect(services.count == 1)
    #expect(services.first?["name"] as? String == "db")
    #expect(services.first?["status"] as? String == "running")
}

@Test func composeUpExecutesWhenApproved() async throws {
    let registryDir = FileManager.default.temporaryDirectory.appendingPathComponent("reg-\(UUID().uuidString)")
    let registry = ComposeProjectRegistry(fileURL: registryDir.appendingPathComponent("compose_projects.json"))
    let compose = FakeComposeRunner(cannedUp: "Stack started successfully")
    let h = Harness(decisions: [.allowOnce], compose: compose, registry: registry)

    let containerWithLabels = ContainerSummary(
        id: FakeDocker.id("bbb222"),
        names: ["/db"],
        image: "postgres:16",
        state: "running",
        status: "Up 2 hours",
        labels: [
            "com.docker.compose.project": "app",
            "com.docker.compose.service": "db",
            "com.docker.compose.project.working_dir": "/workspace",
            "com.docker.compose.project.config_files": "docker-compose.yml"
        ],
        ports: []
    )
    await registry.ingest([containerWithLabels])

    let out = await h.call("compose_up", ["project": .string("app")])
    #expect(!out.isError)
    #expect(out.text.contains("Stack started successfully") || out.text.contains("Started"))

    let calls = await compose.calls
    #expect(calls == [.up(project: "app", workingDir: "/workspace", configFiles: ["docker-compose.yml"])])
    #expect(await h.lastOutcome() == .approved)

    let request = try #require(await h.scripted.requests.first)
    #expect(request.tool == "compose_up")
    #expect(request.allowsAlways == true)
    #expect(request.arguments.contains(ApprovalArgument(name: "project", value: "app")))
}

@Test func composeDownExecutesAndForbidsAllowsAlways() async throws {
    let registryDir = FileManager.default.temporaryDirectory.appendingPathComponent("reg-\(UUID().uuidString)")
    let registry = ComposeProjectRegistry(fileURL: registryDir.appendingPathComponent("compose_projects.json"))
    let compose = FakeComposeRunner(cannedDown: "Stack stopped")
    let h = Harness(decisions: [.allowOnce], compose: compose, registry: registry)

    let containerWithLabels = ContainerSummary(
        id: FakeDocker.id("bbb222"),
        names: ["/db"],
        image: "postgres:16",
        state: "running",
        status: "Up 2 hours",
        labels: [
            "com.docker.compose.project": "app",
            "com.docker.compose.service": "db",
            "com.docker.compose.project.working_dir": "/workspace",
            "com.docker.compose.project.config_files": "docker-compose.yml"
        ],
        ports: []
    )
    await registry.ingest([containerWithLabels])

    let out = await h.call("compose_down", ["project": .string("app"), "remove_volumes": .bool(true)])
    #expect(!out.isError)
    #expect(out.text.contains("Stack stopped") || out.text.contains("Stopped"))

    let calls = await compose.calls
    #expect(calls == [.down(project: "app", workingDir: "/workspace", configFiles: ["docker-compose.yml"], removeVolumes: true)])
    #expect(await h.lastOutcome() == .approved)

    // Critical check: compose_down MUST forbid allowsAlways in the approval request!
    let request = try #require(await h.scripted.requests.first)
    #expect(request.tool == "compose_down")
    #expect(request.allowsAlways == false)
    #expect(request.arguments.contains(ApprovalArgument(name: "project", value: "app")))
    #expect(request.arguments.contains(ApprovalArgument(name: "remove_volumes", value: "true")))
}

@Test func composeToolsErrorOnUnknownProject() async throws {
    let compose = FakeComposeRunner()
    let h = Harness(decisions: [.allowOnce, .allowOnce], compose: compose)

    let upOut = await h.call("compose_up", ["project": .string("nonexistent")])
    #expect(upOut.isError)
    #expect(upOut.text.contains("Unknown compose project 'nonexistent'"))

    let downOut = await h.call("compose_down", ["project": .string("nonexistent")])
    #expect(downOut.isError)
    #expect(downOut.text.contains("Unknown compose project 'nonexistent'"))
}

@Test func composeToolsErrorWhenRunnerUnavailable() async throws {
    // When compose runner is nil
    let hNil = Harness(composeAvailable: false)
    let outNil = await hNil.call("list_compose_projects")
    #expect(outNil.isError)
    #expect(outNil.text.contains("Docker Compose is not available"))

    // When compose runner reports isComposeAvailable == false
    let fakeUnavailable = FakeComposeRunner(isAvailable: false)
    let hUnavailable = Harness(compose: fakeUnavailable)
    let outUnavail = await hUnavailable.call("list_compose_projects")
    #expect(outUnavail.isError)
    #expect(outUnavail.text.contains("Docker Compose is not available"))
}
