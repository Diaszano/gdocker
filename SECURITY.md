# Security Policy

## Supported Versions

Until GDocker reaches 1.0, security fixes are applied on the `main` branch and released in the latest `0.x` version.

## Private Reporting

Report vulnerabilities through GitHub's private vulnerability reporting flow:

1. Open the GDocker repository's **Security** tab.
2. Select **Advisories**.
3. Select **Report a vulnerability**.

Do not open a public issue for an unpatched vulnerability.

Include:

- affected GDocker version or commit SHA;
- macOS version and architecture (`arm64` / `x86_64`);
- minimal reproduction steps;
- expected vs. observed security behavior;
- potential impact (e.g., unauthorized Docker action, token disclosure, privilege boundary bypass).

Do not include real credentials, Keychain secrets, or private container data. Maintainers will acknowledge receipt, investigate, coordinate a fix, and publish an advisory when appropriate.

## Scope

Security-sensitive areas include:

- bypassing the MCP server's `127.0.0.1`-only bind, `Host`/`Origin` validation, or bearer token authentication;
- bypassing **Ask** or **Deny** tool permission policies or approval timeouts;
- command injection or approval-scope bypass in `exec_in_container` or Docker CLI wrappers;
- leaking masked environment variable values outside `get_container_env`;
- unsafe Keychain token storage or exposure in logs/activity views;
- unauthorized access or path traversal in the local WebDAV volume mount server.

See [docs/security.md](docs/security.md) for details on GDocker's security architecture.
