# gdocker — Design do Plano 3B (Docker Compose: Projetos, Orquestração e Ferramentas MCP)

## Intenção e O Porquê

O GDocker gerencia containers individuais com facilidade, mas desenvolvedores modernos quase sempre utilizam **Docker Compose** para orquestrar suas aplicações locais (bancos de dados, APIs, filas e caches).
Hoje, o GDocker já agrupa containers visualmente por projeto Compose na lista principal de containers. No entanto:
1. Quando todos os containers de uma stack sofrem `down`, eles desaparecem da Engine API e o app perde o rastro do projeto, impossibilitando subir a stack novamente pela UI.
2. Não há uma visão consolidada de projetos Compose com controle do ciclo de vida da stack inteira (`Up`, `Down`, `Restart`).
3. Agentes de IA via protocolo MCP não têm ferramentas dedicadas para inspecionar e orquestrar projetos Compose (`list_compose_projects`, `compose_up`, `compose_down`).

Este plano estende o núcleo do GDocker (`GDockerCore`), as capacidades de IA (`GDockerMCP`) e a interface gráfica macOS (`GDocker`) para adicionar gerenciamento completo de projetos Docker Compose.

---

## Objetivos

### 1. Núcleo Docker Compose (`GDockerCore`)
- **Modelos de Dados:**
  - `ComposeServiceSummary: Sendable, Codable, Equatable, Identifiable`:
    - `var id: String { name }`
    - `name: String` (nome do serviço, ex: `web`, `db`)
    - `containerID: String?` (ID do container associado se estiver criado/rodando)
    - `state: String?` (estado do container, ex: `running`, `exited`)
    - `statusKind: StatusKind?` (running, transitioning, stopped, failed)
  - `ComposeStatus: String, Sendable, Codable`:
    - `running`: todos os containers dos serviços estão ativos
    - `partiallyRunning`: alguns serviços estão ativos e outros parados/exited
    - `stopped`: todos os containers dos serviços existem mas estão parados/exited
    - `down`: nenhum container ativo existe para o projeto (recuperado do registro)
  - `ComposeProject: Sendable, Codable, Equatable, Identifiable`:
    - `var id: String { name }`
    - `name: String` (nome do projeto/stack)
    - `workingDir: String` (diretório raiz do projeto)
    - `configFiles: [String]` (caminhos dos arquivos de configuração, ex: `docker-compose.yml`)
    - `services: [ComposeServiceSummary]` (serviços conhecidos da stack; quando em `down`, preserva nomes dos serviços com containerID/state nulos)
    - `status: ComposeStatus`
  - `ComposeProjectRecord: Sendable, Codable, Equatable`:
    - Registro serializável em JSON para persistência em disco:
      - `name: String`
      - `workingDir: String`
      - `configFiles: [String]`
      - `serviceNames: [String]` (nomes dos serviços aprendidos das labels dos containers)
      - `lastSeen: Date`
- **Persistência e Agregação (`ComposeProjectRegistry`):**
  - Salva em disco (`Application Support/GDocker/compose_projects.json` ou caminho injetável em testes) metadados dos projetos vistos a partir das labels dos containers.
  - Métodos:
    - `ingest(containers: [ContainerSummary])`: aprende e atualiza projetos e serviços vistos a partir das labels `com.docker.compose.*`.
    - `removeProject(named: String)`: esquece uma stack do registro (ação manual do usuário).
    - `projects(containers: [ContainerSummary]) -> [ComposeProject]`: sintetiza a lista unificada de projetos ativos e em down, calculando o status e mapeando os serviços.
  - Permite recuperar projetos mesmo quando todos os containers foram removidos por `down`.
- **Executor CLI (`ComposeOperations` e `CLIComposeRunner`):**
  - Protocolo `ComposeOperations`:
    - `func composeUp(project: String, workingDir: String, configFiles: [String]) async throws -> String`
    - `func composeDown(project: String, workingDir: String, configFiles: [String], removeVolumes: Bool) async throws -> String`
    - `func isComposeAvailable() async -> Bool`
  - Implementação `CLIComposeRunner`:
    - Localização do executável `docker`: busca em `/usr/local/bin/docker`, `/opt/homebrew/bin/docker`, `~/.docker/cli-plugins/docker-compose`, `/usr/bin/docker` ou via `PATH`.
    - Execução via `Process` assíncrono em background sem bloquear a MainActor, capturando stdout e stderr.
    - Argumentos: `docker compose -f <file1> -f <file2> --project-directory <dir> up -d` / `down` (com `-v` caso `removeVolumes == true`).
    - Configura `DOCKER_HOST` apontando para o socket ativo descoberto via `DockerSocket.discover()`.
  - Implementação `FakeComposeRunner`:
    - Double para testes unitários determinísticos em `GDockerCoreTests` sem dependência de CLI externo ou daemon real.

### 2. Ferramentas MCP (`GDockerCore` e `GDockerMCP`)
- **Novas Ferramentas em `ToolCatalog.all` (total de 17 para 20 ferramentas):**
  - `list_compose_projects`: Grupo `.read`, padrão `.allow`. Lista todos os projetos Compose conhecidos (ativos e em down) com working directory, arquivos de configuração, serviços e status.
  - `compose_up`: Grupo `.control`, padrão `.ask`. Parâmetros: `project` (string, obrigatório). Inicia todos os serviços do projeto especificado (`docker compose up -d`).
  - `compose_down`: Grupo `.control`, padrão `.ask`, `allowsAlways: false` (exige aprovação humana a cada chamada para proteger contra remoção inadvertida de volumes). Parâmetros: `project` (string, obrigatório), `remove_volumes` (bool, opcional, default false). Para e remove containers e redes do projeto (`docker compose down`).
- **Roteamento no `ToolRouter`:**
  - Injeção de `registry: ComposeProjectRegistry` e `compose: @Sendable () async -> (any ComposeOperations)?`.
  - Antes de executar qualquer ferramenta de compose, sincroniza o registro chamando `docker.listContainers()` e `registry.ingest(containers)`.
  - Validação de parâmetros e resolução de diretório/arquivos através do `ComposeProjectRegistry`. Retorna erro claro se o diretório do projeto não existir no disco.
  - Prompts de aprovação via `ApprovalQueue` quando em `.ask`.
  - Auditoria no `ActivityLog`.

### 3. Interface macOS (`GDocker`)
- **Barra Lateral (`MainWindow.swift`):**
  - Adição do item `Compose` na seção "Docker" (com ícone `square.stack.3d.forward.dottedline` e contador ao vivo de projetos ativos).
- **Store Dedicado (`ComposeStore`):**
  - `@MainActor @Observable final class ComposeStore`:
    - Lista de projetos filtráveis por busca (`searchText`).
    - Integração viva com `ContainersStore`: ao atualizar containers, chama `registry.ingest(containers)` e atualiza `projects = registry.projects(containers:)`.
    - Métodos assíncronos: `refresh()`, `up(project:)`, `down(project:removeVolumes:)`, `forget(project:)`.
    - Tratamento de status de CLI disponível (`isComposeAvailable: Bool`).
- **Tela Dedicada (`ComposeView.swift`):**
  - Tabela/lista de projetos Compose com Nome, Status (badge de cor: verde para `running`, amarelo para `partiallyRunning`, cinza para `stopped`, azul/cinza para `down`), Serviços e Diretório.
  - Detalhe ou expansão com os serviços da stack e seus containers.
  - Ações no topo/linha: botão `Up`, botão `Down` (com alerta de confirmação e toggle opcional de remover volumes).
  - Ação "Esquecer projeto" (context menu ou botão quando em `down`).
  - Tratamento de erro amigável se a pasta do projeto não existir ao tentar subir (`"Directory not found"`).
  - Estado vazio e banner de aviso quando o CLI `docker compose` não for encontrado na máquina.
- **Localização:**
  - Todas as strings em inglês (`en`) e português do Brasil (`pt-BR`) em `Localizable.xcstrings`, validadas com `scripts/check_l10n.py`.

---

## Não-Objetivos

- Criação ou edição de arquivos `docker-compose.yml` dentro do app.
- Suporte a stacks Docker Swarm (`docker stack deploy`).
- Build de imagens interativo de longa duração durante o `compose up` (o comando usa `-d` com imagens locais/puxadas).
- Terminal PTY interativo (faz parte do marco de Terminal).

---

## Anti-Objetivos

- Bloquear a UI do app ou o loop de eventos enquanto o comando `docker compose up` ou `down` executa.
- Executar `compose up` ou `compose down` via MCP sem passar pela fila de aprovação quando a permissão for `.ask`.
- Apagar volumes silenciosamente no `compose down` sem confirmação explícita do usuário.
- Travar ou crashar caso o usuário não tenha o CLI `docker` instalado.

---

## Restrições e Premissas Técnicas

- macOS 14+ (Sonoma), Swift 6.1 / Swift 6.3 modo de concorrência.
- O CLI `docker compose` deve ser executado respeitando o socket do Docker ativo (`DOCKER_HOST` configurado para o socket descoberto caso necessário).
- Todos os testes devem rodar via `make test` sem necessidade do daemon real ou CLI real.
- Commits no formato Conventional Commits sem trailers de co-autoria.

---

## Abordagens Consideradas

### Abordagem 1: Puramente Engine API (sem CLI externo)
- Tenta recriar o comportamento do compose usando apenas endpoints `/containers/create`.
- *Rejeitada:* Exigiria reimplementar em Swift o parser completo da especificação Compose YAML, interpolação de `.env`, criação de redes e volumes. É extremamente frágil e incompatível com projetos reais.

### Abordagem 2: Híbrida — Leitura via Engine API + Orquestração via CLI `docker compose` (Escolhida)
- A Engine API fornece o estado real dos containers ativos em tempo de execução via labels.
- O executável `docker compose` oficial da máquina é chamado apenas para as mutações de orquestração (`up`, `down`).
- Um registro persistente mantém os projetos vistos em disco para suportar o estado `down`.
- *Vantagens:* Compatibilidade total com Compose v2, suporte a volumes e `.env`, zero reimplementação de YAML, conformidade com a decisão 52 do design mestre.

---

## O que é Deixado para quem Construir

- Localização exata e ordem de busca dos caminhos padrão do binário `docker` no macOS.
- Design exato da linha da tabela de Compose (estilo dos badges de status `running`, `partiallyRunning`, `down`).
- Formatação exata do diálogo de confirmação de `compose down`.
