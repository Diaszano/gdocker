# Docker Compose Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar suporte completo ao Docker Compose no GDocker: modelos de domínio e persistência de stacks no disco (`GDockerCore`), orquestração assíncrona via subprocesso `docker compose` com injeção de `DOCKER_HOST`, 3 novas ferramentas MCP com políticas de aprovação (`GDockerMCP`), tela dedicada com controle de ciclo de vida (`GDocker`) e suporte bilíngue (`en`/`pt-BR`).

**Architecture:** Abordagem híbrida combinando leitura de estado em tempo real via labels de containers da Engine API (`com.docker.compose.*`), agregação com stacks salvas em disco (`ComposeProjectRegistry`) para manter visibilidade de projetos parados (`down`), orquestração delegada ao CLI oficial `docker compose` (`CLIComposeRunner`) e exposição segura via catálogo de ferramentas MCP (`ToolRouter`).

**Tech Stack:** Swift 6.1/6.3 (macOS 14+), Observation framework, Swift Concurrency (actors, Sendable), Foundation `Process`, Swift Testing framework (`@Test`, `#expect`), xcstrings localization.

**Spec:** `docs/superpowers/specs/2026-11-12-gdocker-03b-compose-design.md`

## Global Constraints

- macOS 14+ (Sonoma) target mínimo.
- Swift 6.1 / Swift 6.3 modo de concorrência estrita (zero data races, uso correto de `Sendable`, actors e `@MainActor`).
- Todas as strings voltadas ao usuário devem estar em `Sources/GDocker/Resources/Localizable.xcstrings` (inglês `en` e português do Brasil `pt-BR`), validadas via `python3 -I scripts/check_l10n.py .`.
- Todas as execuções de testes devem rodar via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test` sem depender do daemon Docker real ou do executável CLI real (uso de fakes/stubs determinísticos).
- Mensagens de commit no formato Conventional Commits com primeira linha de no máximo 72 caracteres, sem trailers de co-autoria de IA.

## Review Focus

1. **Diretório ausente ou deletado no disco:** ao executar `compose_up` ou `compose_down` em um projeto cujo `workingDir` não existe mais, retornar erro amigável (`Directory '<path>' does not exist`) sem quebrar a UI ou travar o processo.
   - *Testado em:* Task 2 (`ComposeRunnerTests`) e Task 3 (`ToolRouterTests`).
2. **Múltiplos arquivos compose:** labels com múltiplos arquivos separados por vírgula (`docker-compose.yml,docker-compose.override.yml`) devem ser divididos e passados individualmente como flags `-f` para o CLI.
   - *Testado em:* Task 2 (`ComposeRunnerTests`).
3. **Cálculo de status com serviços heterogêneos:** projetos com parte dos containers rodando e parte parada/falha devem computar `.partiallyRunning`; projetos com zero containers devem computar `.down`.
   - *Testado em:* Task 1 (`ComposeRegistryTests`).
4. **Preservação de serviços em down:** projetos recuperados do disco após `down` mantêm `serviceNames`, permitindo exibir a lista de serviços com container e estado nulos.
   - *Testado em:* Task 1 (`ComposeRegistryTests`).
5. **Captura de falhas e stderr do CLI:** comandos do CLI com código de saída diferente de zero devem capturar stderr e lançar `ComposeError.commandFailed` legível sem silenciar erros.
   - *Testado em:* Task 2 (`ComposeRunnerTests`).

---

### Task 1: Compose Core Models & Registry Persistence (`GDockerCore`)

**Files:**
- Create: `Sources/GDockerCore/Docker/ComposeModels.swift`
- Create: `Sources/GDockerCore/Docker/ComposeProjectRegistry.swift`
- Create: `Tests/GDockerCoreTests/ComposeRegistryTests.swift`

- [x] **Step 1: Write failing tests for Compose models and registry**
  - Escrever testes em `Tests/GDockerCoreTests/ComposeRegistryTests.swift`:
    - Ingestão de containers com labels Compose (`com.docker.compose.project`, `com.docker.compose.service`, `com.docker.compose.project.working_dir`, `com.docker.compose.project.config_files`).
    - Cálculo de status: todos rodando -> `.running`, mistura -> `.partiallyRunning`, todos parados -> `.stopped`, ausentes -> `.down`.
    - Persistência em disco: salvar registros em arquivo JSON temporário e recarregar preservando `serviceNames`, `workingDir`, `configFiles`.
    - Esquecer projeto: `removeProject(named:)` remove da memória e persiste remoção no disco.
- [x] **Step 2: Run tests to verify they fail**
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`
- [x] **Step 3: Implement ComposeModels and ComposeProjectRegistry**
  - Implementar em `Sources/GDockerCore/Docker/ComposeModels.swift`:
    - `ComposeServiceSummary` (`id`, `name`, `containerID`, `state`, `statusKind`).
    - `ComposeStatus` (`running`, `partiallyRunning`, `stopped`, `down`).
    - `ComposeProject` (`id`, `name`, `workingDir`, `configFiles`, `services`, `status`).
    - `ComposeProjectRecord` (`name`, `workingDir`, `configFiles`, `serviceNames`, `lastSeen`).
  - Implementar em `Sources/GDockerCore/Docker/ComposeProjectRegistry.swift`:
    - Actor ou classe segura com serialização JSON em arquivo injetável (`fileURL`).
    - `ingest(containers: [ContainerSummary])`.
    - `removeProject(named: String)`.
    - `projects(containers: [ContainerSummary]) -> [ComposeProject]`.
- [x] **Step 4: Run tests to verify they pass**
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`
- [x] **Step 5: Commit**
  - `git commit -m "feat(core): add compose models and project registry"`

---

### Task 2: Compose Operations Protocol & Runners (`GDockerCore`)

**Files:**
- Create: `Sources/GDockerCore/Docker/ComposeOperations.swift`
- Create: `Tests/GDockerCoreTests/ComposeRunnerTests.swift`

- [x] **Step 1: Write failing tests for Compose runners**
  - Escrever testes em `Tests/GDockerCoreTests/ComposeRunnerTests.swift`:
    - `FakeComposeRunner`: grava invocações (`calls`), simula saídas com sucesso e simula erros.
    - Validação de argumentos no `CLIComposeRunner`: flags `-f` para múltiplos arquivos de config, `--project-directory`, `-d` no `up`, `-v` no `down` condicional a `removeVolumes`.
    - Resolução de executável docker (caminhos conhecidos macOS).
    - Validação de existência de diretório de trabalho antes de invocar subprocesso (Review Focus 1).
- [x] **Step 2: Run tests to verify they fail**
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`
- [x] **Step 3: Implement ComposeOperations, FakeComposeRunner, and CLIComposeRunner**
  - Implementar em `Sources/GDockerCore/Docker/ComposeOperations.swift`:
    - Protocolo `ComposeOperations: Sendable`:
      - `func composeUp(project: String, workingDir: String, configFiles: [String]) async throws -> String`
      - `func composeDown(project: String, workingDir: String, configFiles: [String], removeVolumes: Bool) async throws -> String`
      - `func isComposeAvailable() async -> Bool`
    - `ComposeError`: casos para `binaryNotFound`, `directoryNotFound(String)`, `commandFailed(exitCode: Int, output: String)`.
    - `FakeComposeRunner`: implementação em memória para testes.
    - `CLIComposeRunner`: implementação usando `Process` em background, localizando binário em caminhos conhecidos do macOS (`/usr/local/bin/docker`, `/opt/homebrew/bin/docker`, etc.) e aplicando `DOCKER_HOST` a partir de `DockerSocket.discover()`.
- [x] **Step 4: Run tests to verify they pass**
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`
- [x] **Step 5: Commit**
  - `git commit -m "feat(core): implement compose operations and cli runner"`

---

### Task 3: MCP Compose Tools & ToolRouter Integration (`GDockerCore` & `GDockerMCP`)

**Files:**
- Modify: `Sources/GDockerCore/Access/ToolCatalog.swift`
- Modify: `Sources/GDockerCore/Access/ToolRouter.swift`
- Modify: `Sources/GDocker/Mcp/McpController.swift`
- Modify: `Tests/GDockerCoreTests/ToolRouterTests.swift`
- Modify: `Tests/GDockerMCPTests/McpHTTPServerTests.swift`
- Modify: `Tests/GDockerMCPTests/McpTestSupport.swift`

- [x] **Step 1: Write failing tests for compose MCP tools**
  - Escrever testes em `Tests/GDockerCoreTests/ToolRouterTests.swift`:
    - `list_compose_projects`: retorna JSON com projetos conhecidos, serviços e status.
    - `compose_up`: valida parâmetro `project`, resolve caminhos no registry, executa up, respeita aprovação `.ask`.
    - `compose_down`: valida `project`, respeita flag `remove_volumes`, proíbe `allowsAlways` (Review Focus / Anti-objetivo).
    - Retorna erro claro quando projeto não existe no registro ou diretório não existe no disco.
- [x] **Step 2: Run tests to verify they fail**
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`
- [x] **Step 3: Update ToolCatalog and ToolRouter**
  - Em `ToolCatalog.swift`: adicionar `list_compose_projects` (.read, .allow), `compose_up` (.control, .ask), `compose_down` (.control, .ask, `allowsAlways: false`). Total sobe para 20 ferramentas.
  - Em `ToolRouter.swift`:
    - Adicionar propriedades `registry: ComposeProjectRegistry` e `compose: @Sendable () async -> (any ComposeOperations)?`.
    - No início de rotas de compose, sincronizar registry chamando `docker.listContainers()`.
    - Implementar execução das 3 ferramentas.
  - Em `McpController.swift` e testes: repassar registry e compose runner para `ToolRouter`.
- [x] **Step 4: Run tests to verify they pass**
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`
- [x] **Step 5: Commit**
  - `git commit -m "feat(mcp): add compose tools to catalog and router"`

---

### Task 4: Compose Domain Store (`GDocker`)

**Files:**
- Create: `Sources/GDocker/Stores/ComposeStore.swift`
- Modify: `Sources/GDocker/GDockerApp.swift`
- Create: `Tests/GDockerCoreTests/ComposeProjectTests.swift` (search/active logic lives on `ComposeProject` in `GDockerCore`, since the `GDocker` app target has no test target)

- [x] **Step 1: Write failing tests for ComposeStore logic**
  - Escrever testes em `Tests/GDockerCoreTests/ComposeStoreTests.swift`:
    - Atualização da lista de projetos quando containers mudam.
    - Filtro de busca (`searchText`) por nome do projeto e nome de serviço.
    - Contagem de projetos ativos para badge.
    - Ação `forget(project:)` chama registry.
- [x] **Step 2: Run tests to verify they fail**
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`
- [x] **Step 3: Implement ComposeStore and inject into GDockerApp**
  - Implementar `ComposeStore.swift`:
    - `@MainActor @Observable final class ComposeStore`.
    - `projects: [ComposeProject]`, `searchText: String`, `isComposeAvailable: Bool`, `isPerformingAction: Bool`.
    - `activeCount: Int` (computa stacks com status `.running` ou `.partiallyRunning`).
    - Métodos: `up(project:)`, `down(project:removeVolumes:)`, `forget(project:)`.
  - Integrar em `GDockerApp.swift`: instanciar `ComposeStore` e fornecer como `.environment(composeStore)`.
- [x] **Step 4: Run tests to verify they pass**
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`
- [x] **Step 5: Commit**
  - `git commit -m "feat(store): add compose store with search and actions"`

---

### Task 5: Compose UI View & Sidebar Navigation (`GDocker`)

**Files:**
- Create: `Sources/GDocker/Views/ComposeView.swift`
- Modify: `Sources/GDocker/Views/MainWindow.swift`

- [x] **Step 1: Implement ComposeView**
  - Tabela/lista de projetos Compose com colunas: Nome, Status, Serviços, Diretório.
  - Badges de status coloridos (`running` -> verde, `partiallyRunning` -> amarelo, `stopped` -> cinza, `down` -> azul/cinza).
  - Linha expansível ou detalhe mostrando os serviços individuais da stack e seus containers.
  - Botões de ação por linha: `Up` e `Down`.
  - Diálogo de confirmação para `Down` com toggle "Remover volumes associados" (`removeVolumes`).
  - Ação "Esquecer projeto" no menu de contexto ou botão quando a stack estiver em `down`.
  - Banner informativo se o CLI `docker compose` não estiver instalado.
  - Alerta de erro caso a pasta do projeto não exista no disco.
- [x] **Step 2: Add Compose to MainWindow Sidebar**
  - Adicionar entrada de navegação `Compose` na seção "Docker" da barra lateral com ícone `square.stack.3d.forward.dottedline` e badge ao vivo com `composeStore.activeCount`.
  - Renderizar `ComposeView` quando a aba selecionada for `.compose`.
- [x] **Step 3: Build and verify app compilation**
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`
- [x] **Step 4: Commit**
  - `git commit -m "feat(ui): add compose view and sidebar integration"`

---

### Task 6: Localization & Full Suite Verification (`GDocker`)

**Files:**
- Modify: `Sources/GDocker/Resources/Localizable.xcstrings`

- [x] **Step 1: Extract and add all localization keys**
  - Adicionar todas as novas chaves em inglês (`en`) e português (`pt-BR`) em `Localizable.xcstrings`:
    - "Compose", "Docker Compose", "Up", "Down", "Forget Project", "Remove Volumes", "Are you sure you want to stop this stack?", "This will stop and remove containers for project '%@'.", "Directory '%@' does not exist.", "Docker Compose CLI not found.", etc.
- [x] **Step 2: Verify localization with script**
  - `python3 -I scripts/check_l10n.py .`
  - Garantir 0 missing e 0 unused keys.
- [x] **Step 3: Run full test suite**
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`
  - Garantir que todos os testes (GDockerCoreTests + GDockerMCPTests) passam com 100% de sucesso.
- [x] **Step 4: Commit**
  - `git commit -m "chore(l10n): add localization for compose feature"`
