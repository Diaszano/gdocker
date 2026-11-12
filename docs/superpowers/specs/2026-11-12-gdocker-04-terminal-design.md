# gdocker — Design do Plano 4 (Terminal interativo no detalhe do container)

## Intenção e O Porquê

O design mestre (objetivo 3) prevê, no detalhe do container, as abas Logs, Stats, Inspect, Env e **Terminal** (shell interativo via exec). As quatro primeiras já existem; falta o Terminal.
Hoje, para entrar num container, o usuário sai do gdocker, abre outro terminal e digita `docker exec -it <container> sh`. O objetivo é ter esse shell dentro da janela do app, ao lado dos logs do mesmo container, no mesmo fluxo de "olhar → agir" que motivou o projeto.

---

## Objetivos

### 1. Aba Terminal (`GDocker`)
- Nova aba **Terminal** em `ContainerDetail.Tab` (depois de `Env`).
- Usa o **SwiftTerm** (dependência nova do target `GDocker`), com `LocalProcessTerminalView` embrulhado em `NSViewRepresentable`.
- O processo local é o CLI do Docker num pseudo-terminal:
  `docker exec -it <containerID> /bin/sh -c 'command -v bash >/dev/null 2>&1 && exec bash || exec sh'`
  (abre `bash` se existir no container, senão `sh`).
- Ambiente do processo: `TERM=xterm-256color` e `DOCKER_HOST=unix://<socket>` com o socket de `DockerSocket.discover()` — mesma regra do `CLIComposeRunner`.
- Redimensionar a janela/painel redimensiona o PTY (o SwiftTerm já repassa ao processo; o `docker exec -it` repassa ao container).
- Ctrl-C, Ctrl-D, setas, cores, `vim`/`top` funcionam como num terminal comum — comportamento do próprio `docker exec -it`.
- Copiar/colar e seleção com o mouse: o que o SwiftTerm oferece por padrão.
- Fonte monoespaçada do sistema; cores do terminal seguem o tema claro/escuro do app.

### 2. Ciclo de vida da sessão
- A sessão começa quando o usuário abre a aba Terminal pela primeira vez para aquele container.
- Trocar de aba (Logs ↔ Terminal) **mantém** a sessão viva enquanto o mesmo container continuar selecionado.
- Selecionar outro container, fechar a janela ou o container parar encerra a sessão (o processo `docker exec` é terminado).
- Quando o shell termina (usuário digita `exit`, container parou, erro), a aba mostra uma faixa "Sessão encerrada (código N)" com o botão **Reconectar**, que abre uma sessão nova.

### 3. Estados de exceção
- **Container fora de `running`** (decisão do assistente): a sessão só abre com `state == "running"` — não `isActive`, porque `docker exec` falha em container `paused`/`restarting`.
  - `exited`/`created`/`dead`: estado vazio "O container não está rodando" com o botão **Iniciar** (mesma ação do cabeçalho).
  - `paused`/`restarting`: estado vazio com a mensagem correspondente ("O container está pausado" / "O container está reiniciando"), sem botão (o app não tem ação de despausar).
- **CLI `docker` não encontrado:** estado vazio explicando que o Terminal precisa do CLI do Docker instalado, no mesmo padrão do aviso do Compose.
- **Container sem `sh`** (imagens distroless/scratch): o `docker exec` falha e a mensagem de erro do CLI aparece no próprio terminal, seguida da faixa "Sessão encerrada" — sem tratamento especial.

### 4. Núcleo compartilhado (`GDockerCore`)
- Extrair do `CLIComposeRunner` a resolução do binário e a montagem do `DOCKER_HOST` para um helper reutilizável (ex.: `DockerCLI`). Decisões do assistente:
  - O helper resolve só o binário **`docker`** (nunca o plugin `docker-compose`), em lista fixa de caminhos: `/usr/local/bin/docker`, `/opt/homebrew/bin/docker`, `~/.orbstack/bin/docker`, `/Applications/Docker.app/Contents/Resources/bin/docker`, `/usr/bin/docker`. Sem busca no `PATH`: app aberto pelo Finder recebe `PATH` mínimo, então não ajudaria.
  - O Terminal usa esse binário `docker`. O Compose usa a mesma lista e, se nenhum `docker` existir, cai no plugin standalone `~/.docker/cli-plugins/docker-compose` como hoje (mantendo o tratamento de `hasSuffix("docker-compose")`). A única mudança para o Compose é ganhar os caminhos novos do OrbStack/Docker Desktop.
  - Testes fixam: ordem da lista, que o Terminal nunca recebe o plugin, e o fallback do Compose para o plugin.
- Função pura que monta os argumentos e o ambiente do exec do terminal (`terminalExecCommand(containerID:socketPath:) -> (executable, args, env)`), testável sem CLI nem daemon.

### 5. Localização
- Todas as strings novas em `en` e `pt-BR` no `Localizable.xcstrings`, validadas por `scripts/check_l10n.py`.

---

## Não-Objetivos

- Ferramenta MCP para terminal interativo. A IA continua com `exec_in_container` (comando único, aprovação a cada uso).
- Várias sessões/abas de terminal por container, ou terminal destacado em janela separada.
- Escolher usuário, shell ou diretório de trabalho do exec na UI.
- Persistir histórico/scrollback entre sessões.
- Registrar a sessão no `ActivityLog` (ele audita só chamadas MCP).

---

## Anti-Objetivos

- Travar a UI enquanto a sessão abre ou fecha.
- Deixar processos `docker exec` órfãos rodando depois que a sessão "acabou" na UI (ao trocar de container, fechar janela ou encerrar o app).
- Crashar quando o CLI `docker` não existir ou o container parar no meio da sessão.
- O terminal parecer algo que não é um terminal de Mac (fonte proporcional, cores erradas no tema escuro, teclas que não chegam ao shell).

---

## Restrições e Premissas Técnicas

- macOS 14+, Swift 6.1/6.3 com concorrência estrita. O `LocalProcessTerminalView` é AppKit e vive na `@MainActor`.
- **Exceção ao "sem CLI" do design mestre:** o Terminal passa a chamar o CLI `docker`, como o Compose. Decidido pelo dono (abordagem A abaixo).
- SwiftTerm via Swift Package Manager, versão estável mais recente compatível com macOS 14.
- `make test` continua passando sem daemon real nem CLI real: os testes cobrem a montagem do comando/ambiente e a resolução do binário; a view não tem teste automatizado (o target `GDocker` não tem target de teste).
- Commits em Conventional Commits, primeira linha ≤ 72 caracteres, sem trailers de co-autoria de IA.

---

## Abordagens Consideradas

### A. `docker exec -it` num PTY via `LocalProcessTerminalView` do SwiftTerm (Escolhida pelo dono)
- O SwiftTerm abre o processo local num pseudo-terminal e cuida de resize, sinais e fim de processo.
- *Vantagens:* pouquíssimo código; comportamento idêntico ao `docker exec -it` real; reaproveita a resolução de binário/socket do Compose.
- *Custos:* segunda exceção ao "sem CLI"; depende do CLI instalado; difícil de testar sem o CLI.

### B. Hijack da Engine API com SwiftNIO no `GDockerCore`
- `POST /exec/{id}/start` com `Upgrade: tcp` direto no socket Unix, bytes nos dois sentidos para um `TerminalView` puro, resize via `POST /exec/{id}/resize`.
- *Rejeitada:* muito mais código de rede (HTTP manual, upgrade, ciclo de vida da conexão), mais frágil; o ganho (não depender do CLI) não compensa para o dono.

### C. Como B, usando Network.framework (`NWConnection` com socket Unix)
- *Rejeitada:* mesmo trabalho de B com uma API que o projeto não usa.

---

## O que é Deixado para quem Construir

- Nome e lugar exato do helper compartilhado de CLI e da função que monta o comando.
- Como guardar a sessão viva entre trocas de aba (ex.: um modelo `@Observable` por container em `ContainerDetail`, como o `LogsModel`).
- Como garantir o término do processo no fim da sessão (ex.: `terminate()` do SwiftTerm no `dismantleNSView`/troca de container e no encerramento do app).
- Paleta exata de cores do terminal nos temas claro e escuro.
- Layout da faixa "Sessão encerrada" e dos estados vazios.
