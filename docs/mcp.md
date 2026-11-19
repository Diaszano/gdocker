# MCP Server & AI Clients

**Languages:** 🇺🇸 **English** • [🇧🇷 Português](mcp.pt-BR.md)

GDocker includes a built-in **Model Context Protocol (MCP)** server so AI coding assistants can inspect and manage your local Docker environment under explicit, per-tool permissions.

## Starting the Server

1. Open **Permissions** in the GDocker sidebar and toggle the MCP server on.
2. Optionally enable **Start the MCP server when the app opens** in **Settings**.
3. The server listens on `http://127.0.0.1:7391/mcp` by default (configurable in Settings).

> [!IMPORTANT]
> GDocker must be running for AI clients to reach the MCP server.

## Client Configuration

Click **Copy config** in the **Permissions** view to copy a ready-to-use snippet with your current port and token.

### Claude Code (HTTP)

```sh
claude mcp add --transport http gdocker http://localhost:7391/mcp --header "Authorization: Bearer <token>"
```

### Cursor & Generic HTTP Clients (`mcpServers` JSON)

```json
{
  "mcpServers": {
    "gdocker": {
      "url": "http://localhost:7391/mcp",
      "headers": {
        "Authorization": "Bearer <token>"
      }
    }
  }
}
```

### Claude Desktop (`--stdio` Bridge)

Claude Desktop uses stdio transport. Pass `--stdio` to the GDocker executable — it connects to the running GDocker app over localhost and reads the bearer token automatically from the macOS Keychain:

```json
{
  "mcpServers": {
    "gdocker": {
      "command": "/Applications/GDocker.app/Contents/MacOS/GDocker",
      "args": ["--stdio"]
    }
  }
}
```

## Tool Catalog & Default Policies

Every tool can be set to **Allow**, **Ask**, or **Deny** in the **Permissions** screen:

| Default | Tools |
| --- | --- |
| **Allow** | `list_containers`, `inspect_container`, `get_logs`, `get_stats`, `list_images`, `list_volumes`, `list_networks`, `list_compose_projects`, `start_container`, `restart_container` |
| **Ask** | `get_container_env`, `stop_container`, `exec_in_container`, `compose_up`, `compose_down`, `remove_container` |
| **Deny** | `remove_image`, `remove_volume`, `remove_network`, `system_prune` |

### Special Safeguards

- **Environment masking:** Environment variable values are replaced with `***` in `inspect_container` and everywhere else except `get_container_env`.
- **Exact command approval:** Approving `exec_in_container` authorizes only that exact command invocation and never offers *Always allow*.
- **Approval timeout:** Unanswered approval prompts are automatically denied after 2 minutes.
- **Audit trail:** Every MCP tool invocation (allowed, approved, denied, or failed) is recorded in **AI Activity** in the sidebar.
