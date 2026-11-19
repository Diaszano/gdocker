# GDocker Repository Standardization Design

**Date:** 2026-11-18
**Status:** Draft (pending approval)
**Reference Standard:** [`Diaszano/bearm`](https://github.com/Diaszano/bearm)

## Intent & Why

Bring **GDocker** up to the same engineering, documentation, governance, and release automation standard established in `Diaszano/bearm`, adapted idiomatically for a native Swift 6 / macOS app.

Today the repository has a minimal README (missing recent features), a 14-line CI workflow, manual-only releases (`scripts/release.sh`), no code formatting/linting configuration, no git hooks, and no community/security documentation. Standardizing the repository makes it ready for public open-source distribution, repeatable automated releases to `Diaszano/homebrew-tap`, and consistent contributor workflows.

## Goals

- **Code Quality & Standardization:**
  - Add `.editorconfig`, `.swift-format` (Apple's official `swift format` bundled with Swift 6), and `.swiftlint.yml` (SwiftLint).
  - Format `Sources/` and `Tests/` consistently and resolve SwiftLint violations without changing runtime behavior.
  - Expand `Makefile` to mirror `bearm` (`all`, `build`, `app`, `run`, `test`, `fmt`, `fmt-check`, `lint`, `lint-fix`, `l10n-check`, `verify`, `clean`, `hooks`, `check-commits`).
  - Add `.githooks/commit-msg` and `scripts/verify-commits.sh` enforcing Conventional Commits v1.0.0.
  - Clean up `.gitignore` (ignore `.DS_Store`, `.code-review-graph/`, Xcode user state, etc.).
- **Documentation (Bilingual EN + PT-BR):**
  - Upgrade `README.md` and create `README.pt-BR.md` following the `bearm` layout (header, badges, language switcher, TOC, accurate up-to-date features including WebDAV Finder volume mounts, Rancher Desktop support, Catppuccin theme & menu bar popover, resizable resource tables, and MCP server).
  - Add `CONTRIBUTING.md`, `SECURITY.md`, and `CHANGELOG.md` (Keep a Changelog format, covering `v0.1.0` and `[Unreleased]`).
  - Add focused bilingual guides in `docs/`:
    - `docs/installation.md` & `docs/installation.pt-BR.md` (Homebrew 7 cask with `brew trust`, manual zip + quarantine removal, building from source, Keychain prompt explanation).
    - `docs/mcp.md` & `docs/mcp.pt-BR.md` (Claude Code HTTP, generic `mcpServers` JSON, Claude Desktop `--stdio` bridge, tool permission matrix, masking & approval timeouts).
    - `docs/security.md` & `docs/security.pt-BR.md` (localhost-only binding, Keychain bearer token, Allow/Ask/Deny policy, env masking, exec exact-command approval, WebDAV local mount model).
  - Add GitHub community templates: `.github/ISSUE_TEMPLATE/bug_report.yml`, `.github/ISSUE_TEMPLATE/feature_request.yml`, `.github/ISSUE_TEMPLATE/config.yml`, and `.github/PULL_REQUEST_TEMPLATE.md`.
- **CI/CD & Automated Homebrew Release:**
  - Upgrade `.github/workflows/ci.yml`: run `swift format lint` / `fmt-check`, `swiftlint --strict`, `python3 -I scripts/check_l10n.py .`, `swift test`, and `make app` build verification on `macos-15` (with SwiftPM dependency caching).
  - Add `.github/workflows/conventional-commits.yml`: validate PR titles (`amannn/action-semantic-pull-request`) and commit messages (`scripts/verify-commits.sh`).
  - Add `.github/workflows/security.yml`: CodeQL analysis for `swift` on PR, push to `main`, and weekly schedule.
  - Add `.github/workflows/release.yml`: triggered on `v*` tag push (and `workflow_dispatch` for dry-runs/re-runs). Builds universal `GDocker.app` (`arm64` + `x86_64`), packages `GDocker-<version>.zip` + `SHA256SUMS`, publishes the GitHub Release, generates the Homebrew 7 Cask (`postflight_steps` + `run "/usr/bin/xattr"` + `{{appdir}}`, `livecheck`, `zap`), and pushes `Casks/gdocker.rb` to `Diaszano/homebrew-tap` using `secrets.HOMEBREW_TAP_GITHUB_TOKEN`.
  - Keep `scripts/release.sh` working for local release packaging and DRY-share cask generation (`scripts/generate-cask.sh`) between `scripts/release.sh` and `release.yml`.

## Non-Goals

- Changing GDocker's runtime behavior, UI layout, or MCP protocol semantics.
- Code signing with an Apple Developer ID / notarization (remains ad-hoc signed with Homebrew 7 `postflight_steps` quarantine removal, as established in commit `420b3aa`).
- Modifying `Diaszano/homebrew-tap` directly from this PR (the tap receives `Casks/gdocker.rb` automatically on the next `v*` release once `HOMEBREW_TAP_GITHUB_TOKEN` is configured, or manually via `scripts/generate-cask.sh`).
- Restructuring `docs/superpowers/` (existing internal planning artifacts stay intact).

## Anti-Goals

- Breaking Homebrew 7 cask compatibility (`brew trust --cask` and `postflight_steps` with `{{appdir}}` must be preserved, not downgraded to legacy `postflight` syntax).
- Introducing noisy SwiftLint rules that force artificial rewrites or disable warnings across the codebase (`.swiftlint.yml` must be pragmatic and aligned with Swift 6 / SwiftUI idioms).
- Letting CI break when no Docker daemon is running on GitHub Actions macOS runners (Docker-dependent tests already skip gracefully when no daemon is present; this must remain intact).

## Constraints

- **Swift toolchain:** Swift 6.1+ (`Package.swift` uses `swift-tools-version:6.1`, macOS 14+ target). CI runs on `macos-15`.
- **Homebrew 7:** User runs Homebrew 7.x (`brew trust --cask diaszano/tap/gdocker`, `postflight_steps do run ... end`).
- **Localization check:** `scripts/check_l10n.py` inspects `Sources/GDocker` and `Sources/GDockerCore/Access/ToolCatalog.swift` with regexes — formatting changes must NOT break `check_l10n.py` (e.g., line-wrapping a `Text("...", bundle: .l10n)` call across lines must be verified against `check_l10n.py`).
- **GitHub Secret:** Automated tap updates in `release.yml` require `HOMEBREW_TAP_GITHUB_TOKEN` to be set in `Diaszano/gdocker` repository secrets.
- **Git Worktree Policy:** All implementation work will happen inside `.worktree/chore-standardize-repo` via Worktrunk (`wt`).

## Approaches Considered

1. **Full `bearm` alignment with native Swift 6 tooling only (`swift format`):** Zero external linter dependency in CI/local; lighter setup, but lacks richer static lint rules.
2. **Full `bearm` alignment + SwiftLint (Selected):** Combines Apple's official `swift format` (for formatting) with `SwiftLint` (for static analysis/style rules), mirroring `bearm`'s strict `golangci-lint` setup. Requires `swiftlint` installed locally (`brew install swiftlint`) and on CI runners.
3. **Minimal standardization (README, CI, release only):** Faster with smaller diff, but omits bilingual `docs/` guides, code formatting, and static linting.

**Decision:** The user selected **Approach 2** (Full `bearm` alignment + SwiftLint).

## Key Design Decisions (Builder Calls)

- **Formatter vs Linter split:** `swift format` handles all whitespace, indentation (4 spaces), line length (120 chars), and import sorting; `.swiftlint.yml` focuses on semantic/quality rules (disabling rules that conflict with `swift format` or SwiftUI DSL conventions like `multiple_closures_with_trailing_closure` or overly strict `line_length` conflicts).
- **Cask generator script:** Extract cask generation into `scripts/generate-cask.sh <version> <sha256> [output_path]` so `scripts/release.sh` and `.github/workflows/release.yml` produce byte-identical `Casks/gdocker.rb` files.
- **Release workflow resilience:** `release.yml` fails fast if `HOMEBREW_TAP_GITHUB_TOKEN` is missing (matching `bearm`), and supports `workflow_dispatch` with a `version` input for manual/re-run flexibility if needed.
- **GitHub Actions pinning:** Use standard major tags (`@v4`, `@v5`) or pinned SHAs consistently with `permissions:` scoped to least privilege on every workflow.
- **Makefile compatibility:** Keep `make app`, `make run`, `make test` working identically to before, and guard `DEVELOPER_DIR` with `?=` so CI runners with different Xcode paths aren't broken.
- **SwiftLint installation in CI:** `macos-15` GitHub runners either include `swiftlint` or install it via `brew install swiftlint` (check `command -v swiftlint || brew install swiftlint`).

## Verification Plan

Before claiming completion, all of the following must pass locally inside the worktree:
1. `make verify` (`fmt-check`, `lint`, `l10n-check`, `test`).
2. `make app` (builds `build/GDocker.app` cleanly).
3. `scripts/generate-cask.sh 0.1.0 <dummy-sha>` produces valid Ruby syntax (`ruby -c`).
4. `scripts/verify-commits.sh origin/main HEAD` passes on all new commits.
5. `git status` is clean with `.DS_Store` untracked/ignored.
