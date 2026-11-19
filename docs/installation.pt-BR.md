# Guia de Instalação

**Idiomas:** [🇺🇸 English](installation.md) • 🇧🇷 **Português**

## Requisitos

- **macOS 14 (Sonoma)** ou superior (binário universal para Apple Silicon e Intel)
- Um dos runtimes Docker suportados rodando localmente:
  - **Docker Desktop**
  - **OrbStack**
  - **Colima**
  - **Rancher Desktop**
- CLI `docker` no seu `PATH` (necessário para ações do Docker Compose e para a aba Terminal interativo)

## Instalar via Homebrew (Recomendado)

O GDocker é distribuído como Cask do Homebrew pelo tap [`Diaszano/homebrew-tap`](https://github.com/Diaszano/homebrew-tap):

```sh
brew trust --cask diaszano/tap/gdocker
brew install --cask diaszano/tap/gdocker
```

### Atualizar

```sh
brew upgrade --cask gdocker
```

### Desinstalar

```sh
brew uninstall --cask gdocker
```

Para remover também preferências e dados em `Application Support`:

```sh
brew uninstall --zap --cask gdocker
```

## Instalação Manual (GitHub Releases)

1. Baixe `GDocker-<version>.zip` e `SHA256SUMS` em [GitHub Releases](https://github.com/Diaszano/gdocker/releases).
2. Verifique o checksum do arquivo:
   ```sh
   shasum -a 256 -c SHA256SUMS
   ```
3. Descompacte e mova `GDocker.app` para `/Applications/`.
4. Remova o atributo de quarentena do macOS (o GDocker usa assinatura ad-hoc e não é notarizado pela Apple):
   ```sh
   xattr -dr com.apple.quarantine /Applications/GDocker.app
   ```

## Primeira Execução e Aviso do Keychain

Como cada versão recebe uma nova assinatura ad-hoc, o macOS pedirá sua senha de login uma vez por versão para o GDocker ler o token bearer do MCP no Keychain. Escolha **Sempre Permitir** para não ser perguntado novamente.

## Compilar a partir do Código-Fonte

Requer **Xcode 16.4+** (Swift 6.1+):

```sh
git clone https://github.com/Diaszano/gdocker.git
cd gdocker
make app
```

O app compilado é gerado em `build/GDocker.app`. Para compilar e abrir diretamente:

```sh
make run
```

Para compilar um binário universal (`arm64` + `x86_64`):

```sh
make app SWIFT_FLAGS="--arch arm64 --arch x86_64"
```
