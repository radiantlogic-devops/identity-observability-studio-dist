# identity-observability-studio-dist

macOS distribution artifacts for **Identity Observability Studio**, the Eclipse
Studio of the Radiant Logic Identity Observability platform.

This repository contains no source code: it only hosts the archives published
in *releases*, which are consumed by the Homebrew cask.

## Installation

```bash
brew install --cask radiantlogic-devops/tap/identity-observability-studio
```

See [`radiantlogic-devops/homebrew-tap`](https://github.com/radiantlogic-devops/homebrew-tap)
for the cask and post-installation steps.

## Release contents

| | |
| --- | --- |
| Tag | `v<version>`, for example `v2026.08.24` |
| Asset | `IdentityObservabilityStudio-<version>-macos-arm64.zip` |
| Architecture | Apple Silicon (arm64) |
| JRE | Temurin 21 bundled in the app — no external Java dependency |
| Signature | ad-hoc, **not notarized** by Apple |

The tag name and the asset name are reconstructed by the cask from its
`version` stanza: renaming them will break installation.

The archive is produced by `packaging/build-studio-artifact.sh` from the ZIP
coming out of the build pipeline, which is not directly distributable as-is.
