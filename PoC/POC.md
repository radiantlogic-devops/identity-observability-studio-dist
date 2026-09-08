# PoC — distributing Identity Observability Studio through Homebrew

End-to-end walkthrough of the proof of concept: every step actually performed,
with the commands, URLs and identifiers used.

| | |
| --- | --- |
| Status | **Working, validated end to end** |
| Date | 2026-09-08 |
| Test machine | macOS 26 (Darwin 25.6), Apple Silicon, Homebrew 6.0.22 |
| Result | 13/13 assertions green in [`test/verify-poc.sh`](test/verify-poc.sh), installed from a real GitHub release, launched by double-click |

What an end user types:

```bash
brew tap radiantlogic-devops/tap
brew trust --tap radiantlogic-devops/tap
brew install --cask radiantlogic-devops/tap/identity-observability-studio
xattr -dr com.apple.quarantine "/Applications/Identity Observability Studio.app"
open -a "Identity Observability Studio"
```

The full end-user documentation is in [`INSTALL_GUIDE.md`](INSTALL_GUIDE.md).

---

## The chain

```
Azure DevOps pipeline artifact          fetch-build-artifact.sh
  iGRCAnalyticsSetup_macosx_arm64_*.zip      (manual download during the PoC)
            │
            ▼
  build-studio-artifact.sh              repackaging: permissions, JRE, -vm,
            │                           Info.plist, code signature, ditto
            ▼
  IdentityObservabilityStudio-<v>-macos-arm64.zip  +  .sha256
            │
            ▼
  publish-release.sh                    GitHub release in
            │                           radiantlogic-devops/identity-observability-studio-dist
            ▼
  Casks/identity-observability-studio.rb          in radiantlogic-devops/homebrew-tap
            │
            ▼
  brew install --cask                   /Applications/Identity Observability Studio.app
```

---

## Step 1 — Get the build out of Azure DevOps

**What was done in the PoC:** the ZIP was downloaded by hand from the pipeline's
*Artifacts* tab and dropped into `studio-bin/`. Its origin was later recovered
from the quarantine metadata:

```bash
mdls -name kMDItemWhereFroms studio-bin/iGRCAnalyticsSetup_macosx_arm64_Eiffel-IDO-R2-SP2_2026-08-24.zip
```

```
https://artprodweu2.artifacts.visualstudio.com/A7aaad6e0-.../_apis/artifact/
  cGlwZWxpbmVhcnRpZmFjdDovL2J3LWRldi1vcHMvcHJvamVjdElkL2I5OWUxNmM5.../content
  ?format=file&subPath=%2FiGRCAnalyticsSetup_macosx_arm64_Eiffel-IDO-R2-SP2_2026-08-24.zip
```

The base64 segment decodes to the exact coordinates of the build:

```bash
echo 'cGlwZWxpbmVhcnRpZmFjdDovL2J3LWRldi1vcHMvcHJvamVjdElkL2I5OWUxNmM5LTM1N2YtNGZjOC1hMTE3LWFlZWE2NDg1OTMyMC9idWlsZElkLzU1NTgyL2FydGlmYWN0TmFtZS9pZ3JjLWluc3RhbGxlcnM1' | base64 -d
```

```
pipelineartifact://bw-dev-ops/projectId/b99e16c9-357f-4fc8-a117-aeea64859320/buildId/55582/artifactName/igrc-installers5
```

| | |
| --- | --- |
| Organization | `bw-dev-ops` — https://dev.azure.com/bw-dev-ops |
| Project id | `b99e16c9-357f-4fc8-a117-aeea64859320` |
| Build id | `55582` |
| Pipeline artifact | `igrc-installers5` |
| File | `iGRCAnalyticsSetup_macosx_arm64_Eiffel-IDO-R2-SP2_2026-08-24.zip` |

**Scripted form:** [`packaging/fetch-build-artifact.sh`](packaging/fetch-build-artifact.sh)
turns that manual download into a REST call, so the chain can be automated.

```bash
export AZDO_PAT=<PAT with scope "Build (read)">   # https://dev.azure.com/bw-dev-ops/_usersSettings/tokens
./packaging/fetch-build-artifact.sh --build-id 55582
```

> **Not exercised during the PoC.** The script encodes the same request the web
> UI issues (`GET /_apis/build/builds/<id>/artifacts?artifactName=...` then
> `downloadUrl` + `format=file&subPath=/<file>`), but it was never run against a
> live PAT. Validate it once before wiring it into CI.

## Step 2 — Analyse the binary

Before writing anything, the archive was examined and launched. It cannot start
on an Apple Silicon Mac, for four cumulative reasons — broken code signature,
ZIP without Unix permissions, no bundled JRE, and Eclipse writing inside its own
bundle.

Full detail, with the commands and their output:
**[`UPSTREAM_BUILD_DEFECTS.md`](UPSTREAM_BUILD_DEFECTS.md)**.

The headline: *Homebrew was never the problem*. Three of the four defects are
upstream packaging bugs that would break any distribution channel.

## Step 3 — Repackage into a distributable artifact

```bash
./packaging/build-studio-artifact.sh \
  --input studio-bin/iGRCAnalyticsSetup_macosx_arm64_Eiffel-IDO-R2-SP2_2026-08-24.zip
```

Roughly 35 s, of which 48 MB of JRE download. What each stage does:

| Stage | Fix |
| --- | --- |
| `ditto -x -k` + `xattr -cr` | extract, purge the quarantine inherited from the download |
| `chmod 755` | restore the executable bit on the launcher and on `igrc_*.sh` |
| Temurin JRE 21 (aarch64) | downloaded from the Adoptium API, **checksum verified**, installed into `Contents/Eclipse/jre` |
| patch `igrcanalytics.ini` | insert `-vm ../Eclipse/jre/bin/java` before `-vmargs` |
| rename the bundle | `Igrcanalytics.app` → `Identity Observability Studio.app` |
| patch `Info.plist` | align `CFBundleShortVersionString` / `CFBundleVersion` on the cask version, and `CFBundleName` / `CFBundleDisplayName` on the product name |
| `codesign` | sign the nested native code (JRE, `.so`/`.dylib`/`.jnilib`) **first**, then the bundle — `--deep` alone does not descend into `Contents/Eclipse` |
| `ditto -c -k --sequesterRsrc --keepParent` | repack **preserving permissions and symlinks** |

JRE source — the Adoptium v3 API, which also returns the checksum that the
script enforces:

```
https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=aarch64&image_type=jre&os=mac&vendor=eclipse
```

Measured output:

```
artifact : dist/IdentityObservabilityStudio-2026.08.24-macos-arm64.zip (721M / 740 032 205 bytes)
sha256   : b78276de62e60348f87e51013b86aca7223cdc767d42a5dbd16471336d996f9c
codesign --verify --deep --strict → valid on disk
```

Two things deliberately **not** renamed:

* `Contents/MacOS/igrcanalytics` and `Contents/Eclipse/igrcanalytics.ini` — the
  Eclipse launcher derives the path of its `.ini` from the executable name.
  Renaming one without the other breaks startup. Renaming the `.app` directory,
  on the other hand, has no effect on the launcher.
* `CFBundleIdentifier` = `com.brainwave.igrcanalytics.product` — this is the
  Eclipse product id (`-product` in the `.ini`, `.eclipseproduct`). Changing it
  would break startup and make users lose their preferences and keyring. It is
  also what keeps the cask's `zap` paths stable despite the rename.

The signature is **ad-hoc** by default. The day a certificate is available,
nothing else in the chain changes:

```bash
SIGN_IDENTITY="Developer ID Application: Radiant Logic, Inc. (TEAMID)" \
  ./packaging/build-studio-artifact.sh --input studio-bin/....zip
```

## Step 4 — Create the distribution repository

Hosting decision: **public GitHub release**, on the model of the already-public
`radiantlogic-devops/rlitools-dist`. The binary does not need to be private —
using the Studio requires a licence in any case.

```bash
brew install gh && gh auth login
```

```bash
gh repo create radiantlogic-devops/identity-observability-studio-dist \
  --public --description "macOS distribution artifacts for Identity Observability Studio"
```

> **Pitfall hit here.** Without `--add-readme`, `gh repo create` leaves the
> repository with **no commit at all**, and GitHub refuses to create a tag on an
> empty repository — step 5 failed with
> `HTTP 422: Validation Failed … Repository is empty.`
> The repository had to be seeded first:

```bash
git clone https://github.com/radiantlogic-devops/identity-observability-studio-dist.git /tmp/iosd
# add README.md and .gitignore
cd /tmp/iosd && git add README.md .gitignore && git commit -m "Init dist repo" && git push -u origin HEAD
```

The `.gitignore` ignores `*.zip`: archives belong in releases, never in git
history — otherwise every version adds 721 MB to the repository, irreversibly.

Clean up the draft release the failed attempt may have left behind:

```bash
gh release list --repo radiantlogic-devops/identity-observability-studio-dist
gh release delete v2026.08.24 --repo radiantlogic-devops/identity-observability-studio-dist --yes
```

## Step 5 — Publish the GitHub release

The tag and the asset name are **not free-form**: the cask's `url` stanza
rebuilds both from `version`.

| | |
| --- | --- |
| Tag | `v2026.08.24` |
| Asset | `IdentityObservabilityStudio-2026.08.24-macos-arm64.zip` |

What was run:

```bash
gh release create v2026.08.24 \
  --repo radiantlogic-devops/identity-observability-studio-dist \
  --title "Identity Observability Studio 2026.08.24" \
  --notes "macOS arm64. Bundled Temurin 21 JRE. Not notarised: see cask caveats." \
  dist/IdentityObservabilityStudio-2026.08.24-macos-arm64.zip
```

721 MB to upload, a few minutes. GitHub caps a single release asset at 2 GB, and
release assets do not count towards repository size — accumulating versions is
fine.

**Scripted form:** [`packaging/publish-release.sh`](packaging/publish-release.sh)
does the same thing, enforces the asset naming, refuses an asset over 2 GB,
verifies what GitHub actually stored, and prints the cask stanzas to update.

```bash
./packaging/publish-release.sh --version 2026.08.24 --dry-run   # then without --dry-run
```

Verification of the published asset — GitHub computes the digest server-side, so
there is no need to re-download 721 MB to be sure:

```bash
gh release view v2026.08.24 --repo radiantlogic-devops/identity-observability-studio-dist \
  --json assets --jq '.assets[] | "\(.name) \(.size) \(.digest) \(.state)"'
```

```
IdentityObservabilityStudio-2026.08.24-macos-arm64.zip  740032205  sha256:b78276de…  uploaded
```

Identical to the local artifact and to the cask's `sha256`. Anonymous access
confirmed with `HTTP 206`, `application/octet-stream`, ZIP magic bytes present.

## Step 6 — The cask

[`Casks/identity-observability-studio.rb`](Casks/identity-observability-studio.rb),
destined for `radiantlogic-devops/homebrew-tap`. Notable stanzas:

* `url` points at the release, with `verified: "github.com/radiantlogic-devops/"`
  — Homebrew requires it when the URL host does not match `homepage`;
* `livecheck` with `strategy :github_latest`, so `brew livecheck` follows the
  latest release;
* `depends_on macos: :big_sur` and `depends_on arch: :arm64`;
* **no Java dependency** — the Temurin 21 JRE is inside the bundle;
* `uninstall quit: "com.brainwave.igrcanalytics.product"`;
* `zap` restricted to paths derived from `CFBundleIdentifier`;
* `caveats` documenting the quarantine removal.

**The `zap` was corrected during the PoC, and it mattered.** The first version
listed `~/.eclipse_keyring`, `~/.eclipse/` and `~/eclipse-workspace`. Those are
*generic Eclipse locations shared with every other Eclipse product on the
machine* — three other Eclipse installations were present on the test machine —
so zapping them would have destroyed another product's data. They were removed,
and the corrected zap was verified in real conditions with witness files:

```
==> Trashing files:
~/Library/Caches/com.brainwave.igrcanalytics.product
~/Library/Preferences/com.brainwave.igrcanalytics.product.plist
~/Library/Saved Application State/com.brainwave.igrcanalytics.product.savedState
```

`~/eclipse-workspace`, `~/.eclipse` and `~/.eclipse_keyring`: untouched.

## Step 7 — Get the cask into the tap

```bash
cd homebrew-tap && git checkout -b feat/identity-observability-studio-cask
git add Casks/identity-observability-studio.rb README.md
git commit -m "Add identity-observability-studio cask"
git push -u origin feat/identity-observability-studio-cask
```

> **Blocked here:** `ERROR: Permission to radiantlogic-devops/homebrew-tap.git
> denied`. The account is `pull: true, push: false` on the tap. That is by
> design — a public tap is code executed on users' machines (a cask can run
> arbitrary `preflight`/`postflight` scripts, which is exactly why Homebrew 6
> introduced tap trust). Review by a tap owner is the normal counterpart.

The workaround is also the normal contribution path — fork, then PR:

```bash
gh repo fork --remote --remote-name fork --clone=false
git push -u fork feat/identity-observability-studio-cask
```

```bash
gh pr create --repo radiantlogic-devops/homebrew-tap \
  --head jmcorne:feat/identity-observability-studio-cask \
  --title "Add identity-observability-studio cask" \
  --body "..."
```

**The PR is what makes the cask installable by anyone else.** Until it is merged
into `radiantlogic-devops/homebrew-tap`, `brew tap radiantlogic-devops/tap`
(no second argument) resolves to the org repo, which does not have the cask.

For the PoC, the tap was pointed at the fork while keeping the canonical name —
so the install command under test is byte-for-byte the one an end user will type:

```bash
brew tap radiantlogic-devops/tap https://github.com/jmcorne/homebrew-tap
git -C "$(brew --repository)/Library/Taps/radiantlogic-devops/homebrew-tap" \
  checkout feat/identity-observability-studio-cask
HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask radiantlogic-devops/tap/identity-observability-studio
```

`brew tap` has **no `--branch` flag** — the two-argument form plus a `git
checkout` in the tap directory is the way to test a branch; Homebrew simply
loads what is on disk.

## Step 8 — Install and verify

```bash
./test/verify-poc.sh --fresh
```

[`test/verify-poc.sh`](test/verify-poc.sh) replays the whole user journey and
checks 13 assertions: tap visible, cask resolved, clean reinstall, executable
bits preserved, code signature sealed and valid, bundle identifier unchanged,
JRE present, `-vm` pointing at it, quarantine cleared, the embedded `libjvm`
actually loaded by the launcher, and the process still alive.

Measured results, installing from the real GitHub release:

| Step | Result |
| --- | --- |
| `brew tap` | tap installed, status `Untrusted` |
| Homebrew 6 trust | prompt raised, install blocked until approval |
| Download | 740 032 205 bytes from GitHub in ~30 s |
| Checksum | `b78276de…` — the cask's, verified by Homebrew |
| Install | `/Applications/Identity Observability Studio.app`, 39 s total |
| Quarantine set by Homebrew | 3 870 files |
| After `xattr -dr` | 0 files, bundle seal valid |
| Double-click launch | embedded Temurin 21 JVM loaded, workbench started, no Gatekeeper dialog |

---

## Homebrew 6 specifics worth knowing

### Quarantine can no longer be bypassed by a cask

`Cask::Quarantine.available?` is true on macOS, and both `--no-quarantine` and
the `quarantine false` stanza are gone. Homebrew sets the attribute on all
3 870 files of the bundle and **a cask cannot remove it**. Verified: the
embedded JRE is killed (`exit 137`) as long as quarantine is present.

This is the Headlamp strategy: the cask documents it in `caveats`, the user runs
one explicit command. Measured on macOS 26:

| State | `open -a` |
| --- | --- |
| quarantine set, ad-hoc signature | killed by AMFI |
| quarantine cleared, valid ad-hoc signature | **starts, no dialog** |

The `com.apple.provenance` attribute (macOS 15+) stays on all 3 870 files and
**cannot be removed** (`xattr -d` returns 0 but does nothing) — no observed
effect on launching.

Notarisation is what removes this friction entirely — see
[`APPLE_SIGNING_AND_DISTRIBUTION.md`](APPLE_SIGNING_AND_DISTRIBUTION.md).

### Third-party taps must be trusted

New in Homebrew 6: a non-official tap is `Untrusted` and its content is not
loaded until approved. The approval is stored in `~/.homebrew/trust.json`.

```bash
brew trust --tap radiantlogic-devops/tap
brew trust --json v1     # list what is actually trusted
```

Two findings:

* **Trust is indexed on the remote URL, not the canonical name.** Because the
  tap was created with a custom remote, `trust.json` contains
  `https://github.com/jmcorne/homebrew-tap/identity-observability-studio`, not
  `radiantlogic-devops/tap/…`. After the merge, users get the canonical entry.
* **`brew tap-info` reports tap-level trust only.** It shows `Untrusted` even
  when the individual cask is trusted and installs fine. Use
  `brew trust --json v1` instead — the guide was corrected on this point.

### `brew update` resets taps to their default branch

This silently made the cask disappear mid-test and broke the first install
attempt. Hence `HOMEBREW_NO_AUTO_UPDATE=1` while testing from a branch.

### Do not run `brew audit` on this cask

It switches Homebrew into developer mode and installs a `json` gem that
conflicts with portable-ruby's, which breaks `brew info`. Repair:

```bash
git -C "$(brew --repository)" config --local --unset homebrew.devcmdrun
rm -rf "$(brew --repository)"/Library/Homebrew/vendor/bundle/ruby/*/gems/json-*
```

---

## Replaying the PoC

```bash
# 1. produce the artifact (~35 s, downloads 48 MB of JRE)
./packaging/build-studio-artifact.sh \
  --input studio-bin/iGRCAnalyticsSetup_macosx_arm64_Eiffel-IDO-R2-SP2_2026-08-24.zip

# 2. copy the printed sha256 into Casks/identity-observability-studio.rb

# 3. expose the local tap to Homebrew (symlink: edits are picked up immediately,
#    unlike `brew tap`, which clones)
mkdir -p "$(brew --repository)/Library/Taps/radiantlogic-devops"
ln -sfn "$PWD/homebrew-tap" \
  "$(brew --repository)/Library/Taps/radiantlogic-devops/homebrew-tap"

# 4. verify
./test/verify-poc.sh --fresh
```

Rollback:

```bash
brew uninstall --cask identity-observability-studio
rm "$(brew --repository)/Library/Taps/radiantlogic-devops/homebrew-tap"
```

To test the cask against a local artifact instead of the release, swap the `url`
stanza for `url "file:///path/to/dist/IdentityObservabilityStudio-#{version}-macos-arm64.zip"`
— it is the only line that changes.

---

## What remains, by decreasing value

1. **Fix the build pipeline.** Defects 1–3 are upstream packaging bugs, not
   Homebrew constraints. Produce the ZIP on a macOS runner with
   `ditto -c -k --sequesterRsrc --keepParent`, bundle the JRE, and sign the
   bundle after injecting content. `build-studio-artifact.sh` documents exactly
   the operations to port.
2. **Get an Apple Developer ID and notarise.** Removes the `xattr` command, i.e.
   the only remaining user friction. Requires defect 4 to be fixed first. Full
   process, prerequisites and costs:
   [`APPLE_SIGNING_AND_DISTRIBUTION.md`](APPLE_SIGNING_AND_DISTRIBUTION.md).
3. **Merge the cask PR** into `radiantlogic-devops/homebrew-tap`.
4. **Automate cask updates.** The tap already has a GoReleaser integration for
   `eocctl`; the cask can follow the same path (automatic PR bumping `version`
   and `sha256`).
5. **Intel / universal.** The cask is locked to `arch: :arm64`. An x86_64 build
   needs a second artifact and an `on_intel` block.

### Hosting options that were considered and dropped

Only the `url` stanza differs between them:

* `dist.saas.radiantlogic.com` behind **Cloudflare Access** — what the `rlitools`
  downloader works around for `eocctl`. A cask would need a download strategy
  injecting a service token or a `cloudflared access token`.
* **Private GitHub release** plus the `custom_download_strategy.rb` already in
  the tap, which requires each user to set `HOMEBREW_GITHUB_API_TOKEN`.
