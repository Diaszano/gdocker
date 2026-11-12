# gdocker Plano 3A — Recursos Docker: Imagens, Volumes e Redes

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O app lista, remove e limpa Imagens, Volumes e Redes na interface macOS com contadores na barra lateral, e expõe as ferramentas MCP correspondentes (`list_images`, `list_volumes`, `list_networks`, `remove_image`, `remove_volume`, `remove_network`, `system_prune`) sob o controle de permissões e aprovação da IA.

**Architecture:** A camada de dados e Engine API mora em `GDockerCore` (`ImageSummary`, `VolumeSummary`, `NetworkSummary`, `PruneReport`, `DockerClient` e o protocolo `DockerOperations` com fakes para testes). As 7 novas ferramentas entram em `ToolCatalog.all` e são tratadas no `ToolRouter`. No app (`GDocker`), stores dedicados sob demanda (`ImagesStore`, `VolumesStore`, `NetworksStore`) compartilham o cliente Docker, e telas dedicadas (`ImagesView`, `VolumesView`, `NetworksView`) são integradas à navegação da barra lateral com confirmações para ações destrutivas.

**Tech Stack:** Swift 6.3, SwiftUI, Docker Engine API v1.45 via AsyncHTTPClient, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-12-gdocker-03a-resources-design.md`.

## Global Constraints

- macOS mínimo **14**; `swift-tools-version:6.1`; todo comando `swift` com `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (o `Makefile` já exporta). Testes: `make test`.
- Toda requisição HTTP criada deve ser finalizada se um cliente for descartado.
- Strings visíveis no catálogo `Sources/GDocker/Resources/Localizable.xcstrings` com **en** e **pt-BR**, validadas com `python3 -I scripts/check_l10n.py .`.
- Commits sem trailer de co-autoria de IA (hook de commit). Branch no formato `feature/<nome-kebab>`, ex: `feature/resources`.
- Redes padrão do Docker (`bridge`, `host`, `none`) não podem ser removidas pela UI.
- Ferramentas destrutivas (`remove_*`, `system_prune`) têm permissão padrão `.deny` no MCP.

## Review Focus

1. `remove_network` chamada contra rede padrão (`bridge`/`host`/`none`): deve falhar graciosamente com mensagem explicativa sem corromper o daemon.
2. `system_prune` chamado com volumes desligados: não deve apagar volumes, limpando apenas containers parados, redes órfãs e imagens não usadas.
3. Imagem com múltiplas tags ou `<none>:<none>` (dangling): exibição e remoção não devem travar ou gerar nomes vazios.
4. Falha de conexão ao carregar uma seção (ex: Colima parado): a tela exibe o estado desconectado sem travar o app.
5. Volume em uso por um container: tentativa de remoção sem `force: true` deve reportar o erro retornado pela Engine API com clareza.

---

### Task 1: Core Models & DockerClient Methods

**Files:**
- Create: `Sources/GDockerCore/Docker/{ImageSummary,VolumeSummary,NetworkSummary,PruneReport}.swift`, `Tests/GDockerCoreTests/DockerResourcesTests.swift`
- Modify: `Sources/GDockerCore/Docker/DockerClient.swift`, `Sources/GDockerCore/Docker/DockerOperations.swift`, `Tests/GDockerCoreTests/FakeDocker.swift`

**Interfaces:**
- Produces:
  - `struct ImageSummary: Identifiable, Sendable, Codable, Equatable { let id: String; let repoTags: [String]; let size: Int64; let created: Int64 }`
  - `struct VolumeSummary: Identifiable, Sendable, Codable, Equatable { var id: String { name }; let name: String; let driver: String; let scope: String; let createdAt: String? }`
  - `struct NetworkSummary: Identifiable, Sendable, Codable, Equatable { let id: String; let name: String; let driver: String; let scope: String; let containerCount: Int }`
  - `struct PruneReport: Sendable, Codable, Equatable { let containersDeleted: Int; let imagesDeleted: Int; let networksDeleted: Int; let volumesDeleted: Int; let spaceReclaimed: Int64 }`
  - Métodos em `DockerOperations` e `DockerClient`:
    - `func listImages() async throws -> [ImageSummary]` (`GET /images/json`)
    - `func removeImage(_ id: String, force: Bool) async throws` (`DELETE /images/<id>?force=<force>`)
    - `func pruneImages() async throws -> (deleted: [String], spaceReclaimed: Int64)` (`POST /images/prune`)
    - `func listVolumes() async throws -> [VolumeSummary]` (`GET /volumes`)
    - `func removeVolume(_ name: String, force: Bool) async throws` (`DELETE /volumes/<name>?force=<force>`)
    - `func pruneVolumes() async throws -> (deleted: [String], spaceReclaimed: Int64)` (`POST /volumes/prune`)
    - `func listNetworks() async throws -> [NetworkSummary]` (`GET /networks`)
    - `func removeNetwork(_ id: String) async throws` (`DELETE /networks/<id>`)
    - `func pruneNetworks() async throws -> [String]` (`POST /networks/prune`)
    - `func pruneContainers() async throws -> (deleted: [String], spaceReclaimed: Int64)` (`POST /containers/prune`)
    - `func systemPrune(all: Bool, volumes: Bool) async throws -> PruneReport`

- [ ] **Step 1: Escrever os testes que falham em `DockerResourcesTests.swift`**
Decodificação de payloads reais da Engine API (fixtures de `/images/json`, `/volumes`, `/networks`, `/prune`), e validação das chamadas e relatórios no `FakeDocker`.

- [ ] **Step 2: Executar os testes para confirmar a falha**
`make test` -> FAIL (métodos e modelos não definidos).

- [ ] **Step 3: Implementar modelos, endpoints no `DockerClient` e stub no `FakeDocker`**
Criar as structs em `Sources/GDockerCore/Docker/`, estender `DockerOperations`, implementar as chamadas no `DockerClient` usando `send(.GET, ...)` / `send(.POST, ...)`.

- [ ] **Step 4: Executar os testes para confirmar o sucesso**
`make test` -> PASS.

- [ ] **Step 5: Commit**
`git add Sources/GDockerCore Tests/GDockerCoreTests && git commit -m "feat(core): image, volume, network models and engine api client"`

---

### Task 2: MCP Tool Specs & ToolRouter Integration

**Files:**
- Modify: `Sources/GDockerCore/Access/ToolCatalog.swift`, `Sources/GDockerCore/Access/ToolRouter.swift`, `Tests/GDockerCoreTests/ToolCatalogTests.swift`, `Tests/GDockerCoreTests/ToolRouterTests.swift`

**Interfaces:**
- Consumes: `DockerOperations`, `ImageSummary`, `VolumeSummary`, `NetworkSummary`, `PruneReport` (Task 1).
- Produces:
  - Novas entradas em `ToolCatalog.all`:
    - `list_images` (group: `.read`, default: `.allow`)
    - `list_volumes` (group: `.read`, default: `.allow`)
    - `list_networks` (group: `.read`, default: `.allow`)
    - `remove_image` (group: `.destructive`, default: `.deny`, params: `image`, `force`)
    - `remove_volume` (group: `.destructive`, default: `.deny`, params: `volume`, `force`)
    - `remove_network` (group: `.destructive`, default: `.deny`, params: `network`)
    - `system_prune` (group: `.destructive`, default: `.deny`, params: `all`, `volumes`)
  - No `ToolRouter.call()`: roteamento para `docker.listImages()`, `docker.removeImage()`, etc., respeitando as regras de permissão (`allow`, `ask`, `deny`), com prompts na `ApprovalQueue` para ações em `.ask` e gravação no `ActivityLog`.

- [ ] **Step 1: Escrever os testes em `ToolCatalogTests.swift` e `ToolRouterTests.swift`**
Verificar que `ToolCatalog.all` tem as 17 ferramentas; testar permissões padrão; testar chamada permitida de `list_images`; testar prompt de aprovação para `remove_volume`; testar recusa de `remove_network` em `.deny`.

- [ ] **Step 2: Executar os testes para confirmar a falha**
`make test` -> FAIL.

- [ ] **Step 3: Atualizar `ToolCatalog.swift` e estender o switch em `ToolRouter.swift`**
Adicionar especificações completas de ferramentas e rotear chamadas chamando os métodos correspondentes de `DockerOperations`.

- [ ] **Step 4: Executar os testes para confirmar o sucesso**
`make test` -> PASS.

- [ ] **Step 5: Commit**
`git add Sources/GDockerCore Tests/GDockerCoreTests && git commit -m "feat(mcp): image, volume, network and system prune tool specs and routing"`

---

### Task 3: Domain Stores (ImagesStore, VolumesStore, NetworksStore)

**Files:**
- Create: `Sources/GDocker/Stores/{ImagesStore,VolumesStore,NetworksStore}.swift`
- Modify: `Sources/GDocker/GDockerApp.swift`, `Sources/GDocker/Views/MainWindow.swift`

**Interfaces:**
- Consumes: `DockerClient`, `ImageSummary`, `VolumeSummary`, `NetworkSummary`, `PruneReport` (Task 1).
- Produces:
  - `@MainActor @Observable final class ImagesStore`: lista de imagens, `selectedID`, `searchText`, `filteredImages`, `refresh()`, `remove(id:force:)`, `prune()`.
  - `@MainActor @Observable final class VolumesStore`: lista de volumes, `selectedID`, `searchText`, `filteredVolumes`, `refresh()`, `remove(name:force:)`, `prune()`.
  - `@MainActor @Observable final class NetworksStore`: lista de redes, `selectedID`, `searchText`, `filteredNetworks`, `refresh()`, `remove(id:)`, `prune()`.
  - Injeção desses stores no environment em `GDockerApp.swift` alimentados pelo `ContainersStore.client`.

- [ ] **Step 1: Criar os três stores em `Sources/GDocker/Stores/`**
Implementar filtragem por busca, chamada aos métodos do cliente, tratamento de erros em `lastError` e contadores.

- [ ] **Step 2: Ligar os stores no ciclo de vida do app em `GDockerApp.swift`**
Instanciar os stores e injetá-los no `.environment(...)`.

- [ ] **Step 3: Compilar e rodar a suíte de testes**
`make test` -> PASS.

- [ ] **Step 4: Commit**
`git add Sources/GDocker && git commit -m "feat(app): images, volumes and networks stores"`

---

### Task 4: UI Views (ImagesView, VolumesView, NetworksView) & Navigation

**Files:**
- Create: `Sources/GDocker/Views/{ImagesView,VolumesView,NetworksView}.swift`
- Modify: `Sources/GDocker/Views/MainWindow.swift`

**Interfaces:**
- Consumes: `ImagesStore`, `VolumesStore`, `NetworksStore` (Task 3).
- Produces:
  - `ImagesView`: Tabela/lista de imagens com ID curto, RepoTags, Size em MB/GB, data formatada. Ações no topo: botão de remover selecionada e "Prune Images", ambos com alerta nativo de confirmação.
  - `VolumesView`: Tabela/lista com Nome, Driver, Data. Ações: botão de remover selecionado e "Prune Volumes" com alerta nativo.
  - `NetworksView`: Tabela/lista com Nome, Driver, Escopo, contagem de containers. Ações: botão de remover (desabilitado se for `bridge`, `host` ou `none`).
  - `MainWindow.swift`: barra lateral expandida com itens `images`, `volumes`, `networks` (com contadores). Ao selecionar uma seção, o `detail` exibe a view correspondente e chama `refresh()`.

- [ ] **Step 1: Implementar as views `ImagesView`, `VolumesView`, `NetworksView`**
Construir as telas com SwiftUI usando listas nativas, badges e diálogos de confirmação de exclusão (`confirmationDialog` / `alert`).

- [ ] **Step 2: Integrar as seções na barra lateral de `MainWindow.swift`**
Adicionar os casos ao enum `SidebarItem`: `.images`, `.volumes`, `.networks`, com contadores vivos.

- [ ] **Step 3: Verificar compilação**
`make build` e `make test` -> PASS.

- [ ] **Step 4: Commit**
`git add Sources/GDocker && git commit -m "feat(app): images, volumes and networks views and sidebar navigation"`

---

### Task 5: Global System Prune Menu, Localization & Verification

**Files:**
- Modify: `Sources/GDocker/GDockerApp.swift`, `Sources/GDocker/Resources/Localizable.xcstrings`
- Modify: `scripts/check_l10n.py` (garantir verificação de novas chaves de ferramentas)

**Interfaces:**
- Consumes: todas as tasks anteriores.
- Produces:
  - Menu `Docker > System Prune...` na barra de menus do macOS acionando um alerta modal de confirmação.
  - Catálogo de localização completo com todas as novas strings em **en** e **pt-BR**:
    - Nomes e descrições das ferramentas no MCP.
    - Títulos das seções da barra lateral, botões de ação e alertas de confirmação de exclusão e prune.
  - Verificação com `python3 -I scripts/check_l10n.py .` com saída 0.

- [ ] **Step 1: Adicionar o comando de menu em `GDockerApp.swift`**
Implementar o comando `CommandMenu("Docker")` com atalho ou item "System Prune...".

- [ ] **Step 2: Adicionar todas as chaves em `Localizable.xcstrings`**
Preencher todas as traduções em inglês e português do Brasil.

- [ ] **Step 3: Rodar os testes e a checagem de localização**
`make test` e `python3 -I scripts/check_l10n.py .`. Ambos devem passar com 100% de sucesso.

- [ ] **Step 4: Commit**
`git add Sources/GDocker scripts/check_l10n.py && git commit -m "feat(app): system prune menu command and l10n strings"`
