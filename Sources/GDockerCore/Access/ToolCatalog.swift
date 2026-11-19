public enum ToolCatalog {
    private static let container = ToolParameter(
        name: "container", kind: .string, required: true,
        summary: "Container name, id, or a unique id prefix.")

    public static let all: [ToolSpec] = [
        ToolSpec(
            name: "list_containers", title: "List containers and status", group: .read, defaultPermission: .allow,
            summary: "List Docker containers with their state, image, ports and compose project.",
            parameters: [
                ToolParameter(
                    name: "all", kind: .boolean, required: false,
                    summary: "Include stopped containers. Defaults to true.")
            ]),
        ToolSpec(
            name: "inspect_container", title: "Inspect a container", group: .read, defaultPermission: .allow,
            summary: "Return the full inspect JSON of a container. Environment variable values are masked.",
            parameters: [container]),
        ToolSpec(
            name: "get_logs", title: "Read logs", group: .read, defaultPermission: .allow,
            summary: "Return the most recent log lines of a container.",
            parameters: [
                container,
                ToolParameter(
                    name: "tail", kind: .integer, required: false,
                    summary: "Number of lines, 1 to 2000. Defaults to 100."),
                ToolParameter(
                    name: "timestamps", kind: .boolean, required: false,
                    summary: "Prefix each line with its timestamp."),
            ]),
        ToolSpec(
            name: "get_stats", title: "View stats (CPU/memory)", group: .read, defaultPermission: .allow,
            summary: "Return one sample of CPU, memory and network usage of a running container.",
            parameters: [container]),
        ToolSpec(
            name: "get_container_env", title: "View environment variables", group: .sensitiveRead,
            defaultPermission: .ask,
            summary: "Return the environment variables of a container with their real values (may contain secrets).",
            parameters: [container]),
        ToolSpec(
            name: "start_container", title: "Start a container", group: .control, defaultPermission: .allow,
            summary: "Start a stopped container.",
            parameters: [container]),
        ToolSpec(
            name: "restart_container", title: "Restart a container", group: .control, defaultPermission: .allow,
            summary: "Restart a container.",
            parameters: [container]),
        ToolSpec(
            name: "stop_container", title: "Stop a container", group: .control, defaultPermission: .ask,
            summary: "Stop a running container.",
            parameters: [container]),
        ToolSpec(
            name: "exec_in_container", title: "Run a command inside a container", group: .control,
            defaultPermission: .ask,
            summary: "Run one command inside a running container and return its exit code, stdout and stderr. "
                + "The command is an argument list, not a shell string.",
            parameters: [
                container,
                ToolParameter(
                    name: "command", kind: .stringArray, required: true,
                    summary: "Program and arguments, e.g. [\"ls\", \"-la\", \"/app\"]."),
            ],
            allowsAlways: false),
        ToolSpec(
            name: "remove_container", title: "Remove a container", group: .destructive, defaultPermission: .ask,
            summary: "Delete a container permanently.",
            parameters: [
                container,
                ToolParameter(
                    name: "force", kind: .boolean, required: false,
                    summary: "Remove even if running. Defaults to false."),
            ]),
        ToolSpec(
            name: "list_images", title: "List images", group: .read, defaultPermission: .allow,
            summary: "List local Docker images with their repository tags, size and creation date.",
            parameters: []),
        ToolSpec(
            name: "list_volumes", title: "List volumes", group: .read, defaultPermission: .allow,
            summary: "List Docker volumes with their name, driver and creation date.",
            parameters: []),
        ToolSpec(
            name: "list_networks", title: "List networks", group: .read, defaultPermission: .allow,
            summary: "List Docker networks with their name, driver, scope and connected container count.",
            parameters: []),
        ToolSpec(
            name: "remove_image", title: "Remove an image", group: .destructive, defaultPermission: .deny,
            summary: "Delete a Docker image permanently.",
            parameters: [
                ToolParameter(
                    name: "image", kind: .string, required: true,
                    summary: "Image ID, tag, or repository name."),
                ToolParameter(
                    name: "force", kind: .boolean, required: false,
                    summary: "Force removal of the image. Defaults to false."),
            ]),
        ToolSpec(
            name: "remove_volume", title: "Remove a volume", group: .destructive, defaultPermission: .deny,
            summary: "Delete a Docker volume permanently.",
            parameters: [
                ToolParameter(
                    name: "volume", kind: .string, required: true,
                    summary: "Volume name."),
                ToolParameter(
                    name: "force", kind: .boolean, required: false,
                    summary: "Force removal of the volume. Defaults to false."),
            ]),
        ToolSpec(
            name: "remove_network", title: "Remove a network", group: .destructive, defaultPermission: .deny,
            summary: "Delete a Docker network permanently.",
            parameters: [
                ToolParameter(
                    name: "network", kind: .string, required: true,
                    summary: "Network name or ID.")
            ]),
        ToolSpec(
            name: "system_prune", title: "System prune", group: .destructive, defaultPermission: .deny,
            summary:
                "Remove unused Docker data: stopped containers, unused networks, dangling/unused images, and optionally volumes.",
            parameters: [
                ToolParameter(
                    name: "all", kind: .boolean, required: false,
                    summary: "Remove all unused images, not just dangling ones. Defaults to false."),
                ToolParameter(
                    name: "volumes", kind: .boolean, required: false,
                    summary: "Prune volumes in addition to other resources. Defaults to false."),
            ]),
        ToolSpec(
            name: "list_compose_projects", title: "List compose projects", group: .read, defaultPermission: .allow,
            summary:
                "List known Docker Compose projects with their status, working directory, configuration files and services.",
            parameters: []),
        ToolSpec(
            name: "compose_up", title: "Start a compose stack", group: .control, defaultPermission: .ask,
            summary: "Start all services in a Docker Compose project in detached mode.",
            parameters: [
                ToolParameter(
                    name: "project", kind: .string, required: true,
                    summary: "Compose project name.")
            ]),
        ToolSpec(
            name: "compose_down", title: "Stop a compose stack", group: .control, defaultPermission: .ask,
            summary: "Stop and remove containers and networks for a Docker Compose project.",
            parameters: [
                ToolParameter(
                    name: "project", kind: .string, required: true,
                    summary: "Compose project name."),
                ToolParameter(
                    name: "remove_volumes", kind: .boolean, required: false,
                    summary: "Remove named volumes declared in the compose file. Defaults to false."),
            ],
            allowsAlways: false),
    ]

    public static func spec(named name: String) -> ToolSpec? { all.first { $0.name == name } }
}
