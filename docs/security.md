# Security Architecture

**Languages:** 🇺🇸 **English** • [🇧🇷 Português](security.pt-BR.md)

GDocker exposes Docker operations to local AI clients via MCP and mounts Docker volumes in Finder via WebDAV. The sections below describe the guardrails that keep both surfaces local and under user control.

## MCP Server Isolation

- **Loopback-only binding:** The embedded SwiftNIO HTTP server binds exclusively to `127.0.0.1` and never listens on external network interfaces.
- **Host & Origin validation:** Requests with non-local `Host` or `Origin` headers are rejected (mitigating DNS rebinding and cross-site browser attacks).
- **Bearer token authentication:** Every HTTP request requires an `Authorization: Bearer <token>` header. Tokens are generated randomly and persisted in the macOS Keychain. Rotating the token takes effect immediately.
- **Payload limits:** Oversized request bodies are rejected (`413 Payload Too Large`).

## Permission & Approval Enforcement

- **Default-safe policy:** Read-only and non-destructive lifecycle tools default to *Allow*; mutating or sensitive tools (`get_container_env`, `stop_container`, `exec_in_container`, `compose_up`, `compose_down`, `remove_container`) default to *Ask*; destructive cleanup tools (`remove_image`, `remove_volume`, `remove_network`, `system_prune`) default to *Deny*.
- **Per-command exec approvals:** `exec_in_container` approvals apply only to the exact command displayed in the prompt and cannot be promoted to *Always allow*.
- **Fail-closed timeouts:** Unanswered approval prompts automatically resolve to *Deny* after 2 minutes.
- **Environment variable masking:** Values are masked (`***`) in container inspection output; reading raw values requires an explicit `get_container_env` call.

## Volume Finder Mounts (WebDAV)

When opening a Docker volume in Finder, GDocker spins up an ephemeral local WebDAV mount (`GDocker.local`) scoped to the selected volume rather than exposing the host filesystem.

## Reporting Vulnerabilities

See [SECURITY.md](../SECURITY.md) for instructions on reporting security vulnerabilities privately.
