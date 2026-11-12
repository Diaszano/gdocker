# Terminal Interativo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar a aba **Terminal** ao detalhe do container: um shell interativo (`bash` ou `sh`) rodando via `docker exec -it` num pseudo-terminal do SwiftTerm, dentro da janela do GDocker.

**Architecture:** A lógica pura (resolução do binário `docker`, montagem de argumentos/ambiente do exec, disponibilidade por estado do container) fica em `GDockerCore` num helper `DockerCLI`, compartilhado com o `CLIComposeRunner`. O app (`GDocker`) embrulha o `LocalProcessTerminalView` do SwiftTerm num `NSViewRepresentable`, com um modelo de sessão por container que sobrevive à troca de abas e é encerrado ao sair do detalhe.

**Tech Stack:** Swift 6.1/6.3 (macOS 14+), SwiftUI + AppKit (`NSViewRepresentable`), SwiftTerm (SPM), Observation, Swift Testing, xcstrings.

**Spec:** `docs/superpowers/specs/2026-11-12-gdocker-04-terminal-design.md`

## Global Constraints

- macOS 14+ (Sonoma); Swift 6.1/6.3 com concorrência estrita (zero data races; views AppKit na `@MainActor`).
- Comando do terminal exatamente: `docker exec -it <containerID> /bin/sh -c 'command -v bash >/dev/null 2>&1 && exec bash || exec sh'`.
- Ambiente do processo: o ambiente do app + `TERM=xterm-256color` + `DOCKER_HOST=unix://<socket>` (socket de `DockerSocket.discover()`; omitido se não houver socket).
- Caminhos do binário `docker`, nesta ordem: `/usr/local/bin/docker`, `/opt/homebrew/bin/docker`, `~/.orbstack/bin/docker`, `/Applications/Docker.app/Contents/Resources/bin/docker`, `/usr/bin/docker`. Sem busca no `PATH`. O Terminal nunca usa o plugin `docker-compose`.
- Sessão só abre com `state == "running"`.
- Todas as strings novas em `en` e `pt-BR` no `Sources/GDocker/Resources/Localizable.xcstrings`; `python3 -I scripts/check_l10n.py .` com 0 missing / 0 unused.
- Testes via `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`, sem daemon nem CLI reais.
- Conventional Commits, primeira linha ≤ 72 caracteres, **sem** trailers de co-autoria de IA.

## Review Focus

1. **Processo órfão ao trocar de container ou fechar a janela:** o `docker exec` da sessão anterior precisa morrer. `MainWindow` já recria `ContainerDetail` com `.id(selected.id)`, então o `onDisappear` do detalhe tem que chamar `terminate()`.
   - *Verificado em:* Task 2, Step 6 (checagem manual com `pgrep -fl "docker exec -it"`).
2. **Container para no meio da sessão:** o shell sai, a aba mostra "Sessão encerrada (código N)" + Reconectar, sem crash; com o container parado, Reconectar dá lugar ao estado vazio com Iniciar.
   - *Testado em:* Task 1 (`TerminalAvailability`), Task 2 Step 6 (manual).
3. **Imagem sem `bash`** (alpine): cai para `sh`. **Sem shell** (distroless): erro do CLI aparece no terminal, depois a faixa de encerrado.
   - *Testado em:* Task 1 (string exata do comando), Task 2 Step 6 (manual com `alpine`).
4. **Máquina só com o plugin `docker-compose`:** Terminal mostra "CLI não encontrado", Compose continua funcionando pelo plugin.
   - *Testado em:* Task 1 (`DockerCLITests`, `ComposeRunnerTests`).
5. **Tema escuro / tema forçado nas Preferências:** cores do terminal acompanham `NSApp.effectiveAppearance` (o app força o tema via `NSApp.appearance` em `AppSettings.swift`).
   - *Verificado em:* Task 2, Step 6 (manual nos dois temas).

---

### Task 1: `DockerCLI` e disponibilidade do terminal (`GDockerCore`)

**Files:**
- Create: `Sources/GDockerCore/Docker/DockerCLI.swift`
- Modify: `Sources/GDockerCore/Docker/ComposeOperations.swift` (`candidateBinaryPaths`, `execute(binary:arguments:workingDir:)`)
- Test: `Tests/GDockerCoreTests/DockerCLITests.swift` (novo), `Tests/GDockerCoreTests/ComposeRunnerTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum DockerCLI {
      public static func candidatePaths(home: String) -> [String]          // os 5 caminhos, ~ expandido com `home`
      public static func resolve(home: String = NSHomeDirectory(),
                                 fileExists: (String) -> Bool) -> String?  // primeiro existente, ou nil
      public static func environment(base: [String: String], socketPath: String?) -> [String: String]
          // base + DOCKER_HOST ("unix://" prefixado se faltar); sem socket, base inalterado
      public static func terminalArguments(containerID: String) -> [String]
          // ["exec", "-it", id, "/bin/sh", "-c", "command -v bash >/dev/null 2>&1 && exec bash || exec sh"]
  }
  public enum TerminalAvailability: Equatable, Sendable {
      case ready, stopped, paused, restarting
      public init(state: String)  // "running"→ready, "paused"→paused, "restarting"→restarting, resto→stopped
  }
  ```
  `TERM=xterm-256color` é adicionado pelo app (Task 2), não por `environment(base:socketPath:)`, porque o Compose não deve recebê-lo.

- [ ] **Step 1: Write the failing tests** em `DockerCLITests.swift`:
  - `candidatePathsAreInOrderWithHomeExpanded`: `candidatePaths(home: "/Users/u")` == os 5 caminhos da Global Constraints, com `/Users/u/.orbstack/bin/docker` no 3º.
  - `resolveReturnsFirstExisting`: com só `/opt/homebrew/bin/docker` e `/usr/bin/docker` existindo → `/opt/homebrew/bin/docker`.
  - `resolveIgnoresComposePlugin`: com só `/Users/u/.docker/cli-plugins/docker-compose` existindo → `nil`.
  - `environmentAddsUnixPrefix`: socket `/var/run/docker.sock` → `DOCKER_HOST == "unix:///var/run/docker.sock"`; socket `unix:///x.sock` não duplica prefixo; `nil` → igual à base.
  - `terminalArgumentsExact`: igual ao array do Interfaces.
  - `availabilityFromState`: `running`→`.ready`, `paused`→`.paused`, `restarting`→`.restarting`, `exited`/`created`/`dead`→`.stopped`.
- [ ] **Step 2: Add Compose regression tests** em `ComposeRunnerTests.swift` (usar o `fileExists` injetado do `CLIComposeRunner`):
  - `composeFallsBackToPluginWhenNoDocker`: só o plugin existe → `isComposeAvailable() == true` e o launcher recebe o plugin, sem o argumento `compose`.
  - `composeFindsOrbStackDocker`: só `<home>/.orbstack/bin/docker` existe → disponível, launcher recebe esse caminho com `compose` como 1º argumento.
- [ ] **Step 3: Run tests to verify they fail**
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test` → falha de compilação (`DockerCLI` indefinido).
- [ ] **Step 4: Implement `DockerCLI` and `TerminalAvailability`** em `DockerCLI.swift`; no `CLIComposeRunner`, `candidateBinaryPaths` vira `DockerCLI.candidatePaths(home:) + [plugin expandido]` (remover a entrada literal `~/.docker/...` não expandida) e `execute` usa `DockerCLI.environment(base:socketPath:)`.
- [ ] **Step 5: Run tests to verify they pass**
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test` → todos verdes, incluindo os `ComposeRunnerTests` antigos.
- [ ] **Step 6: Commit**
  - `git commit -m "feat(core): add shared docker cli helper for terminal"`

---

### Task 2: Aba Terminal com SwiftTerm (`GDocker`)

**Files:**
- Modify: `Package.swift` (dependência `https://github.com/migueldeicaza/SwiftTerm`, versão estável mais recente; produto `SwiftTerm` no target `GDocker`)
- Create: `Sources/GDocker/Views/TerminalSession.swift`
- Create: `Sources/GDocker/Views/TerminalTab.swift`
- Modify: `Sources/GDocker/Views/ContainerDetail.swift` (`Tab`, `content`, `onDisappear`)
- Modify: `Sources/GDocker/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `DockerCLI.resolve`, `DockerCLI.environment`, `DockerCLI.terminalArguments`, `TerminalAvailability(state:)`, `DockerSocket.discover()` (Task 1).
- Produces:
  ```swift
  @MainActor @Observable final class TerminalSession {
      private(set) var view: LocalProcessTerminalView?   // nil até start()
      private(set) var exitCode: Int32?                  // não-nil = sessão encerrada
      private(set) var isCLIAvailable: Bool
      func start(containerID: String)                    // no-op se já rodando
      func reconnect(containerID: String)                // terminate() + start()
      func terminate()                                   // mata o processo; idempotente
  }
  struct TerminalTab: View   // init(session: TerminalSession, container: ContainerSummary)
  ```

- [ ] **Step 1: Add SwiftTerm and confirm it builds under Swift 6**
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --product GDocker` → `build complete`. Se o SwiftTerm não compilar em modo estrito, importar com `@preconcurrency import SwiftTerm` e anotar aqui a versão usada.
- [ ] **Step 2: Implement `TerminalSession`**
  - `start` resolve o binário (`DockerCLI.resolve(fileExists: FileManager.default.fileExists)`); se nil, `isCLIAvailable = false` e não cria view. Senão cria o `LocalProcessTerminalView`, define `processDelegate` (o callback `processTerminated` grava `exitCode`) e chama `startProcess(executable:args:environment:)` com `DockerCLI.terminalArguments`, ambiente `DockerCLI.environment(base: ProcessInfo.processInfo.environment, socketPath: DockerSocket.discover())` + `TERM=xterm-256color` (o SwiftTerm espera o ambiente como `["K=V"]`).
  - Fonte: `NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)`. Cores: `nativeForegroundColor = .textColor`, `nativeBackgroundColor = .textBackgroundColor` (seguem o tema sozinhas).
- [ ] **Step 3: Implement `TerminalTab`**, com base em `TerminalAvailability(state: container.state)` e na sessão:
  - `!isCLIAvailable` → `ContentUnavailableView` "Docker CLI not found" / "The terminal needs the Docker command-line tool installed." (mesmo estilo do aviso do Compose).
  - `.stopped` → "Container is not running" + botão **Start** (`store.perform(.start, on:)`).
  - `.paused` → "Container is paused"; `.restarting` → "Container is restarting"; sem botão.
  - `.ready` → `NSViewRepresentable` mostrando `session.view`; chama `session.start` em `.task(id: container.state)`; foca o terminal ao aparecer (`window?.makeFirstResponder`). Com `exitCode != nil`, faixa no rodapé "Session ended (code %d)" + botão **Reconnect**.
- [ ] **Step 4: Wire into `ContainerDetail`**
  - `case terminal` em `Tab` (depois de `env`, título `"Terminal"`); `@State private var terminal = TerminalSession()`; `case .terminal: TerminalTab(session: terminal, container: container)`.
  - No `.onDisappear` existente, adicionar `terminal.terminate()`. Como a `TerminalSession` fica no `@State` do detalhe, trocar de aba não a encerra.
- [ ] **Step 5: Localize and verify**
  - Adicionar `en`/`pt-BR` para: "Terminal", "Docker CLI not found", "The terminal needs the Docker command-line tool installed.", "Container is not running", "Container is paused", "Container is restarting", "Session ended (code %lld)", "Reconnect".
  - `python3 -I scripts/check_l10n.py .` → 0 missing / 0 unused.
  - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test` → todos verdes.
- [ ] **Step 6: Manual check in the running app** (`make run`)
  - `docker run -d --name t-alpine alpine sleep 1d` e `docker run -d --name t-debian debian sleep 1d`.
  - Debian abre `bash`, alpine abre `sh`; `ls --color`, `top`, `vi`, Ctrl-C funcionam; redimensionar a janela reflete no `stty size`.
  - Logs ↔ Terminal mantém a sessão (histórico na tela preservado).
  - Selecionar outro container → `pgrep -fl "docker exec -it"` não mostra a sessão anterior. Encerrar o app → nenhuma restante.
  - `docker stop t-alpine` com a aba aberta → faixa "Session ended"; depois o estado "not running" com Start.
  - `docker pause t-debian` → "Container is paused".
  - Temas Claro e Escuro forçados nas Preferências → texto legível nos dois.
- [ ] **Step 7: Commit**
  - `git commit -m "feat(ui): add interactive terminal tab with SwiftTerm"`
