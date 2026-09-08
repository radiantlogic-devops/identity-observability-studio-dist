# Identity Observability Studio — macOS Installation Guide

For macOS on Apple Silicon (M1 and later). Installation is handled by
[Homebrew](https://brew.sh), so upgrades and removal are one command each.

> **Status: preview.** The cask is not yet merged into the official Radiant
> Logic tap. Until it is, use the commands in
> [Preview installation](#preview-installation) instead of step 3 below.

---

## Requirements

| | |
| --- | --- |
| Hardware | Apple Silicon (arm64). Intel Macs are not supported. |
| macOS | 11 Big Sur or later |
| Java | **None.** A Temurin 21 runtime ships inside the application. |
| Disk space | ~1.7 GB during install, ~870 MB once installed |
| Licence | A valid Radiant Logic licence is required to use the Studio. Installing it does not grant one. |

Check your hardware if you are unsure:

```bash
uname -m
```

`arm64` means you are on Apple Silicon. If it prints `x86_64`, this package
will not run on your machine.

---

## Install

### 1. Install Homebrew

Skip if `brew --version` already works.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. Add the Radiant Logic tap

```bash
brew tap radiantlogic-devops/tap
```

Homebrew 6 requires you to explicitly trust third-party taps before it will
load anything from them:

```bash
brew trust --tap radiantlogic-devops/tap
```

### 3. Install the Studio

```bash
brew install --cask radiantlogic-devops/tap/identity-observability-studio
```

This downloads about 740 MB and installs
`/Applications/Identity Observability Studio.app`.

### 4. Approve the application

**This step is required — the Studio will not start without it.**

```bash
xattr -dr com.apple.quarantine "/Applications/Identity Observability Studio.app"
```

The application is signed but not notarised by Apple. Homebrew marks every
download with a quarantine attribute, and macOS refuses to launch quarantined
software that Apple has not notarised. The command above removes that
attribute, which is your explicit statement that you trust this application.

Prefer not to use the terminal? See
[Approving without the terminal](#approving-without-the-terminal).

### 5. Launch

```bash
open -a "Identity Observability Studio"
```

Or open it from Launchpad or the Applications folder. First start takes
30–60 seconds while the workbench initialises.

---

## Preview installation

While the cask is still under review, install it from the review branch:

```bash
brew tap radiantlogic-devops/tap https://github.com/jmcorne/homebrew-tap
```

```bash
git -C "$(brew --repository)/Library/Taps/radiantlogic-devops/homebrew-tap" checkout feat/identity-observability-studio-cask
```

```bash
HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask radiantlogic-devops/tap/identity-observability-studio
```

`HOMEBREW_NO_AUTO_UPDATE=1` matters: `brew update` resets taps to their default
branch, which would silently make the cask disappear again. Then continue with
steps 4 and 5 above.

---

## Troubleshooting

### "Identity Observability Studio is damaged and can't be opened"

The quarantine attribute is still present, or only partially removed. Re-run
step 4, then confirm nothing is left:

```bash
xattr -r -p com.apple.quarantine "/Applications/Identity Observability Studio.app" | wc -l
```

It must print `0`.

### "Operation not permitted" when running xattr

Your terminal lacks permission to modify applications. Open **System Settings →
Privacy & Security → App Management** and enable your terminal application,
then run the command again.

### Approving without the terminal

1. Open the Studio and let macOS block it. Click **Done**.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the security section — a message names the blocked application.
4. Click **Open Anyway** and confirm.

### The application starts, then nothing appears

First start is slow — up to a minute — and there is no progress indicator after
the splash screen closes. Confirm it is still working:

```bash
pgrep -fl "Identity Observability Studio"
```

If a process is listed, it is still initialising.

### Homebrew says the cask is unavailable

Either the tap is not trusted, or `brew update` reset it to a branch without
the cask. Check what Homebrew currently trusts:

```bash
brew trust --json v1
```

If neither `radiantlogic-devops/tap` nor the cask appears, re-run step 2's
`brew trust` command. Note that `brew tap-info` reports *tap-level* trust only,
so it can show `Untrusted` even when the individual cask is trusted and
installs fine — use the command above instead.

---

## Update

```bash
brew upgrade --cask radiantlogic-devops/tap/identity-observability-studio
```

**Repeat step 4 after every upgrade.** Homebrew replaces the whole application
bundle and quarantines the new copy, so the previous approval does not carry
over.

---

## Uninstall

Remove the application:

```bash
brew uninstall --cask identity-observability-studio
```

Remove the application **and** your personal settings, keyring and caches:

```bash
brew uninstall --zap --cask identity-observability-studio
```

If you already ran the plain `brew uninstall` above, add `--force` so Homebrew
still cleans up even though the cask is no longer installed:

```bash
brew uninstall --zap --force --cask identity-observability-studio
```

`--zap` is irreversible. It removes only files specific to this application —
its macOS caches, preferences and saved window state.

It deliberately leaves the generic Eclipse locations alone:

| Path | Why it is kept |
| --- | --- |
| `~/eclipse-workspace` | Your projects. Also the default workspace for any other Eclipse installed on the machine. |
| `~/.eclipse_keyring` | Shared credential store, used by every Eclipse product. |
| `~/.eclipse/` | Shared Eclipse state. |

Delete those by hand only if you have no other Eclipse installation and you are
sure you want to lose their contents.

---

## What gets installed

| Path | Contents |
| --- | --- |
| `/Applications/Identity Observability Studio.app` | The application, including its Temurin 21 runtime |
| `~/eclipse-workspace` | Your workspace, created on first launch. Shared with any other Eclipse on the machine. |
| `~/.eclipse/` | Shared Eclipse state, created on first launch |

Nothing is installed outside your user account and `/Applications`, and no
background service or launch agent is registered.

The application keeps its own configuration inside its bundle, so it writes
very little to your home directory.

The distributed archive is published at
[`radiantlogic-devops/identity-observability-studio-dist`](https://github.com/radiantlogic-devops/identity-observability-studio-dist/releases).
Homebrew verifies its SHA-256 checksum on download, so a corrupted or tampered
archive fails the install rather than being installed.
