# Changelog

All notable changes to GDocker are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0](https://github.com/Diaszano/gdocker/compare/v0.1.0...v0.2.0) (2026-11-26)


### Added

* **core:** decode container SizeRw and add status filtering ([a4a705c](https://github.com/Diaszano/gdocker/commit/a4a705c76bd7d92fdd9bdd22c6d2d1ddda0317ed))
* **docker:** support Rancher Desktop socket and CLI paths ([7a0faad](https://github.com/Diaszano/gdocker/commit/7a0faadb7614736c04bc7195332249fdfe09da25))
* **ui:** add resizable columns and unify resource tables ([b7a77ea](https://github.com/Diaszano/gdocker/commit/b7a77eac98edf488945420b6d66421e88bd64cf6))
* **ui:** add ServiceKind matcher and ServiceLogo component ([ddc9d5f](https://github.com/Diaszano/gdocker/commit/ddc9d5fef1bbfde5ba1a7e6edb3ff8e9114ce2e8))
* **ui:** add StatusBadge, FilterPill, IconActionButton, and TabStrip components ([7086e59](https://github.com/Diaszano/gdocker/commit/7086e594e9298ea538e600a053787e40314dc001))
* **ui:** implement Penpot UI redesign and localization ([039fe3e](https://github.com/Diaszano/gdocker/commit/039fe3e167f8ad077102f6d48dd3db819789ad7b))
* **ui:** replace static menu bar list with Catppuccin popover ([454779b](https://github.com/Diaszano/gdocker/commit/454779bf0b877ad9d2466bc7b63a74af40e017cf))
* **ui:** show CPU %, memory used, and disk bars in RuntimeCard ([1a67dda](https://github.com/Diaszano/gdocker/commit/1a67dda3d6bd7ac440f0fb9cff85e68ba9f200c8))
* **ui:** use Penpot brand logos and fix table alignments ([dc68959](https://github.com/Diaszano/gdocker/commit/dc6895954d3f7c566a4c615ccf7c2a9fd99a8a85))
* **volumes:** open Docker volumes in Finder via WebDAV ([0faa5ab](https://github.com/Diaszano/gdocker/commit/0faa5ab8cad113241b936bb5f7474d0352f0860f))
* **volumes:** use GDocker.local hostname for WebDAV Finder mounts ([3dce8d2](https://github.com/Diaszano/gdocker/commit/3dce8d242ab6f232d76e8f689992732b5a209dee))


### Fixed

* apply all 14 audit findings across core, mcp, and ui ([8b1d4c5](https://github.com/Diaszano/gdocker/commit/8b1d4c5d866a8ac2618756e4b28768dbdf21ecc6))
* **ci:** use macos-latest and select latest installed Xcode ([4920175](https://github.com/Diaszano/gdocker/commit/492017573d59da009822d95f6642220af498d2fd))
* **ui:** align sidebar MCP row and indent AI sub-items ([045db97](https://github.com/Diaszano/gdocker/commit/045db9765bad4d07827fb04f82cfbc88ee823c5b))
* **ui:** collapse inspector on launch and scroll container table horizontally ([1b43087](https://github.com/Diaszano/gdocker/commit/1b430874e27ad752f035923818f425021e3ebc80))
* **ui:** set minimum window size, fix alignment, and show Colima info ([a8133c8](https://github.com/Diaszano/gdocker/commit/a8133c8f150f57e2a9fddb3bcc4f0a3ddc9596e4))
* **ui:** theme window titlebar and polish table controls ([4bdd24c](https://github.com/Diaszano/gdocker/commit/4bdd24ce72c0a7d1a3b773cc1e227e602b8dc749))

## [Unreleased]

### Added

- Support for Rancher Desktop socket and CLI paths.
- Open Docker volumes in Finder via local WebDAV mount (`GDocker.local`).
- Catppuccin-themed menu bar popover replacing the static menu bar list.
- Resizable table columns and unified resource tables with Penpot brand service logos.
- CPU %, memory usage, and disk progress bars in `RuntimeCard`.
- Standardized repository tooling: `.swift-format`, `.swiftlint.yml`, `.editorconfig`, `.githooks/commit-msg`, and expanded `Makefile`.
- Automated CI, Conventional Commits validation, CodeQL security scanning, and universal GitHub Release + `Diaszano/homebrew-tap` publishing workflows.
- Bilingual documentation (`README.md`, `README.pt-BR.md`, `docs/`), `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`, and GitHub Issue/PR templates.

### Changed

- Extracted Homebrew 7 Cask generation into `scripts/generate-cask.sh` and added `SHA256SUMS` output to `scripts/release.sh`.
- Formatted `Sources/` and `Tests/` with `swift format` and resolved SwiftLint warnings.

### Fixed

- Applied 14 audit findings across `GDockerCore`, `GDockerMCP`, and UI modules.
- Improved window titlebar theming, table alignment, minimum window size, and Colima runtime display.

## [0.1.0] - 2026-11-13

### Added

- Initial native macOS SwiftUI app for Docker (macOS 14 Sonoma+).
- Container management grouped by Compose project with live logs, stats, inspect, environment, and interactive SwiftTerm terminal.
- Images, volumes, networks, and Compose project views with prune and `compose up`/`down`.
- Built-in MCP server (`127.0.0.1` HTTP + `--stdio` bridge) with Keychain bearer token, Allow/Ask/Deny permission policies, approval prompts, and AI activity log.
- English and Brazilian Portuguese localization (`Localizable.xcstrings`) and automated `scripts/check_l10n.py` validation.
- Universal build script (`scripts/release.sh`) and Homebrew 7 Cask support.
