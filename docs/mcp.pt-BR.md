# Servidor MCP e Clientes de IA

**Idiomas:** [🇺🇸 English](mcp.md) • 🇧🇷 **Português**

O GDocker possui um servidor **Model Context Protocol (MCP)** integrado para que assistentes de IA inspecionem e gerenciem seu ambiente Docker local sob permissões explícitas por ferramenta.

## Iniciando o Servidor

1. Abra **Permissões** na barra lateral do GDocker e ative o servidor MCP.
2. Opcionalmente, ative **Iniciar servidor MCP ao abrir o app** em **Ajustes**.
3. O servidor escuta em `http://127.0.0.1:7391/mcp` por padrão (porta configurável nos Ajustes).

> [!IMPORTANT]
> O GDocker precisa estar aberto para os clientes de IA conseguirem se conectar ao servidor MCP.

## Configuração nos Clientes

Clique em **Copiar config** na tela de **Permissões** para copiar o snippet pronto com sua porta e token atuais.

### Claude Code (HTTP)

```sh
claude mcp add --transport http gdocker http://localhost:7391/mcp --header "Authorization: Bearer <token>"
```

### Cursor e Clientes HTTP Genéricos (JSON `mcpServers`)

```json
{
  "mcpServers": {
    "gdocker": {
      "url": "http://localhost:7391/mcp",
      "headers": {
        "Authorization": "Bearer <token>"
      }
    }
  }
}
```

### Claude Desktop (Ponte `--stdio`)

O Claude Desktop usa transporte stdio. Passe `--stdio` para o executável do GDocker — ele encaminha as chamadas para o app em execução via localhost e lê o token bearer automaticamente do Keychain do macOS:

```json
{
  "mcpServers": {
    "gdocker": {
      "command": "/Applications/GDocker.app/Contents/MacOS/GDocker",
      "args": ["--stdio"]
    }
  }
}
```

## Catálogo de Ferramentas e Políticas Padrão

Cada ferramenta pode ser configurada como **Permitir**, **Perguntar** ou **Negar** na tela de **Permissões**:

| Padrão | Ferramentas |
| --- | --- |
| **Permitir** | `list_containers`, `inspect_container`, `get_logs`, `get_stats`, `list_images`, `list_volumes`, `list_networks`, `list_compose_projects`, `start_container`, `restart_container` |
| **Perguntar** | `get_container_env`, `stop_container`, `exec_in_container`, `compose_up`, `compose_down`, `remove_container` |
| **Negar** | `remove_image`, `remove_volume`, `remove_network`, `system_prune` |

### Proteções Adicionais

- **Mascaramento de ambiente:** Valores de variáveis de ambiente são substituídos por `***` em `inspect_container` e em todos os outros lugares, exceto em `get_container_env`.
- **Aprovação exata de comando:** Aprovar `exec_in_container` autoriza apenas aquele comando exato e nunca oferece *Sempre permitir*.
- **Timeout de aprovação:** Prompts sem resposta são negados automaticamente após 2 minutos.
- **Trilha de auditoria:** Todas as chamadas MCP (permitidas, aprovadas, negadas ou com erro) ficam registradas em **Atividade de IA** na barra lateral.
