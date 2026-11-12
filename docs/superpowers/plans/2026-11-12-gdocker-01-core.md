# gdocker Plano 1 — Núcleo (containers, logs, tema, i18n, barra de menu)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Um app SwiftUI de macOS que lista containers com status ao vivo agrupados por compose, mostra logs ao vivo, stats, inspect e env, inicia/para/reinicia/remove containers, com tema claro/escuro, pt-BR/en e modo barra de menu.

**Architecture:** Swift Package com dois alvos: `GDockerCore` (biblioteca testável: descoberta do socket, cliente da Engine API via HTTP sobre socket Unix, parsing de logs/stats, modelos) e `GDocker` (executável SwiftUI: stores `@Observable` + views). Um `Makefile` empacota o executável em `GDocker.app`.

**Tech Stack:** Swift 6.3, SwiftUI, macOS 14+, Swift Testing, [async-http-client](https://github.com/swift-server/async-http-client) (HTTP sobre `http+unix://`), String Catalog (`.xcstrings`).

**Spec:** `docs/superpowers/specs/2026-11-12-gdocker-design.md`

**Este é o plano 1 de 3.** Plano 2: servidor MCP, permissões, aprovação, atividade, token e `--stdio`. Plano 3: Imagens/Volumes/Redes/Compose (exceção do CLI), aba Terminal e cask do Homebrew. Cada um produz um app que funciona sozinho.

## Global Constraints

- macOS mínimo **14**. `Package.swift`: `platforms: [.macOS(.v14)]`, `swift-tools-version:6.1`, `defaultLocalization: "en"`.
- Esta máquina tem só as Command Line Tools selecionadas. **Todo** comando `swift` roda com `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (o `Makefile` exporta isso). Sem isso, `import Testing` falha.
- Acesso ao Docker **somente** pela Engine API via socket Unix. Nada de `Process("docker", …)` neste plano.
- Prefixo de versão da API: `/v1.41` em todas as rotas.
- Toda string visível ao usuário passa pelo String Catalog `Sources/GDocker/Resources/Localizable.xcstrings`, com **en** e **pt-BR** preenchidos. A chave é o texto em inglês.
- Bundle id: `com.diaszano.gdocker` (decisão do plano).
- Cores de status (mockup 01): verde = rodando, laranja = reiniciando/pausado/criado, cinza = saiu com código 0, vermelho = saiu com código ≠ 0 ou dead.
- Testes de integração que precisam do Docker usam `.enabled(if: DockerSocket.discover() != nil)`, para não quebrar em máquina sem Docker.

## Review Focus

1. **Docker parado ou socket ausente:** o app mostra o estado "Docker desconectado" e reconecta sozinho quando o Docker volta, sem travar nem sair. Testes na Task 2 (`discover` devolve `nil`) e na Task 7 (estado do store).
2. **Ação que falha** (parar algo já parado, remover um container rodando, container sumiu): erro visível na UI com a mensagem do Docker; `304` conta como sucesso. Teste na Task 4 (`DockerError.from`).
3. **Container removido enquanto está selecionado**, ou stream de logs que termina: o detalhe é limpo e o stream é cancelado sem crash. Task 7, passo de verificação manual.
4. **Container que gera muito log** com "Seguir" ligado: o buffer fica limitado a 5000 linhas e a UI continua responsiva. Teste na Task 5 (`LogBuffer`).
5. **Frame de log partido entre dois chunks, ou bytes que não são UTF-8:** o demuxer guarda o frame parcial e decodifica com substituição de caracteres inválidos. Teste na Task 5.

---

### Task 1: Esqueleto do pacote, app abrindo e i18n funcionando

**Files:**
- Create: `Package.swift`, `Makefile`, `scripts/Info.plist`, `.gitignore`
- Create: `Sources/GDockerCore/GDockerCore.swift` (vazio, só para o alvo existir)
- Create: `Sources/GDocker/GDockerApp.swift`, `Sources/GDocker/L10n.swift`, `Sources/GDocker/Resources/Localizable.xcstrings`
- Create: `Tests/GDockerCoreTests/SmokeTests.swift`

**Interfaces:**
- Produces: alvos `GDockerCore` (library) e `GDocker` (executableTarget, `resources: [.process("Resources")]`), dependência `async-http-client` from `"1.21.0"` em `GDockerCore`; `Bundle.l10n: Bundle` (resolve o bundle de recursos tanto no `swift run` quanto dentro do `.app`); `make test`, `make run`, `make app`.

- [ ] **Step 1:** Escrever `Package.swift` conforme Global Constraints e `.gitignore` (`.build/`, `build/`, `*.app`).
- [ ] **Step 2:** Escrever o `Makefile`:
  - `export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer`
  - `test:` roda `swift test`
  - `run:` roda `make app && open build/GDocker.app`
  - `app:` roda `swift build -c release`, cria `build/GDocker.app/Contents/{MacOS,Resources}`, copia o binário, `GDocker_GDocker.bundle` para `Contents/Resources/` e `scripts/Info.plist`, e assina ad-hoc com `codesign --force --deep -s -`.
  - `Info.plist`: `CFBundleIdentifier com.diaszano.gdocker`, `CFBundleExecutable GDocker`, `LSMinimumSystemVersion 14.0`, `CFBundleLocalizations [en, pt-BR]`, `CFBundleDevelopmentRegion en`.
- [ ] **Step 3:** `L10n.swift`: `extension Bundle { static let l10n: Bundle }`, que procura `GDocker_GDocker.bundle` primeiro em `Bundle.main.resourceURL` e cai para `.module`. (O acessor gerado pelo SPM procura no `bundleURL`, e colocar arquivo na raiz do `.app` quebra a assinatura.)
- [ ] **Step 4:** `GDockerApp.swift`: `@main struct GDockerApp: App` com um `WindowGroup` que mostra `Text("Containers", bundle: .l10n)`. Catálogo com a chave `Containers` → pt-BR `Containers`, e uma chave de teste `Docker disconnected` → pt-BR `Docker desconectado` mostrada embaixo.
- [ ] **Step 5:** `SmokeTests.swift`: `@Test func coreLinks() { #expect(true) }` com `import GDockerCore`.
- [ ] **Step 6:** Rodar `make test`. Esperado: `✔ Test run with 1 test … passed`.
- [ ] **Step 7:** Rodar `make run` com o sistema em inglês e depois com `defaults write com.diaszano.gdocker AppleLanguages '("pt-BR")'`. Esperado: a janela mostra "Docker disconnected" e depois "Docker desconectado". Apagar a chave em seguida (`defaults delete com.diaszano.gdocker AppleLanguages`).
- [ ] **Step 8:** Commit `chore: scaffold GDocker package, app bundle and l10n`.

### Task 2: Descoberta do socket do Docker

**Files:**
- Create: `Sources/GDockerCore/Docker/DockerSocket.swift`
- Test: `Tests/GDockerCoreTests/DockerSocketTests.swift`

**Interfaces:**
- Produces: `public enum DockerSocket { public static func discover(env: [String: String] = ProcessInfo.processInfo.environment, home: URL = FileManager.default.homeDirectoryForCurrentUser, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? }`, que devolve o caminho do socket.

Ordem (o primeiro que existir vence):
1. `DOCKER_HOST` com o prefixo `unix://`. Um `DOCKER_HOST` que não é unix é ignorado.
2. O contexto atual: `currentContext` em `~/.docker/config.json` → `~/.docker/contexts/meta/<sha256 hex do nome>/meta.json` → `Endpoints.docker.Host` (`unix://…`). O contexto `default` ou ausente pula esta etapa. Hash com `CryptoKit.SHA256`.
3. Caminhos conhecidos: `/var/run/docker.sock`, `~/.docker/run/docker.sock`, `~/.orbstack/run/docker.sock`, `~/.colima/default/docker.sock`.

Apps abertos pelo Finder não herdam `DOCKER_HOST` do shell, por isso o passo 2 importa (o Colima desta máquina só é achado por ele ou pelo passo 3).

- [ ] **Step 1: Testes que falham** (cada um usa um diretório temporário como `home` e um `exists` falso):
  - `envUnixWins`: `env = ["DOCKER_HOST": "unix:///tmp/x.sock"]`, `exists` aceita tudo → `"/tmp/x.sock"`
  - `envTcpIgnored`: `DOCKER_HOST=tcp://1.2.3.4:2375`, só `/var/run/docker.sock` existe → `"/var/run/docker.sock"`
  - `contextResolved`: grava `config.json` `{"currentContext":"colima"}` e `contexts/meta/<sha256("colima")>/meta.json` `{"Endpoints":{"docker":{"Host":"unix:///h/.colima/default/docker.sock"}}}`, e esse caminho existe → esse caminho
  - `knownPathFallback`: sem env nem config, só `<home>/.orbstack/run/docker.sock` existe → ele
  - `nothingFound`: `exists` sempre `false` → `nil`
- [ ] **Step 2:** `make test`. Esperado: FAIL (`DockerSocket` não existe).
- [ ] **Step 3:** Implementar `DockerSocket.discover`.
- [ ] **Step 4:** `make test`. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): discover docker socket from env, context and known paths`.

### Task 3: Modelos, tipo de status e agrupamento por compose

**Files:**
- Create: `Sources/GDockerCore/Docker/Models.swift`
- Test: `Tests/GDockerCoreTests/ModelsTests.swift`, `Tests/GDockerCoreTests/Fixtures/containers.json` (resource do alvo de teste)

**Interfaces:**
- Produces:
  - `public struct ContainerSummary: Decodable, Identifiable, Hashable, Sendable`, com `id`, `names: [String]`, `image`, `state`, `status`, `labels: [String: String]`, `ports: [PortBinding]` (chaves `Id`, `Names`, `Image`, `State`, `Status`, `Labels`, `Ports` da API), mais `var name: String` (primeiro nome sem `/`), `var composeProject: String?` (label `com.docker.compose.project`) e `var statusKind: StatusKind`
  - `public struct PortBinding: Decodable, Hashable, Sendable { ip: String?, privatePort: Int, publicPort: Int?, type: String }`
  - `public enum StatusKind: Sendable { case running, transitioning, stopped, failed }`
  - `public struct ContainerGroup: Identifiable, Sendable { public let project: String?; public let containers: [ContainerSummary]; id = project ?? "" }`
  - `public func groupByCompose(_ containers: [ContainerSummary]) -> [ContainerGroup]`
  - `public struct ContainerDetails: Decodable, Sendable`, com `id`, `name`, `config.image`, `config.env: [String]`, `config.tty: Bool`, `state.status`, `state.startedAt` (chaves da API `/containers/{id}/json`)

- [ ] **Step 1: Testes que falham.**
  - `decodeFixture`: decodifica `containers.json` (copiar uma resposta real de `curl --unix-socket … /v1.41/containers/json?all=1` e anonimizar). Espera que `name` não comece com `/`.
  - `statusKindMapping` (parametrizado): (`"running"`, `"Up 2 hours"`) → `.running`; (`"restarting"`, `"Restarting (1) 3 seconds ago"`) → `.transitioning`; (`"paused"`, …) → `.transitioning`; (`"created"`, …) → `.transitioning`; (`"exited"`, `"Exited (0) 3 days ago"`) → `.stopped`; (`"exited"`, `"Exited (2) 1 week ago"`) → `.failed`; (`"dead"`, …) → `.failed`
  - `grouping`: os containers `api`, `postgres` com projeto `myapp`, `nginx` sem projeto e `web` com projeto `blog` → grupos `[blog, myapp, nil]`, nesta ordem (alfabética, "sem grupo" por último), e os containers de cada grupo ordenados por `name`
- [ ] **Step 2:** `make test`. Esperado: FAIL.
- [ ] **Step 3:** Implementar. O código de saída sai de `status` com a regex `Exited \((\d+)\)`.
- [ ] **Step 4:** `make test`. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): container models, status kind and compose grouping`.

### Task 4: DockerClient — listar, inspecionar e ações

**Files:**
- Create: `Sources/GDockerCore/Docker/DockerClient.swift`, `Sources/GDockerCore/Docker/DockerError.swift`
- Test: `Tests/GDockerCoreTests/DockerErrorTests.swift`, `Tests/GDockerCoreTests/DockerClientIntegrationTests.swift`

**Interfaces:**
- Consumes: `DockerSocket.discover()`, `ContainerSummary`, `ContainerDetails`
- Produces:
  - `public enum DockerError: Error, Equatable, LocalizedError { case socketNotFound; case notFound(String); case conflict(String); case server(status: Int, message: String); case transport(String) }`
  - `static func from(status: Int, body: Data) -> DockerError?`: `2xx` e `304` → `nil`; `404` → `.notFound(msg)`; `409` → `.conflict(msg)`; o resto → `.server`. `msg` é o campo `message` do JSON, ou o corpo cru.
  - `public actor DockerClient`:
    - `init(socketPath: String)`
    - `static func connect() throws -> DockerClient` (lança `.socketNotFound`)
    - `func ping() async throws`
    - `func listContainers() async throws -> [ContainerSummary]` (`all=1`)
    - `func inspect(_ id: String) async throws -> (details: ContainerDetails, rawJSON: String)` (`rawJSON` formatado com `.prettyPrinted, .sortedKeys`)
    - `func start(_ id: String)`, `stop(_ id: String)`, `restart(_ id: String)`, `remove(_ id: String, force: Bool)`, todos `async throws`
    - `func shutdown() async`
  - URL base: `http+unix://<socketPath percent-encoded com .urlHostAllowed>/v1.41`. Usar um `HTTPClient` por `DockerClient`.

- [ ] **Step 1: Testes que falham.**
  - `DockerErrorTests`: `from(status: 204, body: Data())` → `nil`; `304` → `nil`; `404` com `{"message":"No such container: x"}` → `.notFound("No such container: x")`; `409` → `.conflict(…)`; `500` com corpo `"boom"` → `.server(status: 500, message: "boom")`
  - `DockerClientIntegrationTests` (`.enabled(if: DockerSocket.discover() != nil)`): `ping` não lança; `listContainers` não lança; `inspect("gdocker-nope-\(UUID())")` lança `.notFound`
- [ ] **Step 2:** `make test`. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** `make test`. Esperado: PASS (os de integração rodam aqui, porque o Colima está ativo).
- [ ] **Step 5:** Commit `feat(core): docker engine client with container actions`.

### Task 5: Logs — demux, buffer limitado e stream

**Files:**
- Create: `Sources/GDockerCore/Docker/Logs.swift`
- Modify: `Sources/GDockerCore/Docker/DockerClient.swift` (adicionar `logs`)
- Test: `Tests/GDockerCoreTests/LogsTests.swift`

**Interfaces:**
- Produces:
  - `public struct LogLine: Identifiable, Sendable, Hashable { public let id: Int; public let stream: Stream (.stdout/.stderr); public let timestamp: Date?; public let text: String }`
  - `public struct LogDemuxer { init(tty: Bool, timestamps: Bool); mutating func feed(_ bytes: [UInt8]) -> [LogLine] }`. Sem TTY: frames com cabeçalho de 8 bytes (`[stream, 0, 0, 0, size UInt32 big-endian]`). Com TTY: bytes crus, tudo stdout. Guarda frame e linha parciais entre chamadas. Separa linhas por `\n` e remove `\r` final. Decodifica com `String(decoding:as: UTF8.self)`. Com `timestamps`, tira o prefixo RFC3339Nano até o primeiro espaço e o põe em `timestamp`. O `id` é um contador crescente.
  - `public struct LogBuffer: Sendable { init(limit: Int = 5000); mutating func append(_ lines: [LogLine]); private(set) var lines: [LogLine] }`, que descarta as linhas mais antigas
  - `DockerClient.logs(_ id: String, tty: Bool, follow: Bool, tail: Int = 500, timestamps: Bool) -> AsyncThrowingStream<[LogLine], Error>`, que usa `stdout=1&stderr=1`. Cancelar o consumidor cancela a requisição (`onTermination`).

- [ ] **Step 1: Testes que falham.**
  - `demuxTwoFrames`: frame stdout `"hello\n"` + frame stderr `"oops\n"` → 2 linhas, streams `.stdout` e `.stderr`
  - `demuxSplitFrame`: o mesmo par de frames dividido no byte 5 e no byte 11 em três `feed` → as mesmas 2 linhas, no total
  - `demuxPartialLine`: frame `"ab"` e depois frame `"c\n"` → uma linha `"abc"`
  - `invalidUTF8`: frame com `[0x66, 0xFF, 0x0A]` → texto `"f\u{FFFD}"`
  - `ttyRaw`: `tty: true`, bytes `"x\r\ny\n"` → `["x", "y"]`
  - `timestampsParsed`: `"2026-11-12T14:02:11.123456789Z Server up\n"` → texto `"Server up"` e `timestamp` não nil
  - `bufferCap`: `LogBuffer(limit: 3)`, anexar 5 linhas → mantém as ids 3, 4 e 5
- [ ] **Step 2:** `make test`. Esperado: FAIL.
- [ ] **Step 3:** Implementar `LogDemuxer`, `LogBuffer` e `DockerClient.logs`.
- [ ] **Step 4:** `make test`. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): log demuxer, bounded buffer and log streaming`.

### Task 6: Stats

**Files:**
- Create: `Sources/GDockerCore/Docker/Stats.swift`
- Modify: `Sources/GDockerCore/Docker/DockerClient.swift` (adicionar `stats`)
- Test: `Tests/GDockerCoreTests/StatsTests.swift`

**Interfaces:**
- Produces:
  - `public struct StatsSample: Sendable { cpuPercent: Double; memoryUsed: UInt64; memoryLimit: UInt64; netRx: UInt64; netTx: UInt64 }`
  - `public static func StatsSample.from(json: Data) throws -> StatsSample?` (`nil` quando `precpu_stats.system_cpu_usage` falta, como no primeiro sample)
  - CPU% = `(cpu_stats.cpu_usage.total_usage − precpu.total_usage) / (cpu_stats.system_cpu_usage − precpu.system_cpu_usage) × online_cpus × 100`
  - memória = `memory_stats.usage − memory_stats.stats.inactive_file` (`inactive_file` ausente conta como 0)
  - rede = soma de `networks.*.rx_bytes` / `tx_bytes`
  - `DockerClient.stats(_ id: String) -> AsyncThrowingStream<StatsSample, Error>` (`stream=1`, um JSON por linha)

- [ ] **Step 1: Teste que falha.** `cpuAndMemory`: JSON com total 200→400, system 1000→2000, online_cpus 4, usage 600, inactive_file 100, limit 1000, eth0 rx 10 tx 20, eth1 rx 5 tx 5 → `cpuPercent == 80`, `memoryUsed == 500`, `netRx == 15`, `netTx == 25`. `firstSampleNil`: sem `precpu_stats.system_cpu_usage` → `nil`.
- [ ] **Step 2:** `make test`. Esperado: FAIL.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** `make test`. Esperado: PASS.
- [ ] **Step 5:** Commit `feat(core): container stats parsing and streaming`.

### Task 7: Janela principal — barra lateral e lista de containers

**Files:**
- Create: `Sources/GDocker/Stores/ContainersStore.swift`, `Sources/GDocker/Views/MainWindow.swift`, `Sources/GDocker/Views/ContainerList.swift`, `Sources/GDocker/Views/StatusDot.swift`
- Modify: `Sources/GDocker/GDockerApp.swift`, `Localizable.xcstrings`

**Interfaces:**
- Consumes: `DockerClient`, `groupByCompose`, `StatusKind`, `DockerError`
- Produces: `@MainActor @Observable final class ContainersStore`, com:
  - `groups: [ContainerGroup]`, `selectedID: String?`, `connected: Bool`, `lastError: String?`, `searchText: String`
  - `func start()`: loop com intervalo de 2 s; recria o `DockerClient` quando a conexão falha
  - `func perform(_ action: ContainerAction, on id: String) async`
  - `enum ContainerAction { case start, stop, restart, remove }`
  - `var selected: ContainerSummary?`

  Se o container selecionado some da lista, `selectedID` vira `nil`.

`// shortcut: polling a cada 2 s em vez de /events; trocar por /events se o custo de CPU incomodar`

- [ ] **Step 1:** Implementar o store e as views conforme o mockup 01:
  - `NavigationSplitView` com 3 colunas
  - barra lateral só com "Containers" e a contagem; o rodapé mostra "Docker connected/disconnected"
  - lista com busca (filtra por nome e imagem), cabeçalhos de seção com o nome do projeto em maiúsculas ou "No group"
  - linha com `StatusDot`, nome, imagem e o texto de status, que fica laranja ou vermelho em `.transitioning`/`.failed`
  - cores: `Color.green`, `.orange`, `.secondary` e `.red` do sistema, que se adaptam ao tema
  - todas as strings novas entram no catálogo com pt-BR
- [ ] **Step 2: Verificar** com `make run` e o Colima ativo: a lista bate com `docker ps -a`. Rodar `docker run -d --name gd-test alpine sleep 600` faz o container aparecer em até 2 s. `docker rm -f gd-test` com ele selecionado: some e a seleção é limpa.
- [ ] **Step 3: Verificar desconexão:** `colima stop` → o rodapé mostra "Docker desconectado" e o app continua aberto. `colima start` → a lista volta sozinha.
- [ ] **Step 4:** Commit `feat(app): main window with live container list`.

### Task 8: Detalhe do container — ações e abas Logs/Stats/Inspect/Env

**Files:**
- Create: `Sources/GDocker/Stores/LogsModel.swift`, `Sources/GDocker/Views/ContainerDetail.swift`, `Sources/GDocker/Views/LogsTab.swift`, `Sources/GDocker/Views/StatsTab.swift`, `Sources/GDocker/Views/InspectTab.swift`, `Sources/GDocker/Views/EnvTab.swift`
- Modify: `Localizable.xcstrings`

**Interfaces:**
- Consumes: `ContainersStore.perform`, `DockerClient.logs`, `.stats`, `.inspect`, `LogBuffer`
- Produces: `@MainActor @Observable final class LogsModel`, com:
  - `buffer: LogBuffer`, `filter: String`, `follow: Bool = true`, `showTimestamps: Bool = false`
  - `func attach(client: DockerClient, id: String, tty: Bool)`: cancela a task anterior
  - `var visibleLines: [LogLine]`

- [ ] **Step 1:** Implementar conforme o mockup 01:
  - cabeçalho com nome, imagem e portas publicadas, e os botões Reiniciar / Parar (ou Iniciar, quando parado) / Remover. Remover pede confirmação e usa `force: true` se o container estiver rodando.
  - os erros de `perform` aparecem num `.alert` com a mensagem do Docker.
  - Logs: `ScrollViewReader` + `LazyVStack` em fonte monoespaçada, com auto-scroll quando "Seguir" está ligado. O filtro é por substring sem diferenciar maiúsculas e minúsculas. stderr aparece em vermelho.
  - Stats: CPU%, memória usada/limite (`ByteCountFormatter`) e rede, atualizados pelo stream.
  - Inspect: `rawJSON` num `ScrollView` com `textSelection(.enabled)`.
  - Env: tabela chave/valor de `config.env`.
  - Trocar de container cancela os streams anteriores.
- [ ] **Step 2: Verificar** com `docker run -d --name gd-log alpine sh -c 'i=0; while true; do echo line $i; i=$((i+1)); sleep 0.01; done'`: os logs correm sem travar a UI, ficam limitados a 5000 linhas, o filtro "line 9" funciona e desligar "Seguir" para o auto-scroll. Parar, Iniciar, Reiniciar e Remover funcionam. Stats mostra CPU > 0. Remover `gd-log` com ele selecionado limpa o detalhe sem crash.
- [ ] **Step 3: Verificar o erro:** rodar `docker create --name gd-bad alpine /nao-existe`, selecionar o container e clicar em Iniciar → aparece um alerta com a mensagem do Docker (`…/nao-existe: no such file or directory`). Depois, `docker rm gd-bad`.
- [ ] **Step 4:** Commit `feat(app): container detail with actions, logs, stats, inspect and env`.

### Task 9: Preferências — tema e modo barra de menu

**Files:**
- Create: `Sources/GDocker/Settings/AppSettings.swift`, `Sources/GDocker/Settings/SettingsView.swift`, `Sources/GDocker/Views/MenuBarContent.swift`, `Sources/GDocker/AppDelegate.swift`
- Modify: `Sources/GDocker/GDockerApp.swift`, `Localizable.xcstrings`

**Interfaces:**
- Consumes: `ContainersStore`
- Produces:
  - `enum Theme: String, CaseIterable { case system, light, dark }`
  - chaves do `UserDefaults`: `"theme"` (padrão `system`) e `"keepInMenuBar"` (padrão `false`)
  - o plano 2 adiciona o status do MCP ao `MenuBarContent`

- [ ] **Step 1:** Implementar:
  - Cena `Settings` com um Picker de tema e um Toggle "Keep running in the menu bar when the window is closed".
  - O tema aplica `NSApp.appearance` (`nil` / `.aqua` / `.darkAqua`), que também cobre menus e alertas, ao abrir o app e ao mudar a opção.
  - `MenuBarExtra(isInserted: $keepInMenuBar)` mostra:
    - Docker conectado/desconectado
    - os containers rodando, com Reiniciar e Parar
    - "Open window" (`openWindow` + `NSApp.activate`)
    - "Quit"
  - `AppDelegate.applicationShouldTerminateAfterLastWindowClosed` devolve `!keepInMenuBar`.
  - Quando a última janela fecha com `keepInMenuBar`, aplicar `setActivationPolicy(.accessory)`. Ao abrir a janela, voltar para `.regular`.
- [ ] **Step 2: Verificar:**
  - Tema Escuro e Claro mudam na hora. Sistema segue a aparência do macOS.
  - Com a opção desligada, fechar a janela encerra o app.
  - Com a opção ligada, fechar a janela tira o ícone do Dock e deixa o ícone na barra de menu. Reiniciar um container pelo menu funciona, e "Abrir janela" traz a janela e o Dock de volta.
- [ ] **Step 3: Verificar o i18n:** `plutil -convert json -o - Sources/GDocker/Resources/Localizable.xcstrings | python3 -c 'import json,sys; d=json.load(sys.stdin)["strings"]; m=[k for k,v in d.items() if "pt-BR" not in v.get("localizations",{})]; print(m); sys.exit(bool(m))'`. Esperado: `[]`. Rodar o app em pt-BR (Task 1, passo 7) e percorrer todas as telas sem achar texto em inglês.
- [ ] **Step 4:** Commit `feat(app): theme, settings and menu bar mode`.
