# PoC — Homebrew distribution of Identity Observability Studio

Working notes, scripts and analysis behind the macOS distribution of the Studio.
Kept in this repository because this is where the released archives live.

Related ticket: **IDO-1282 — Verify that Studio works on macOS**.

## Read in this order

| Document | What it answers |
| --- | --- |
| [`UPSTREAM_BUILD_DEFECTS.md`](UPSTREAM_BUILD_DEFECTS.md) | Why the ZIP produced by the Azure DevOps pipeline cannot start on an Apple Silicon Mac — four cumulative defects, with the commands that prove each one |
| [`POC.md`](POC.md) | The full walkthrough: every step, command and URL used to get from the pipeline artifact to `brew install --cask` |
| [`INSTALL_GUIDE.md`](INSTALL_GUIDE.md) | End-user installation guide (English), the deliverable for macOS arm64 users |
| [`APPLE_SIGNING_AND_DISTRIBUTION.md`](APPLE_SIGNING_AND_DISTRIBUTION.md) | How to make this a properly Apple-signed app — Developer ID + notarisation, the Mac App Store question, Apple Developer Program Organization prerequisites, costs, and a request template for C-Level |

## Scripts

| Script | Role | Exercised in the PoC |
| --- | --- | --- |
| [`packaging/fetch-build-artifact.sh`](packaging/fetch-build-artifact.sh) | Pull the macOS installer out of the Azure DevOps pipeline artifact | No — the ZIP was downloaded by hand; the script encodes the same REST call |
| [`packaging/build-studio-artifact.sh`](packaging/build-studio-artifact.sh) | Turn that ZIP into a distributable, signed artifact with a bundled JRE | Yes |
| [`packaging/publish-release.sh`](packaging/publish-release.sh) | Publish the artifact as a GitHub release asset and print the cask stanzas | Scripted form of the `gh release create` run by hand |
| [`test/verify-poc.sh`](test/verify-poc.sh) | Replay the whole user journey, 13 assertions | Yes — 13/13 green |

Reference copy of the cask under review:
[`Casks/identity-observability-studio.rb`](Casks/identity-observability-studio.rb).
The authoritative copy lives in
[`radiantlogic-devops/homebrew-tap`](https://github.com/radiantlogic-devops/homebrew-tap).

## The short version

```
Azure DevOps artifact ──▶ build-studio-artifact.sh ──▶ GitHub release ──▶ Homebrew cask
```

The pipeline artifact is not distributable as-is: broken code signature, ZIP
without Unix permissions, no Java runtime. `build-studio-artifact.sh` fixes all
three and documents exactly what should be ported into the build pipeline.

The one remaining user-visible friction — a manual `xattr -dr
com.apple.quarantine` — disappears the day the application is notarised by
Apple, which needs an Apple Developer Program Organization membership
(99 USD/year) and one product-side fix.
