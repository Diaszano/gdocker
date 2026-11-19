# Contributing to GDocker

Thank you for contributing to GDocker!

## Prerequisites

- macOS 14 (Sonoma) or newer;
- Xcode 16.4 or newer (Swift 6.1+ with bundled `swift format`);
- [SwiftLint](https://github.com/realm/SwiftLint) (`brew install swiftlint`);
- Python 3 (for `scripts/check_l10n.py`);
- Git and `make`.

## Setup

Enable the repository commit hook right after cloning:

```sh
make hooks
```

## Workflow

1. Create a conventional English branch name such as `feat/volume-search`, `fix/socket-discovery`, or `docs/mcp-guide`.
2. Write a failing test for each behavior change and confirm it fails for the right reason.
3. Implement the smallest change that passes the test.
4. Format and run the full verification suite:

   ```sh
   make fmt
   make verify
   make app
   ```

5. Keep each task in focused Conventional Commits.

## Available `Makefile` Targets

| Target | Description |
| --- | --- |
| `make verify` | Run `fmt-check`, `lint`, `l10n-check`, and `test` |
| `make fmt` | Format all Swift files using `.swift-format` |
| `make fmt-check` | Verify formatting without modifying files |
| `make lint` | Run `swiftlint lint --strict` using `.swiftlint.yml` |
| `make lint-fix` | Apply safe SwiftLint autofixes |
| `make l10n-check` | Verify all UI strings exist in `Localizable.xcstrings` (`en` and `pt-BR`) |
| `make test` | Run `swift test` (Docker-dependent tests skip if no daemon is running) |
| `make app` | Build `build/GDocker.app` (release) |
| `make run` | Build and launch `build/GDocker.app` |
| `make hooks` | Configure `core.hooksPath` to `.githooks` |
| `make check-commits` | Validate commits against Conventional Commits |
| `make clean` | Remove `build/` and `.build/` |

## Localization Rules

Every user-facing string in `Sources/GDocker` and every tool title in `Sources/GDockerCore/Access/ToolCatalog.swift` must have both `en` and `pt-BR` entries in `Sources/GDocker/Resources/Localizable.xcstrings`.

- Interpolate `String` values rather than `Int` values in `String(localized:)` so numbers like ports are not locale-formatted (e.g., `7.391` in `pt-BR`).
- Run `make l10n-check` to confirm there are zero missing, unknown, or unused keys.

## Conventional Commits Specification

All commit messages and Pull Request titles must follow [Conventional Commits v1.0.0](https://www.conventionalcommits.org/):

```text
<type>(<optional scope>): <description>
```

Allowed types:

- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation only changes
- `style`: Formatting, whitespace, or lint fixes (no logic changes)
- `refactor`: Code changes that neither fix a bug nor add a feature
- `perf`: Performance improvements
- `test`: Adding or correcting tests
- `build`: Build system, packaging, or dependency changes
- `ci`: CI/CD configuration and scripts
- `chore`: Maintenance tasks that do not modify `Sources/` or `Tests/`
- `revert`: Reverts a previous commit

Append `!` before the colon (e.g., `feat(mcp)!: change default port`) or include `BREAKING CHANGE:` in the commit footer for breaking changes.

Examples:

```text
feat(docker): support Rancher Desktop socket paths
feat(volumes): open Docker volumes in Finder via WebDAV
fix(mcp): reject non-local Host headers
docs(mcp): document Claude Desktop stdio bridge
test(core): cover container status filtering
```
