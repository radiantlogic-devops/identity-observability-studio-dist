# identity-observability-studio-dist

Artefacts de distribution macOS de **Identity Observability Studio**, le Studio
Eclipse de la plateforme Radiant Logic Identity Observability.

Ce dépôt ne contient pas de code : il ne sert qu'à héberger les archives
publiées dans les *releases*, consommées par le cask Homebrew.

## Installation

```bash
brew install --cask radiantlogic-devops/tap/identity-observability-studio
```

Voir [`radiantlogic-devops/homebrew-tap`](https://github.com/radiantlogic-devops/homebrew-tap)
pour le cask et les étapes post-installation.

## Contenu d'une release

| | |
| --- | --- |
| Tag | `v<version>`, par exemple `v2026.08.24` |
| Asset | `IdentityObservabilityStudio-<version>-macos-arm64.zip` |
| Architecture | Apple Silicon (arm64) |
| JRE | Temurin 21 embarqué dans le bundle — aucune dépendance Java externe |
| Signature | ad-hoc, **non notarisée** par Apple |

Le nom du tag et celui de l'asset sont reconstruits par le cask à partir de sa
strophe `version` : les renommer casse l'installation.

L'archive est produite par `packaging/build-studio-artifact.sh` à partir du ZIP
sortant du pipeline de build, qui n'est pas directement distribuable en l'état.
