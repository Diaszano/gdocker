# Changelog

All notable changes to GDocker are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
