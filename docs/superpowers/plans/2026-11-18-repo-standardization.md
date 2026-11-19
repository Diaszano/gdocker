# GDocker Repository Standardization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align GDocker with the `Diaszano/bearm` repository standard—adding `swift format` + `SwiftLint`, Conventional Commits hooks, full CI/CD + automated Homebrew 7 tap releases, community templates, and bilingual (EN + PT-BR) documentation.

**Architecture:** All work is executed in an isolated Worktrunk worktree (`.worktree/chore-standardize-repo`). Tooling is split cleanly between `swift format` (formatting), `SwiftLint` (static analysis), and `scripts/generate-cask.sh` (single source of truth for Homebrew 7 Cask generation shared by `scripts/release.sh` and `.github/workflows/release.yml`).

**Tech Stack:** Swift 6.1+ (`swift format`, SwiftPM), SwiftLint, Homebrew 7 Cask, GitHub Actions (`macos-15`, `ubuntu-latest`, CodeQL), Python 3 (`scripts/check_l10n.py`), POSIX `/bin/sh`.

**Spec:** `docs/superpowers/specs/2026-11-18-repo-standardization-design.md`

## Global Constraints

- Swift toolchain floor: `swift-tools-version:6.1`, macOS 14+ (`LSMinimumSystemVersion` 14.0), CI on `macos-15`.
- Homebrew 7 syntax MUST be preserved verbatim: `brew trust --cask diaszano/tap/gdocker`, `postflight_steps do run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/GDocker.app"] end`.
- `python3 -I scripts/check_l10n.py .` MUST exit 0 after any Swift formatting or linting edits.
- `swift test` MUST pass even when no Docker daemon is running locally or in CI.
- All commits MUST follow Conventional Commits v1.0.0 (`scripts/verify-commits.sh`).
- All implementation changes MUST be made inside `.worktree/chore-standardize-repo` created via `WORKTRUNK_WORKTREE_PATH='{{ repo_path }}/.worktree/{{ branch | sanitize }}' wt switch --create chore/standardize-repo`.

## Review Focus

- `swift format` line-wrapping a `Text("...", bundle: .l10n)` or `String(localized: "...")` call across lines could break `scripts/check_l10n.py` regexes — pinned in Task 3 verification.
- `DEVELOPER_DIR` hardcoded in `Makefile` could fail on GitHub Actions `macos-15` runners if Xcode is installed at a versioned path — pinned in Task 2 (`DEVELOPER_DIR ?=` or conditional only when default Xcode path exists).
- `release.yml` pushing `Casks/gdocker.rb` to `Diaszano/homebrew-tap` must fail fast with a clear error when `HOMEBREW_TAP_GITHUB_TOKEN` is unset — pinned in Task 5.
- `SwiftLint` rules conflicting with `swift format` (e.g., `opening_brace`, `trailing_comma`, `indentation_width`) would cause an unfixable loop between `make fmt` and `make lint` — pinned in Task 2 & Task 3 (`make fmt && make fmt-check && make lint` must all pass together).
- `.githooks/commit-msg` must be executable (`chmod +x`) and support worktrees where `git rev-parse --show-toplevel` resolves to the worktree root — pinned in Task 1.

---

### Task 1: Worktree Setup, Git Hygiene, EditorConfig & Commit Hooks

**Files:**
- Modify: `.gitignore`
- Create: `.editorconfig`
- Create: `.githooks/commit-msg`
- Create: `scripts/verify-commits.sh`

**Interfaces:**
- Produces:
  - Executable `.githooks/commit-msg <commit_msg_file>` validating Conventional Commits v1.0.0.
  - Executable `scripts/verify-commits.sh [base_ref] [head_ref]` validating a commit range.

- [ ] **Step 1: Create isolated worktree via Worktrunk**

Run:
```bash
WORKTRUNK_WORKTREE_PATH='{{ repo_path }}/.worktree/{{ branch | sanitize }}' wt switch --create chore/standardize-repo
```
Verify with `git worktree list` that `.worktree/chore-standardize-repo` exists and is on branch `chore/standardize-repo`. Copy the spec and plan into the worktree (or commit them cleanly on the branch).

- [ ] **Step 2: Update `.gitignore`**

Ensure `.gitignore` ignores:
- `.worktrees/`, `.worktree/`, `.superpowers/`, `.claude/`, `.serena/`, `.code-review-graph/`
- `.build/`, `build/`, `*.app`, `.swiftpm/`, `*.xcodeproj`, `xcuserdata/`
- `.DS_Store`

- [ ] **Step 3: Create `.editorconfig`**

Configure `root = true`, `charset = utf-8`, `end_of_line = lf`, `insert_final_newline = true`, `trim_trailing_whitespace = true`, 4-space indentation for `*.swift`, 2-space indentation for `*.{yml,yaml,json,rb,md}`, tab indentation for `Makefile`.

- [ ] **Step 4: Create `.githooks/commit-msg` and `scripts/verify-commits.sh`**

Port both scripts from `Diaszano/bearm` verbatim (updating examples in `.githooks/commit-msg` to GDocker scopes like `docker`, `mcp`, `ui`, `volumes`), and `chmod +x .githooks/commit-msg scripts/verify-commits.sh`.

- [ ] **Step 5: Verify hook and commit validator**

Run:
```bash
printf "feat(mcp): add tool\n" > /tmp/msg_ok && sh .githooks/commit-msg /tmp/msg_ok
printf "bad commit\n" > /tmp/msg_bad && ! sh .githooks/commit-msg /tmp/msg_bad
rm -f /tmp/msg_ok /tmp/msg_bad
```
Expected: valid message exits 0; invalid message exits 1.

- [ ] **Step 6: Commit**

```bash
git add .gitignore .editorconfig .githooks/commit-msg scripts/verify-commits.sh
git commit -m "chore: add editorconfig, gitignore rules, and conventional commit hooks"
```

---

### Task 2: Swift Format, SwiftLint Configuration & Standardized Makefile

**Files:**
- Create: `.swift-format`
- Create: `.swiftlint.yml`
- Modify: `Makefile`

**Interfaces:**
- Consumes: `.githooks/commit-msg` and `scripts/verify-commits.sh` from Task 1.
- Produces:
  - `make fmt`, `make fmt-check`, `make lint`, `make lint-fix`, `make l10n-check`, `make test`, `make build`, `make app`, `make run`, `make verify`, `make clean`, `make hooks`, `make check-commits`, `make all`.

- [ ] **Step 1: Ensure `swiftlint` is installed locally**

Run: `command -v swiftlint || brew install swiftlint`
Expected: `swiftlint version` outputs an installed version.

- [ ] **Step 2: Create `.swift-format`**

Configure official Swift 6 `swift-format` JSON with `version: 1`, `lineLength: 120`, `indentation: { spaces: 4 }`, `tabWidth: 4`, `respectsExistingLineBreaks: true`, and `OrderedImports: true` (keeping rules compatible with `scripts/check_l10n.py`).

- [ ] **Step 3: Create `.swiftlint.yml`**

Configure SwiftLint targeting `Sources` and `Tests`, excluding `.build`, `build`, `.worktree`, `.worktrees`, and `Sources/GDocker/Resources`. Disable rules that conflict with `swift format` or SwiftUI idioms (`line_length` managed by `swift format` or aligned at warning 140 / error 180, `multiple_closures_with_trailing_closure`, `trailing_comma`, `opening_brace`, `vertical_parameter_alignment`, `identifier_name` tuned for short loop/math vars like `x`, `y`, `id`, `fd`, `ip`, `ok`). Enable useful opt-in rules (`empty_count`, `first_where`, `sorted_first_last`, `redundant_nil_coalescing`).

- [ ] **Step 4: Standardize `Makefile`**

Update `Makefile` to mirror `bearm`:
- Only set `DEVELOPER_DIR` if not already set and `/Applications/Xcode.app/Contents/Developer` exists (so CI runners are never broken).
- Keep `app`, `run`, `test` behavior intact.
- Add `all`, `build`, `fmt`, `fmt-check`, `lint`, `lint-fix`, `l10n-check`, `verify` (`fmt-check lint l10n-check test`), `clean`, `hooks` (pointing `core.hooksPath` to `.githooks`), and `check-commits`.

- [ ] **Step 5: Verify `Makefile` targets resolve**

Run: `make hooks && make l10n-check`
Expected: hooks configured cleanly and `check_l10n.py` exits 0.

- [ ] **Step 6: Commit**

```bash
git add .swift-format .swiftlint.yml Makefile
git commit -m "chore: configure swift-format, swiftlint, and standardized Makefile"
```

---

### Task 3: Format Codebase & Resolve SwiftLint Violations

**Files:**
- Modify: Swift files under `Sources/` and `Tests/` as required by `swift format` and `swiftlint --strict`.

**Interfaces:**
- Consumes: `.swift-format`, `.swiftlint.yml`, `Makefile` from Task 2.
- Produces: Cleanly formatted, zero-warning Swift codebase passing `make verify`.

- [ ] **Step 1: Run `make fmt`**

Run: `make fmt`
Verify `make fmt-check` exits 0 immediately after.

- [ ] **Step 2: Run `make lint` and inspect violations**

Run: `make lint`
Capture all reported SwiftLint warnings/errors.

- [ ] **Step 3: Fix SwiftLint violations cleanly**

Run `make lint-fix` for safe autofixes, then fix remaining genuine issues manually (avoiding any runtime behavior change) and tune `.swiftlint.yml` only where a rule is genuinely noisy for SwiftUI/NIO idioms.

- [ ] **Step 4: Run full verification**

Run: `make fmt && make verify`
Expected: `fmt-check`, `lint` (`swiftlint --strict`), `l10n-check` (`check_l10n.py`), and `test` (`swift test`) ALL pass with exit code 0.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests .swiftlint.yml
git commit -m "style: format codebase with swift-format and resolve SwiftLint issues"
```

---

### Task 4: Homebrew 7 Cask Generator & Release Script

**Files:**
- Create: `scripts/generate-cask.sh`
- Modify: `scripts/release.sh`

**Interfaces:**
- Produces:
  - Executable `scripts/generate-cask.sh <version> <sha256> [output_path]` emitting a valid Homebrew 7 Cask (`postflight_steps`, `{{appdir}}`, `depends_on macos: :sonoma`, `livecheck`, `zap`).

- [ ] **Step 1: Create `scripts/generate-cask.sh`**

Accept `<version> <sha256> [output_path]` (defaults to stdout when `output_path` is omitted). Strip leading `v` if passed. Emit the Homebrew 7 Cask with:
- Header comment `# This file was generated by GDocker release automation. DO NOT EDIT.`
- `version "<version>"`, `sha256 "<sha256>"`
- `url "https://github.com/Diaszano/gdocker/releases/download/v#{version}/GDocker-#{version}.zip"`
- `name "GDocker"`, `desc "Native macOS Docker GUI with a built-in MCP server for AI clients"`, `homepage "https://github.com/Diaszano/gdocker"`
- `livecheck { url :url; strategy :github_latest }`
- `depends_on macos: :sonoma`
- `app "GDocker.app"`
- `postflight_steps { run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/GDocker.app"] }`
- `zap trash: ["~/Library/Application Support/GDocker", "~/Library/Preferences/com.diaszano.gdocker.plist"]`

`chmod +x scripts/generate-cask.sh`.

- [ ] **Step 2: Refactor `scripts/release.sh`**

Update `scripts/release.sh` to:
- Strip optional leading `v` from version argument.
- Generate `build/GDocker-<version>.zip` and `build/SHA256SUMS`.
- Call `./scripts/generate-cask.sh "$version" "$sha" build/gdocker.rb`.
- Print updated next-step instructions.

- [ ] **Step 3: Verify Cask syntax and script output**

Run:
```bash
./scripts/generate-cask.sh 0.1.0 0000000000000000000000000000000000000000000000000000000000000000 /tmp/gdocker.rb
ruby -c /tmp/gdocker.rb
grep -q 'postflight_steps' /tmp/gdocker.rb && grep -q '{{appdir}}/GDocker.app' /tmp/gdocker.rb
rm -f /tmp/gdocker.rb
```
Expected: `Syntax OK` and both Homebrew 7 markers present.

- [ ] **Step 4: Commit**

```bash
git add scripts/generate-cask.sh scripts/release.sh
git commit -m "build: extract Homebrew 7 cask generator and add SHA256SUMS"
```

---

### Task 5: GitHub Workflows & Community Templates

**Files:**
- Modify: `.github/workflows/ci.yml`
- Create: `.github/workflows/conventional-commits.yml`
- Create: `.github/workflows/security.yml`
- Create: `.github/workflows/release.yml`
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Create: `.github/ISSUE_TEMPLATE/feature_request.yml`
- Create: `.github/ISSUE_TEMPLATE/config.yml`
- Create: `.github/PULL_REQUEST_TEMPLATE.md`

**Interfaces:**
- Consumes: `Makefile` targets (`fmt-check`, `lint`, `l10n-check`, `test`, `app`), `scripts/verify-commits.sh`, `scripts/generate-cask.sh`.
- Produces: Complete CI, commit-lint, CodeQL security, and automated universal release + Homebrew tap publishing workflows.

- [ ] **Step 1: Upgrade `.github/workflows/ci.yml`**

Run on `push` (all branches) and `pull_request` with `permissions: contents: read` on `macos-15`:
- Cache `.build` keyed by `Package.resolved`.
- Ensure `swiftlint` is available (`command -v swiftlint || brew install swiftlint`).
- Run `make fmt-check`, `make lint`, `make l10n-check`, `make test`, and `make app`.

- [ ] **Step 2: Create `.github/workflows/conventional-commits.yml`**

Mirror `Diaszano/bearm`'s `conventional-commits.yml`:
- `lint-pr-title` job using `amannn/action-semantic-pull-request@v5`.
- `lint-commits` job running `./scripts/verify-commits.sh`.

- [ ] **Step 3: Create `.github/workflows/security.yml`**

Mirror `Diaszano/bearm`'s `security.yml` adapted for Swift:
- Triggers on `pull_request`, `push` to `main`, and weekly `cron: "17 8 * * 1"`.
- Runs `github/codeql-action/init@v3`, `autobuild@v3`, `analyze@v3` on `macos-15` with `languages: swift`.

- [ ] **Step 4: Create `.github/workflows/release.yml`**

Triggers on `push: tags: ["v*"]` and `workflow_dispatch` (with `version` input):
- Runs on `macos-15`, `permissions: contents: write`.
- Fails fast if `secrets.HOMEBREW_TAP_GITHUB_TOKEN` is missing.
- Runs `make verify`.
- Updates `scripts/Info.plist` version via `PlistBuddy`, builds universal `make app SWIFT_FLAGS="--arch arm64 --arch x86_64"`, zips `build/GDocker-<version>.zip`, generates `build/SHA256SUMS`.
- Creates/updates GitHub Release via `gh release create` with `--generate-notes` and uploads zip + `SHA256SUMS`.
- Checks out `Diaszano/homebrew-tap` using `HOMEBREW_TAP_GITHUB_TOKEN`, generates `Casks/gdocker.rb` via `./scripts/generate-cask.sh`, commits `chore(cask): update gdocker to v<version>`, and pushes to `main`.

- [ ] **Step 5: Create Issue & PR templates**

Create `.github/ISSUE_TEMPLATE/bug_report.yml` (macOS version, GDocker version, Docker runtime: Docker Desktop / OrbStack / Colima / Rancher Desktop, steps to reproduce), `feature_request.yml`, `config.yml` (blank issues disabled + link to Security Advisories), and `.github/PULL_REQUEST_TEMPLATE.md` (summary, checklist referencing `make verify` and Conventional Commits).

- [ ] **Step 6: Validate all YAML files**

Run:
```bash
python3 -c '
import glob, sys, yaml
for p in sorted(glob.glob(".github/**/*.yml", recursive=True)):
    yaml.safe_load(open(p))
    print("OK:", p)
'
```
Expected: all workflow and template YAML files parse cleanly.

- [ ] **Step 7: Commit**

```bash
git add .github/
git commit -m "ci: add CI, release, security, conventional commits workflows and templates"
```

---

### Task 6: Bilingual Documentation (`README`, Governance & `docs/`)

**Files:**
- Modify: `README.md`
- Create: `README.pt-BR.md`
- Create: `CONTRIBUTING.md`
- Create: `SECURITY.md`
- Create: `CHANGELOG.md`
- Create: `docs/installation.md`
- Create: `docs/installation.pt-BR.md`
- Create: `docs/mcp.md`
- Create: `docs/mcp.pt-BR.md`
- Create: `docs/security.md`
- Create: `docs/security.pt-BR.md`

**Interfaces:**
- Consumes: Final `Makefile` targets, Homebrew 7 install commands, and accurate feature inventory from `Sources/`.
- Produces: Complete `bearm`-aligned bilingual documentation suite.

- [ ] **Step 1: Rewrite `README.md` and create `README.pt-BR.md`**

Follow `Diaszano/bearm` structure:
- Centered header, tagline, badges (Swift 6.1+, macOS 14+, License MIT, CI status, Conventional Commits, PRs Welcome), EN/PT-BR language switcher.
- Table of Contents.
- Core Features (Containers grouped by Compose project, live logs/stats/inspect/env/interactive SwiftTerm terminal, Images/Volumes with WebDAV Finder mount/Networks/Compose, Catppuccin theme & menu bar popover, RuntimeCard with CPU/memory/disk bars, Docker Desktop/OrbStack/Colima/Rancher Desktop support, built-in MCP server with Allow/Ask/Deny approvals & AI activity log).
- Installation (Homebrew 7 with `brew trust --cask diaszano/tap/gdocker`, manual zip, build from source).
- Connecting AI clients (Claude Code, generic `mcpServers` JSON, Claude Desktop `--stdio`).
- Links to `docs/` guides, `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`, `LICENSE`.

- [ ] **Step 2: Create `CONTRIBUTING.md`, `SECURITY.md`, and `CHANGELOG.md`**

Align structure and tone with `Diaszano/bearm`:
- `CONTRIBUTING.md`: prerequisites (macOS 14+, Xcode 16.4+ / Swift 6.1+, `swiftlint`, `make`), workflow (`make hooks`, `make verify`, `make app`), Conventional Commits spec, localization rules (`Localizable.xcstrings` + `make l10n-check`), PR guidelines.
- `SECURITY.md`: supported versions, private GitHub Security Advisory reporting, security scope (localhost MCP server binding, Keychain bearer token, permission/approval enforcement, env masking, WebDAV local mount).
- `CHANGELOG.md`: Keep a Changelog format with `[Unreleased]` (all features since `v0.1.0`: Rancher Desktop, WebDAV Finder mounts, Catppuccin popover, resizable tables, repo standardization) and `[0.1.0]`.

- [ ] **Step 3: Create bilingual guides in `docs/`**

- `docs/installation.md` & `docs/installation.pt-BR.md`
- `docs/mcp.md` & `docs/mcp.pt-BR.md`
- `docs/security.md` & `docs/security.pt-BR.md`

- [ ] **Step 4: Commit**

```bash
git add README.md README.pt-BR.md CONTRIBUTING.md SECURITY.md CHANGELOG.md docs/installation*.md docs/mcp*.md docs/security*.md
git commit -m "docs: add bilingual README, guides, changelog, contributing, and security policy"
```

---

### Final Branch Verification

- [ ] **Step 1: Run complete verification suite**

Run inside `.worktree/chore-standardize-repo`:
```bash
make verify
make app
./scripts/verify-commits.sh origin/main HEAD
git status
```
Expected: `fmt-check`, `lint`, `l10n-check`, `test`, `app`, and `verify-commits.sh` all pass with exit code 0, and `git status` is clean.
