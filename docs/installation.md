# Installation Guide

**Languages:** 🇺🇸 **English** • [🇧🇷 Português](installation.pt-BR.md)

## Requirements

- **macOS 14 (Sonoma)** or later (universal binary for Apple Silicon and Intel)
- One of the supported local Docker runtimes:
  - **Docker Desktop**
  - **OrbStack**
  - **Colima**
  - **Rancher Desktop**
- The `docker` CLI on your `PATH` (required for Docker Compose actions and the interactive Terminal tab)

## Install via Homebrew (Recommended)

GDocker is distributed as a Homebrew Cask through [`Diaszano/homebrew-tap`](https://github.com/Diaszano/homebrew-tap):

```sh
brew trust --cask diaszano/tap/gdocker
brew install --cask diaszano/tap/gdocker
```

### Upgrade

```sh
brew upgrade --cask gdocker
```

### Uninstall

```sh
brew uninstall --cask gdocker
```

To also remove saved settings and application support data:

```sh
brew uninstall --zap --cask gdocker
```

## Manual Installation (GitHub Releases)

1. Download `GDocker-<version>.zip` and `SHA256SUMS` from [GitHub Releases](https://github.com/Diaszano/gdocker/releases).
2. Verify the archive checksum:
   ```sh
   shasum -a 256 -c SHA256SUMS
   ```
3. Unzip and move `GDocker.app` to `/Applications/`.
4. Remove the macOS quarantine attribute (GDocker is ad-hoc signed, not Apple-notarized):
   ```sh
   xattr -dr com.apple.quarantine /Applications/GDocker.app
   ```

## First Launch & Keychain Prompt

Because each release is ad-hoc signed with a fresh signature, macOS will ask for your login password once per version so GDocker can access its MCP bearer token in the Keychain. Select **Always Allow** to avoid repeated prompts.

## Build from Source

Requires **Xcode 16.4+** (Swift 6.1+):

```sh
git clone https://github.com/Diaszano/gdocker.git
cd gdocker
make app
```

The built application bundle is created at `build/GDocker.app`. To build and launch immediately:

```sh
make run
```

To build a universal (`arm64` + `x86_64`) app bundle:

```sh
make app SWIFT_FLAGS="--arch arm64 --arch x86_64"
```
