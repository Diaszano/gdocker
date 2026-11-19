# Arquitetura de Segurança

**Idiomas:** [🇺🇸 English](security.md) • 🇧🇷 **Português**

O GDocker expõe operações Docker para clientes de IA locais via MCP e monta volumes Docker no Finder via WebDAV. As seções abaixo descrevem as proteções que mantêm ambas as superfícies locais e sob controle do usuário.

## Isolamento do Servidor MCP

- **Bind exclusivo em loopback:** O servidor HTTP SwiftNIO embarcado escuta exclusivamente em `127.0.0.1`, nunca em interfaces de rede externas.
- **Validação de `Host` e `Origin`:** Requisições com cabeçalhos `Host` ou `Origin` não-locais são rejeitadas (mitigando ataques de DNS rebinding e chamadas cross-site via navegador).
- **Autenticação por Bearer Token:** Toda requisição HTTP exige `Authorization: Bearer <token>`. O token é gerado aleatoriamente e armazenado no Keychain do macOS. Regenerar o token passa a valer imediatamente.
- **Limite de payload:** Corpos de requisição acima do limite são rejeitados (`413 Payload Too Large`).

## Controle de Permissões e Aprovações

- **Padrão seguro:** Ferramentas de leitura e ciclo de vida não-destrutivo vêm como *Permitir*; operações mutáveis ou sensíveis (`get_container_env`, `stop_container`, `exec_in_container`, `compose_up`, `compose_down`, `remove_container`) vêm como *Perguntar*; operações destrutivas (`remove_image`, `remove_volume`, `remove_network`, `system_prune`) vêm como *Negar*.
- **Aprovação por comando exato:** Aprovações de `exec_in_container` valem apenas para o comando exato exibido no prompt e não podem ser promovidas para *Sempre permitir*.
- **Fail-closed por timeout:** Prompts sem resposta são negados automaticamente após 2 minutos.
- **Mascaramento de variáveis de ambiente:** Valores são mascarados (`***`) na inspeção de containers; ler os valores reais exige uma chamada explícita a `get_container_env`.

## Montagem de Volumes no Finder (WebDAV)

Ao abrir um volume Docker no Finder, o GDocker cria uma montagem WebDAV local efêmera (`GDocker.local`) restrita ao volume selecionado, sem expor o sistema de arquivos do host.

## Reportando Vulnerabilidades

Veja [SECURITY.md](../SECURITY.md) para instruções sobre como reportar vulnerabilidades de forma privada.
