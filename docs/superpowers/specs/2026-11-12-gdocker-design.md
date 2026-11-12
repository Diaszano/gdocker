# gdocker — Design

Data: 2026-11-12
Status: aguardando aprovação

## Intenção

Um app nativo de macOS, em Swift, que faz o papel do [lazydocker](https://github.com/jesseduffield/lazydocker), mas com interface gráfica. Ele também roda um **servidor MCP** embutido, para que uma IA (Claude Code, Claude Desktop, Cursor etc.) possa ver e controlar o Docker. Um **sistema de permissões** define o que a IA pode fazer.

**Por quê:** o dono do projeto usa o lazydocker principalmente para ver os containers rodando, ler os logs e reiniciar ou parar containers. Ele quer o mesmo fluxo numa janela nativa e quer que a IA faça essas tarefas (e "muito mais") sem ficar copiando e colando logs, mas sob controle dele.

Mockups: arquivo do Penpot, Page 1, telas `01 · Containers + Logs`, `02 · Permissões do MCP` e `03 · Aprovação da IA`. O layout foi aprovado pelo dono ("de resto está legal").

## Objetivos

1. **Containers:** listar os containers com status ao vivo, agrupados pelo projeto do compose (label `com.docker.compose.project`). Também ter Iniciar, Parar, Reiniciar e Remover.
2. **Logs:** acompanhar ao vivo (follow), com filtro de texto e a opção de mostrar timestamps.
3. **Detalhe do container:** abas Logs, Stats (CPU/memória), Inspect, Env e Terminal (shell interativo via exec).
4. **Outros recursos:** listar Imagens, Volumes, Redes e projetos Compose, com as ações básicas de cada um (remover; up/down no compose).
5. **Servidor MCP** embutido, expondo ferramentas para tudo o que o app faz. O dono quer que a IA faça "isso e muito mais", então o conjunto de ferramentas deve cobrir a superfície do app, não só o mínimo.
6. **Permissões do MCP:** cada ação tem um destes estados: **Permitir**, **Perguntar** ou **Negar**.
   - **Perguntar** abre um aviso de aprovação (tela 03) que mostra o cliente, a ferramenta, os argumentos e o motivo, com os botões Negar e Permitir uma vez, e a caixa "Sempre permitir", que muda a regra para Permitir.
   - **Negar** devolve um erro para a IA, explicando que a ação foi bloqueada pelo usuário.
7. **i18n:** português (pt-BR) e inglês, seguindo o idioma do sistema.
8. **Tema claro e escuro:** segue o sistema, com opção de forçar Claro ou Escuro nas preferências.
9. **Modo barra de menu (opcional, nas preferências):** com a opção ligada, fechar a janela não encerra o app. Ele continua com um ícone na barra de menu e o servidor MCP segue rodando. Com a opção desligada, fechar a janela encerra o app.
10. **Distribuição via Homebrew** (cask), fora da App Store.

## Não-objetivos

- App Store e sandbox. O sandbox bloqueia o acesso ao socket do Docker.
- Kubernetes, Docker Swarm e hosts Docker remotos (v1 só usa o host local).
- Chat com IA dentro do app. A IA vive no cliente MCP, não no gdocker.
- Construir imagens (build) ou editar Dockerfile/compose dentro do app.

## Anti-objetivos (seria um fracasso mesmo funcionando)

- A IA conseguir executar uma ação marcada como **Negar**, ou executar uma ação **Perguntar** sem a aprovação explícita do usuário.
- O servidor MCP ficar acessível por outras máquinas da rede.
- O app parecer um wrapper web. Ele tem que parecer e se comportar como um app de Mac.

## Restrições e decisões

| Item | Decisão | Origem |
|---|---|---|
| Linguagem/UI | Swift + SwiftUI | dono |
| Distribuição | Homebrew cask, fora da App Store, sem sandbox | dono |
| i18n | pt-BR + en (String Catalog) | dono pediu i18n; idiomas são palpite do assistente, aceito sem objeção |
| Tema | Claro/escuro seguindo o sistema + override | dono pediu; override é palpite do assistente |
| Fechar → barra de menu | Opcional, nas preferências | dono |
| Acesso ao Docker | API HTTP do Engine pelo socket Unix, sem shell para o CLI `docker` | assistente; aceito pelo dono ("Ok") |
| Exceção: compose | `compose_up`/`compose_down` (app e MCP) chamam `docker compose` com a pasta e os arquivos do projeto (labels `com.docker.compose.project.working_dir` / `.config_files`). O app guarda os projetos já vistos para poder subir de novo depois de um `down`. Se o CLI não existir, os botões de compose ficam desabilitados com uma explicação. | dono |
| Segurança do MCP | Exigir bearer token (gerado na 1ª execução, guardado no Keychain, incluído no "Copiar config"; botão para gerar outro). Rejeitar requisições cujo `Host`/`Origin` não seja localhost, para bloquear DNS rebinding. O nome do cliente vem do próprio cliente e serve só para exibir. | decisão do assistente |
| Clientes só-stdio | O mesmo executável aceita `--stdio` e funciona como ponte stdio→HTTP para o servidor do app aberto. "Copiar config" oferece as duas formas. | decisão do assistente |
| SDK MCP | SDK oficial em Swift. Se ele não tiver transporte HTTP de servidor, quem constrói escolhe a alternativa, mantendo o mesmo comportamento. | decisão do assistente |
| Runtime suportado | Docker Desktop, OrbStack e Colima: descobrir o socket via contexto atual / `DOCKER_HOST` / caminhos conhecidos | assistente |
| Transporte MCP | HTTP Streamable em `127.0.0.1` (porta padrão 7391, configurável), via SDK oficial de MCP em Swift | assistente; aceito pelo dono |
| macOS mínimo | 14 (Sonoma) | assistente; aceito pelo dono |
| Granularidade das permissões | Por ação (ferramenta), não por container | assistente; mostrado no mockup, sem objeção |

### Ferramentas MCP e permissões padrão (palpite do assistente, visível no mockup 02)

| Grupo | Ferramentas | Padrão |
|---|---|---|
| Leitura | `list_containers`, `inspect_container`, `get_logs`, `get_stats`, `list_images`, `list_volumes`, `list_networks`, `list_compose_projects` | Permitir |
| Controle | `start_container`, `restart_container` | Permitir |
| Leitura sensível | `get_container_env` (valores das variáveis de ambiente) | Perguntar |
| Controle | `stop_container`, `exec_in_container`, `compose_up`, `compose_down` | Perguntar |
| Destrutivo | `remove_container` | Perguntar |
| Destrutivo | `remove_image`, `remove_volume`, `remove_network`, `system_prune` | Negar |

As ferramentas aceitam um argumento opcional `reason`, que o aviso de aprovação mostra.

Regras decididas pelo dono:
- **Segredos:** `inspect_container` e as demais ferramentas devolvem as variáveis de ambiente com os valores mascarados (`***`). Os valores só saem por `get_container_env`. Os logs não são mascarados.
- **Exec:** `exec_in_container` roda um comando e devolve stdout, stderr e o código de saída, sem sessão interativa. A aprovação vale só para aquele comando exato, e o aviso **não** mostra "Sempre permitir". Para liberar geral, o usuário muda a regra na tela de Permissões.

### Telas

- **Janela principal** (mockup 01): barra lateral (Docker: Containers, Imagens, Volumes, Redes, Compose; IA: status do servidor MCP, Permissões, Atividade da IA), lista no meio e detalhe à direita.
- **Permissões** (mockup 02): cartão do servidor (endereço, clientes conectados, Copiar config, Parar/Iniciar) e lista de ações com o seletor de três estados.
- **Aprovação** (mockup 03): aviso não modal à janela principal, que aparece mesmo com a janela fechada (modo barra de menu) e traz o app para frente.
- **Atividade da IA:** histórico das chamadas MCP (data/hora, cliente, ferramenta, argumentos, resultado: permitido/aprovado/negado/erro).
- **Barra de menu:** status do Docker e do MCP, containers rodando com reiniciar/parar, Abrir janela, Encerrar.
- **Preferências:** tema, modo barra de menu, porta do MCP, iniciar servidor MCP ao abrir o app.

## Deixado para quem construir

- Arquitetura interna, organização dos módulos e camada de cliente do Docker.
- Como implementar o Terminal (biblioteca de terminal ou view própria).
- Onde persistir as permissões e o histórico (UserDefaults, arquivo JSON, SwiftData).
- Formato exato do "Copiar config" para cada cliente.
- Tempo de espera do aviso de aprovação antes de negar automaticamente.
- Ícone do app e da barra de menu.
- Pipeline do cask (release no GitHub, assinatura e notarização).
