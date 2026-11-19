# GDocker

A native macOS app for Docker, in the spirit of [lazydocker](https://github.com/jesseduffield/lazydocker) but with a real Mac UI, plus a built-in **MCP server** so an AI client (Claude Code, Claude Desktop, Cursor…) can see and control Docker under rules you set.

- **Containers** grouped by Compose project, with start, stop, restart and remove
- **Container detail:** live logs (filter, timestamps), CPU/memory stats, inspect, environment and an interactive terminal
- **Images, volumes, networks and Compose projects**, with remove, prune and compose up/down
- **MCP server** on `127.0.0.1` with a bearer token; every tool is set to *Allow*, *Ask* or *Deny*, and *Ask* shows an approval prompt
- **AI activity** log of every MCP call
- English and Brazilian Portuguese, light and dark themes, optional menu bar mode

## Requirements

- macOS 14 (Sonoma) or later
- Docker Desktop, OrbStack, Colima or Rancher Desktop running locally
- The `docker` CLI on your `PATH` for Compose and the Terminal tab

## Install

```sh
brew trust --cask diaszano/tap/gdocker
brew install --cask diaszano/tap/gdocker
```

The app is not notarized. The cask removes the quarantine flag on install; if you download the zip by hand instead, run `xattr -dr com.apple.quarantine /Applications/GDocker.app` before opening it.

Each new version has a new ad-hoc signature, so on its first launch macOS asks for your login password to let GDocker read its MCP token from the Keychain. Choose **Always Allow**.

## Connect an AI client

Start the server from **Permissions** in the sidebar (or turn on *Start the MCP server when the app opens* in Settings), then use **Copy config**. It offers three forms:

- **Claude Code** (HTTP):
  ```sh
  claude mcp add --transport http gdocker http://localhost:7391/mcp --header "Authorization: Bearer <token>"
  ```
- **Generic `mcpServers` JSON** (HTTP) for clients such as Cursor.
- **Claude Desktop** (stdio only): the same executable acts as a stdio bridge to the running app and reads the token from the Keychain.
  ```json
  { "mcpServers": { "gdocker": { "command": "/Applications/GDocker.app/Contents/MacOS/GDocker", "args": ["--stdio"] } } }
  ```

The app must be open for the AI to reach it. Port 7391 is the default and can be changed in Settings.

## Permissions

| Default | Tools |
|---|---|
| Allow | `list_containers`, `inspect_container`, `get_logs`, `get_stats`, `list_images`, `list_volumes`, `list_networks`, `list_compose_projects`, `start_container`, `restart_container` |
| Ask | `get_container_env`, `stop_container`, `exec_in_container`, `compose_up`, `compose_down`, `remove_container` |
| Deny | `remove_image`, `remove_volume`, `remove_network`, `system_prune` |

Environment variable values are masked (`***`) everywhere except `get_container_env`. An `exec_in_container` approval covers only that exact command and never offers *Always allow*. Unanswered prompts are denied after two minutes.

## Build from source

Requires Xcode 16.4 or later (Swift 6.1).

```sh
make test   # run the test suite (Docker-dependent tests skip when no daemon is running)
make app    # build build/GDocker.app
make run    # build and open it
```

## License

[MIT](LICENSE)
