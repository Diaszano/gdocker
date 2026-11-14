# GDocker UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the redesigned Penpot UI (`DockerUI`: screens `01`–`04` and `Componentes`/`Logos`) in the GDocker macOS SwiftUI app, including service logos, tabular containers view with filters and inline actions, collapsible sidebar & inspector, runtime resource card, status bar, and redesigned AI Activity, Permissions, and Approval views.

**Architecture:** Keep `GDockerCore` and `GDockerMCP` decoupled from SwiftUI; extend `GDockerCore` only where new data is needed (`ContainerSummary.sizeRw`, `StatusFilter` helpers). Build reusable Penpot component primitives under `Sources/GDocker/Views/Components/` backed by the existing `Color.ctp` / `Flavor` Catppuccin tokens, then upgrade each screen (`MainWindow`, `ContainerList`, `ContainerDetail`, `ActivityView`, `PermissionsView`, `ApprovalView`).

**Tech Stack:** Swift 6.1, SwiftUI (macOS 14+), Observation (`@Observable`), Swift Testing (`import Testing`), Catppuccin (`Sources/GDocker/Settings/Catppuccin.swift`).

**Spec:** Penpot file `DockerUI` (pages `Telas`, `Componentes`, `Logos`; 9 screens `01`–`04` across Catppuccin Macchiato, Latte, Frappé, Mocha).

## Global Constraints

- Minimum platform: macOS 14.0 (`Package.swift`: `platforms: [.macOS(.v14)]`), Swift 6.1.
- Colors must use `Color.ctp.*` / `NSColor.ctp(...)` from `Sources/GDocker/Settings/Catppuccin.swift` so all 4 Catppuccin flavors (`latte`, `frappe`, `macchiato`, `mocha`) and WCAG contrast adjustments apply automatically.
- All user-facing strings must use `bundle: .l10n` (`Text("...", bundle: .l10n)` or `String(localized: "...", bundle: .l10n)`) and exist in `Sources/GDocker/Resources/Localizable.xcstrings`, verified by `python3 scripts/check_l10n.py`.
- Run tests with `make test` (sets `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`) and build the app bundle with `make app`.

## Review Focus

- **Unknown or registry-prefixed image names** (e.g., `ghcr.io/org/postgres:16-alpine`, `mailhog/mailhog`, empty string): `ServiceLogo` must normalize registry/tag and fall back cleanly to the generic container icon without crashing or returning blank space.
- **Missing container size (`sizeRw == nil`)**: Docker's `/containers/json` only returns `SizeRw` when `size=true` is passed (and some states omit it); UI must format `nil` as `"—"` rather than `"0 B"` or crashing.
- **Collapsed sidebar & inspector state**: Toggling the sidebar (`220px` <-> `60px`) or hiding the right-hand inspector (`01c`) must preserve selection and not break keyboard navigation or minimum window width.
- **Pending approval count synchronization**: The `"N aguardando aprovação"` pill appears in the bottom status bar, `PermissionsView` header, and `ActivityView` KPI card; when `ApprovalModel.pending.count == 0`, the pill hides cleanly and `ApprovalView` updates immediately.
- **Environment masking toggle in `PermissionsView`**: Toggling `"Mascarar variáveis de ambiente"` from the header banner must update the persisted setting / MCP masking state without restarting the MCP server.

---

### Task 1: Docker Service Logo Catalog & View

**Files:**
- Create: `Sources/GDocker/Views/Components/ServiceLogo.swift`
- Test: `Tests/GDockerCoreTests/ServiceLogoTests.swift` (or pure-Swift matcher in `GDockerCore` if tested in `GDockerCoreTests`)

**Interfaces:**
- Produces:
  - `enum ServiceKind: String, CaseIterable, Sendable` (in `GDockerCore` or `GDocker`)
  - `ServiceKind.from(image: String) -> ServiceKind`
  - `struct ServiceLogo: View` taking `image: String, size: CGFloat = 28`

- [ ] **Step 1: Write the failing test**

Create `Tests/GDockerCoreTests/ServiceLogoTests.swift`:
```swift
import Testing
@testable import GDockerCore

@Test func mapsCommonDockerImagesToServiceKind() {
    #expect(ServiceKind.from(image: "postgres:16") == .postgres)
    #expect(ServiceKind.from(image: "ghcr.io/bitnami/redis:7-alpine") == .redis)
    #expect(ServiceKind.from(image: "nginx:1.27") == .nginx)
    #expect(ServiceKind.from(image: "rabbitmq:3-management") == .rabbitmq)
    #expect(ServiceKind.from(image: "mongo:7") == .mongodb)
    #expect(ServiceKind.from(image: "mailhog/mailhog") == .generic)
    #expect(ServiceKind.from(image: "") == .generic)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL with `cannot find 'ServiceKind' in scope`.

- [ ] **Step 3: Implement `ServiceKind` in `GDockerCore` and `ServiceLogo` in `GDocker`**

Add `Sources/GDockerCore/Docker/ServiceKind.swift` with `ServiceKind.from(image:)` stripping registry host (`/`), tag (`:`), and digest (`@sha256:`), then matching known service names (`postgres`, `redis`, `nginx`, `rabbitmq`, `mongo`, `mysql`, `mariadb`, `elasticsearch`, `kafka`, `traefik`, `caddy`, `grafana`, `prometheus`, `minio`, etc.) with `.generic` fallback.
Add `Sources/GDocker/Views/Components/ServiceLogo.swift` rendering a centered `28x28` rounded badge (`Color.ctp.hover` / brand tint) with bundled vector asset or SF Symbol fallback.

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: PASS for `ServiceLogoTests`.

- [ ] **Step 5: Commit**

```bash
git add Sources/GDockerCore/Docker/ServiceKind.swift Sources/GDocker/Views/Components/ServiceLogo.swift Tests/GDockerCoreTests/ServiceLogoTests.swift
git commit -m "feat(ui): add ServiceKind matcher and ServiceLogo component"
```

---

### Task 2: Container Size (`sizeRw`) and Status Filtering

**Files:**
- Modify: `Sources/GDockerCore/Docker/Models.swift`
- Modify: `Sources/GDockerCore/Docker/DockerOperations.swift` (pass `size=true` on `/containers/json`)
- Modify: `Sources/GDocker/Stores/ContainersStore.swift`
- Test: `Tests/GDockerCoreTests/ModelsTests.swift`

**Interfaces:**
- Consumes: `ContainerSummary`, `StatusKind`
- Produces:
  - `ContainerSummary.sizeRw: Int64?` (decoded from `"SizeRw"`)
  - `enum ContainerStatusFilter: String, CaseIterable` (`all`, `running`, `stopped`, `failed`)
  - `ContainersStore.statusFilter: ContainerStatusFilter`
  - `ContainersStore.selectedIDs: Set<String>`

- [ ] **Step 1: Write the failing test**

In `Tests/GDockerCoreTests/ModelsTests.swift`, add tests verifying:
- `ContainerSummary` decodes `"SizeRw": 222298112` into `sizeRw == 222298112` and handles missing `"SizeRw"` as `nil`.
- Filtering `[ContainerSummary]` by `ContainerStatusFilter` (`all`, `running`, `stopped`, `failed`) returns the expected subset.

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL because `sizeRw` and `ContainerStatusFilter` do not exist yet.

- [ ] **Step 3: Implement `sizeRw`, `size=true` query param, and `ContainerStatusFilter`**

- Update `ContainerSummary` in `Sources/GDockerCore/Docker/Models.swift` to decode `sizeRw: Int64?` from `"SizeRw"`.
- Update `listContainers()` in `Sources/GDockerCore/Docker/DockerOperations.swift` to request `/containers/json?all=true&size=true`.
- Add `ContainerStatusFilter` and `selectedIDs` to `Sources/GDocker/Stores/ContainersStore.swift`, and apply `statusFilter` inside `visibleGroups`.

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/GDockerCore/Docker/Models.swift Sources/GDockerCore/Docker/DockerOperations.swift Sources/GDocker/Stores/ContainersStore.swift Tests/GDockerCoreTests/ModelsTests.swift
git commit -m "feat(core): decode container SizeRw and add status filtering"
```

---

### Task 3: Reusable Penpot Design System Components

**Files:**
- Create: `Sources/GDocker/Views/Components/StatusBadge.swift`
- Create: `Sources/GDocker/Views/Components/FilterPill.swift`
- Create: `Sources/GDocker/Views/Components/IconActionButton.swift`
- Create: `Sources/GDocker/Views/Components/TabStrip.swift`

**Interfaces:**
- Produces:
  - `StatusBadge(kind: StatusKind, label: LocalizedStringKey)` (pill with colored dot + tinted background matching Penpot `Status`)
  - `FilterPill(title: LocalizedStringKey, dotColor: Color?, isSelected: Bool, action: () -> Void)` (matching Penpot `Filtro`)
  - `IconActionButton(systemImage: String, role: ButtonRole? = nil, help: LocalizedStringKey, action: () -> Void)` (28×28 bordered square icon button matching Penpot `Botão ícone`)
  - `TabStrip(selection: Binding<Tab>, tabs: [(Tab, LocalizedStringKey, String)])` (icon + label + bottom accent bar matching Penpot `Aba`)

- [ ] **Step 1: Create the 4 component files**

Implement each view in `Sources/GDocker/Views/Components/` using `Color.ctp.*` tokens and `bundle: .l10n`.

- [ ] **Step 2: Verify compilation**

Run: `make test`
Expected: Compiles and all existing tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/GDocker/Views/Components/
git commit -m "feat(ui): add StatusBadge, FilterPill, IconActionButton, and TabStrip components"
```

---

### Task 4: Collapsible Sidebar, Runtime Resource Card, and Bottom Status Bar

**Files:**
- Create: `Sources/GDocker/Views/Components/RuntimeCard.swift`
- Create: `Sources/GDocker/Views/Components/StatusBar.swift`
- Modify: `Sources/GDocker/Views/MainWindow.swift`

**Interfaces:**
- Consumes: `ContainersStore`, `McpController`, `ApprovalModel`
- Produces:
  - `MainWindow` with collapsible sidebar (`sidebarCollapsed: Bool`, 220px expanded vs 60px icon-only rail as in `01d`/`02d`/`03d`)
  - `RuntimeCard` at bottom of sidebar showing runtime status, running/total containers, CPU count, Memory & Disk progress bars (or compact badge when collapsed)
  - `StatusBar` at bottom of main content showing runtime status, running count, memory summary, MCP active/clients count, and clickable `"N aguardando aprovação"` pill when `mcp.approvalModel.pending.count > 0`

- [ ] **Step 1: Implement `RuntimeCard` and `StatusBar`**

Create `RuntimeCard.swift` and `StatusBar.swift` using `Color.ctp.*` tokens. Wire `StatusBar`'s approval pill to open/focus `ApprovalPanelController` (or trigger `mcp.showApprovals()`).

- [ ] **Step 2: Update `MainWindow.swift` with collapsible sidebar and `StatusBar`**

Replace default `NavigationSplitView` sidebar with a custom 220px / 60px collapsible rail (`sidebarCollapsed` toggle button in sidebar header), `RuntimeCard` at the bottom, and `StatusBar` below the detail content.

- [ ] **Step 3: Build & test**

Run: `make test`
Expected: Compiles and tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/GDocker/Views/Components/RuntimeCard.swift Sources/GDocker/Views/Components/StatusBar.swift Sources/GDocker/Views/MainWindow.swift
git commit -m "feat(ui): add collapsible sidebar, RuntimeCard, and bottom StatusBar"
```

---

### Task 5: Tabular Containers View, Context Menu (`⋯`), and Collapsible Inspector (`01`, `01b`, `01c`)

**Files:**
- Modify: `Sources/GDocker/Views/ContainerList.swift`
- Modify: `Sources/GDocker/Views/MainWindow.swift` (inspector visibility toggle `showInspector`)

**Interfaces:**
- Consumes: `ContainersStore`, `ServiceLogo`, `StatusBadge`, `FilterPill`, `IconActionButton`
- Produces:
  - Header with title, `FilterPill` row (`Todos`, `Rodando`, `Parados`, `Falhos`), search field (`⌘K`), and inspector toggle button (`01c`).
  - Table header (`NOME`, `ESTADO`, `PORTAS`, `TAMANHO`, `AÇÕES`) + Compose group header (`project · Compose · X de Y rodando`).
  - Container row (`Linha container`) with checkbox, `ServiceLogo`, name + image, `StatusBadge`, formatted ports, formatted `sizeRw` (`ByteCountFormatter` or `"—"`), and inline `IconActionButton`s (`Restart`, `Stop/Start`, `Remove`, `⋯` menu with `Logs`, `Stats`, `Inspect`, `Env`, `Terminal` that opens the inspector on the chosen tab).

- [ ] **Step 1: Upgrade `ContainerList.swift` to the tabular layout**

Implement the header bar, filter pills, column headers, Compose group headers, and `ContainerRow` with inline actions + `Menu` for `⋯`.

- [ ] **Step 2: Wire inspector toggle and tab selection in `MainWindow.swift`**

Add `@State private var showInspector = true` and `@State private var inspectorTab = ContainerDetail.Tab.logs` so clicking `⋯ -> Stats` (or toggling the inspector button) opens/closes the right-hand `ContainerDetail` panel cleanly (`01c`).

- [ ] **Step 3: Build & test**

Run: `make test`
Expected: Compiles and tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/GDocker/Views/ContainerList.swift Sources/GDocker/Views/MainWindow.swift
git commit -m "feat(ui): redesign Containers list as tabular view with filters and actions"
```

---

### Task 6: Inspector Header & Tab Strip Polish (`ContainerDetail.swift`, `LogsTab.swift`)

**Files:**
- Modify: `Sources/GDocker/Views/ContainerDetail.swift`
- Modify: `Sources/GDocker/Views/LogsTab.swift`

**Interfaces:**
- Consumes: `TabStrip`, `StatusBadge`, `StatusDot`
- Produces:
  - `ContainerDetail(container: ContainerSummary, selectedTab: Binding<Tab>, onClose: () -> Void)` with Penpot `01` header (`StatusDot`, container name, close panel button, `image · ports`, `StatusBadge`, uptime) and `TabStrip`.
  - `LogsTab` toolbar matching Penpot `01` (`Filtrar logs...` search input + `Seguir` toggle pill).

- [ ] **Step 1: Update `ContainerDetail.swift` header and replace segmented `Picker` with `TabStrip`**
- [ ] **Step 2: Polish `LogsTab.swift` filter bar and `Seguir` pill**
- [ ] **Step 3: Build & test**

Run: `make test`
Expected: Compiles and tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/GDocker/Views/ContainerDetail.swift Sources/GDocker/Views/LogsTab.swift
git commit -m "feat(ui): polish ContainerDetail header, TabStrip, and LogsTab toolbar"
```

---

### Task 7: Redesigned `ActivityView` (`02`, `02d`)

**Files:**
- Modify: `Sources/GDocker/Views/ActivityView.swift`

**Interfaces:**
- Consumes: `ActivityModel`, `ApprovalModel` (for pending count in KPI card)
- Produces:
  - 4 KPI cards (`Chamadas hoje`, `Permitidas`, `Negadas`, `Aguardando`) at top.
  - Tabular activity log (`HORA`, `FERRAMENTA`, `ALVO`, `CLIENTE`, `RESULTADO` pill, `DETALHE`).

- [ ] **Step 1: Implement KPI cards and tabular columns in `ActivityView.swift`**
- [ ] **Step 2: Build & test**

Run: `make test`
Expected: Compiles and tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/GDocker/Views/ActivityView.swift
git commit -m "feat(ui): redesign ActivityView with KPI cards and tabular log"
```

---

### Task 8: Redesigned `PermissionsView` and `ApprovalView` (`03`, `03d`, `04`)

**Files:**
- Modify: `Sources/GDocker/Views/PermissionsView.swift`
- Modify: `Sources/GDocker/Views/ApprovalView.swift`

**Interfaces:**
- Consumes: `McpController`, `PermissionsModel`, `ApprovalModel`, `ToolCatalog`
- Produces:
  - `PermissionsView` with top status banner (`Servidor MCP ativo · localhost:<port> · N cliente(s)`, clickable `N aguardando aprovação` pill, `Mascarar variáveis de ambiente` toggle) and tabular tool permissions (`FERRAMENTA`, `DESCRIÇÃO`, `RISCO` pill `Baixo`/`Médio`/`Alto`, `PERMISSÃO` `Permitir`/`Perguntar`/`Negar`).
  - `ApprovalView` matching Penpot `04` (`Aprovar chamada da IA?`, `<Client> quer executar uma ação sensível`, monospace `Ferramenta` / `Alvo` / `Comando` card, and 3 buttons: `Negar`, `Permitir uma vez`, `Sempre permitir`).

- [ ] **Step 1: Redesign `PermissionsView.swift` with status banner, risk pills, and tabular rows**
- [ ] **Step 2: Redesign `ApprovalView.swift` with structured monospace detail card and 3 action buttons**
- [ ] **Step 3: Build & test**

Run: `make test`
Expected: Compiles and tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/GDocker/Views/PermissionsView.swift Sources/GDocker/Views/ApprovalView.swift
git commit -m "feat(ui): redesign PermissionsView and ApprovalView to match Penpot specs"
```

---

### Task 9: Localization & Final Verification

**Files:**
- Modify: `Sources/GDocker/Resources/Localizable.xcstrings`

- [ ] **Step 1: Add all new localization keys (English + Portuguese) to `Localizable.xcstrings`**
- [ ] **Step 2: Run localization check**

Run: `python3 scripts/check_l10n.py`
Expected: Exit code 0 with no missing keys.

- [ ] **Step 3: Run full test suite and release app build**

Run: `make test && make app`
Expected: All tests pass and `build/GDocker.app` builds cleanly.

- [ ] **Step 4: Commit**

```bash
git add Sources/GDocker/Resources/Localizable.xcstrings
git commit -m "chore(l10n): add English and Portuguese strings for UI redesign"
```
