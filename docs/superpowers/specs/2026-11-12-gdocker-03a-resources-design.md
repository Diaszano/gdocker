# gdocker — Design do Plano 3A (Recursos Docker: Imagens, Volumes e Redes)

## Intenção e O Porquê

O GDocker gerencia containers locais com excelência e segurança via MCP. No entanto, desenvolvedores e agentes de IA frequentemente precisam gerenciar o ciclo de vida completo do Docker local:
- Inspecionar quais imagens ocupam espaço em disco e remover imagens órfãs ou antigas.
- Listar volumes persistentes, verificar uso e limpar volumes sem containers associados.
- Visualizar redes criadas, identificar conflitos e remover redes não utilizadas.
- Executar limpeza geral de recursos obsoletos (*system prune*).

Este plano estende o núcleo do GDocker (`GDockerCore`), as capacidades de IA (`GDockerMCP`) e a interface gráfica do macOS (`GDocker`) para suportar esses três recursos fundamentais com total integração entre a interface nativa e as ferramentas expostas ao protocolo MCP.

---

## Objetivos

### 1. Núcleo Docker (`GDockerCore`)
- **Modelos de Dados:**
  - `ImageSummary`: ID, Repositório/Tags (`RepoTags`), Tamanho (`Size`), Data de criação (`Created`).
  - `VolumeSummary`: Nome (`Name`), Driver (`Driver`), Escopo (`Scope`), Data de criação (`CreatedAt`), Tamanho opcional (`UsageData.Size`).
  - `NetworkSummary`: ID (`Id`), Nome (`Name`), Driver (`Driver`), Escopo (`Scope`), Containers conectados (`Containers`).
  - `PruneReport`: Contagem detalhada de itens removidos (`containersDeleted`, `imagesDeleted`, `networksDeleted`, `volumesDeleted`) e espaço total recuperado em bytes (`spaceReclaimed`).
- **Cliente Docker (`DockerClient`):**
  - Imagens: `listImages()`, `removeImage(_ id: String, force: Bool)`, `pruneImages()`.
  - Volumes: `listVolumes()`, `removeVolume(_ name: String, force: Bool)`, `pruneVolumes()`.
  - Redes: `listNetworks()`, `removeNetwork(_ id: String)`, `pruneNetworks()`.
  - Containers: `pruneContainers()`.
  - Orquestração de Prune: `systemPrune(all: Bool, volumes: Bool)` executando a limpeza na ordem padrão do Docker (containers parados, redes órfãs, imagens não utilizadas, e volumes órfãos se `volumes == true`), retornando o `PruneReport` agregado.
- **Abstração e Testes:**
  - Extensão do protocolo `DockerOperations` contemplando todas as novas operações de listagem, remoção e prune.
  - Implementação completa em `FakeDocker` para testes unitários rápidos e determinísticos sem dependência do daemon real.

### 2. Ferramentas MCP (`GDockerCore` e `GDockerMCP`)
- Adição das novas ferramentas ao `ToolCatalog.all`:
  - **Leitura (Grupo `.read`, padrão `.allow`):**
    - `list_images`: Lista imagens locais com tags e tamanho.
    - `list_volumes`: Lista volumes com nome, driver e data de criação.
    - `list_networks`: Lista redes disponíveis com escopo e containers conectados.
  - **Destrutivo (Grupo `.destructive`, padrão `.deny`):**
    - `remove_image`: Deleta uma imagem pelo ID ou tag. Parâmetros: `image` (string, obrigatório), `force` (bool, opcional).
    - `remove_volume`: Deleta um volume pelo nome. Parâmetros: `volume` (string, obrigatório), `force` (bool, opcional).
    - `remove_network`: Deleta uma rede pelo ID ou nome. Parâmetros: `network` (string, obrigatório).
    - `system_prune`: Executa limpeza orquestrada de recursos não utilizados (containers parados, redes órfãs, imagens e volumes). Parâmetros: `all` (bool, opcional), `volumes` (bool, opcional).
- Roteamento no `ToolRouter`:
  - Validação de argumentos e resolução de nomes/IDs.
  - Interceptação pelo sistema de permissões (`allow`, `ask`, `deny`).
  - Prompts de aprovação via `ApprovalQueue` quando em modo `ask` (com motivo `reason`).
  - Registro de auditoria no `ActivityLog`.

### 3. Interface macOS (`GDocker`)
- **Barra Lateral:**
  - Itens adicionados sob a seção "Docker":
    - `Containers` (já existente, com contador).
    - `Images` (com contador).
    - `Volumes` (com contador).
    - `Networks` (com contador).
- **Telas Dedicadas:**
  - `ImagesView`: Tabela/lista com Tags, ID curto, Tamanho formatado e Data. Campo de busca, botão de remover imagem selecionada e botão de "Prune Images" (Limpar imagens não utilizadas).
  - `VolumesView`: Tabela/lista com Nome, Driver e Data. Campo de busca, botão de remover volume selecionado e botão de "Prune Volumes" (Limpar volumes órfãos).
  - `NetworksView`: Tabela/lista com Nome, Driver, Escopo e contagem de containers associados. Campo de busca e botão de remover rede selecionada (com proteção visual desabilitando remoção das redes padrão do sistema: `bridge`, `host`, `none`).
- **Ações Globais:**
  - Item de menu nativo `Docker > System Prune...` (Limpeza do Sistema) com diálogo de confirmação detalhado informando o que será excluído (containers parados, imagens não usadas, redes e volumes).
- **Confirmações:**
  - Ações destrutivas na UI (remoção individual e limpezas/prunes) exibem alerta nativo de confirmação antes do envio à Engine API.
- **Localização:**
  - Todas as novas strings adicionadas ao catálogo `Localizable.xcstrings` em inglês (`en`) e português (`pt-BR`), verificadas por `scripts/check_l10n.py`.

---

## Não-Objetivos

- **Docker Compose:** Gerenciamento de stacks, `compose_up`, `compose_down` e inspeção de projetos Compose são parte da Etapa B.
- **Terminal Interativo:** Sessão interativa PTY ou streaming de attach é parte da Etapa B.
- **Pull / Build de Imagens:** Operações interativas de longa duração com streaming de camadas de download (`docker pull`) ficam para um plano futuro. Aqui cobrimos as imagens já presentes localmente.

---

## Anti-Objetivos

- **Polling Agressivo:** Fazer requisições contínuas a cada 2 segundos para imagens, volumes e redes. Como esses dados mudam com pouca frequência, o polling agressivo desperdiçaria CPU e bateria no macOS.
- **Exclusão Acidental Sem Confirmação:** Permitir que cliques na UI deletem volumes com dados ou imagens sem um diálogo de confirmação claro.
- **Remoção de Redes Essenciais:** Permitir que o app solicite a exclusão de `bridge`, `host` ou `null/none`, o que corrompe o estado operacional do daemon Docker.

---

## Restrições e Premissas Técnicas

- **Compatibilidade:** macOS 14+ (Sonoma), Swift 6.3 com compilação em modo de concorrência completa.
- **Comunicação com Docker:** Apenas via Engine API através de sockets UNIX (Docker Desktop, Colima, OrbStack). Sem subprocessos chamando a CLI `docker`.
- **Limpeza de Conexões:** Todo `HTTPClient` / `DockerClient` criado deve ser explicitamente encerrado (`shutdown()`) ao ser descartado.
- **Commits e Branches:** Commits sem trailer de co-autoria por imposição do hook local.

---

## Abordagem Arquitetural Escolhida

**Abordagem 3 (Híbrida — Conexão Compartilhada e Atualização Sob Demanda):**
1. O `ContainersStore` permanece como fonte primária do `DockerClient` e gerencia o status geral de conectividade com o daemon Docker.
2. Criam-se stores leves e dedicados para cada domínio: `ImagesStore`, `VolumesStore` e `NetworksStore`.
3. Os stores secundários utilizam a conexão ativa do Docker.
4. Quando uma seção é ativada pelo usuário na barra lateral, os dados completos daquela seção são carregados (`refresh()`).
5. Um timer em background mais espaçado (15 a 30s) ou recarregamento após ações mutantes atualiza os contadores numéricos da barra lateral.

---

## O que é Deixado para quem Construir

- Formatação visual exata das colunas das tabelas (larguras ideais, alinhamento de números de bytes).
- Estrutura exata dos structs decodificados da Engine API (e.g., mapeamento de `Size` em bytes para formatação legível como MB/GB).
- Textos exatos dos diálogos de confirmação de exclusão e prune na interface.
