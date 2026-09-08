# Defects of the binary produced by the Azure DevOps build pipeline

Subject of the analysis:

| | |
| --- | --- |
| Artifact | `iGRCAnalyticsSetup_macosx_arm64_Eiffel-IDO-R2-SP2_2026-08-24.zip` |
| Origin | Azure DevOps, org `bw-dev-ops`, project `b99e16c9-357f-4fc8-a117-aeea64859320`, build `55582`, pipeline artifact `igrc-installers5` |
| Test machine | macOS 26 (Darwin 25.6), Apple Silicon |

The four defects below are **cumulative**: each one alone is enough to stop the
Studio from launching. None of them is caused by Homebrew — the archive cannot
start on an Apple Silicon Mac whatever the distribution channel.

---

## 1. The bundle signature is broken by the build

The Eclipse launcher still carries the signature it inherited from upstream:

```
$ codesign -dv Igrcanalytics.app
Authority=Developer ID Application: Eclipse Foundation, Inc. (JCDTMS22B4)
Identifier=SigningServlet-3891350600729875247-unsigned-eclipse
```

But injecting `Contents/Eclipse/` and `Resources/igrc.icns` into the bundle
*after* it was signed removed `Contents/_CodeSignature/`. The CodeDirectory of
the main binary therefore points at a resource seal that no longer exists:

```
$ codesign --verify --deep --strict Igrcanalytics.app
Igrcanalytics.app: code has no resources but signature indicates they must be present

$ ./Igrcanalytics.app/Contents/MacOS/igrcanalytics
Killed: 9          # exit 137
```

On Apple Silicon every process must carry a valid signature, so **AMFI (Apple
Mobile File Integrity) kills the process at load time**. This is what produces
the *"the application is damaged and can't be opened"* dialog.

This is **not Gatekeeper**, and no amount of quarantine handling fixes it.

## 2. The ZIP is produced without Unix permissions

```
$ unzip -Z -l ...zip | grep MacOS/igrcanalytics
-rw----     2.0 fat    76800 ...   Igrcanalytics.app/Contents/MacOS/igrcanalytics
                  ^^^                ^^^^^^^
```

The archive is written with **`fat` (Windows) attributes**: no executable bit,
and no symlink at all (0 symlinks across 3 079 entries). After extraction the
launcher is `-rw-r--r--` → `Permission denied`.

Consistent with the artifact's origin — an Azure DevOps pipeline, confirmed by
its `kMDItemWhereFroms` metadata.

## 3. No bundled JRE, and no `-vm` in the `.ini`

`Contents/Eclipse/igrcanalytics.ini` has no `-vm` stanza, and the bundle
embeds no Java runtime. The Eclipse launcher then looks for a JVM through the
JavaVM framework, then through `PATH`. Neither works on a realistic machine:

* `/usr/libexec/java_home` returns nothing when Java came from
  `brew install openjdk@21` — that formula is *keg-only* and is never
  registered in `/Library/Java/JavaVirtualMachines`;
* launched from the Finder, the process inherits a minimal `PATH`
  (`/usr/bin:/bin:/usr/sbin:/sbin`) that contains no JDK.

So the Studio does not start even on a machine that "has Java installed".

## 4. Eclipse writes inside its own bundle on first launch

```
$ codesign --verify --deep --strict "/Applications/Identity Observability Studio.app"
a sealed resource is missing or invalid
file added: .../Contents/Eclipse/configuration/org.eclipse.osgi/.manager/.fileTableLock
file added: .../Contents/Eclipse/configuration/org.eclipse.osgi/framework.info.1
file added: .../Contents/Eclipse/configuration/org.eclipse.equinox.launcher/.../splash.bmp
```

Equinox uses `Contents/Eclipse/configuration/` as its writable configuration
area, which **breaks the code signature seal of the bundle on first launch**.

* **No consequence today.** Gatekeeper only evaluates a bundle on first launch,
  and `brew upgrade` replaces the whole bundle.
* **Blocking the day the app is notarised.** A stapled, notarised app that
  rewrites itself will fail re-validation, and Homebrew 6 tries to carry the
  Gatekeeper approval from one version to the next by comparing signing
  identities (`Cask::Quarantine.signing_identity_match`).

The fix is to move the Equinox writable areas out of the bundle, in
`igrcanalytics.ini`:

```
-Dosgi.configuration.area=@user.home/Library/Application Support/Igrcanalytics/configuration
-Dosgi.sharedConfiguration.area=../Eclipse/configuration
-Dosgi.instance.area.default=@user.home/Igrcanalytics-workspace
```

This switches the product to Equinox's *shared install* model and changes its
runtime behaviour. It is a Studio product decision, not a packaging one, and
was deliberately **not** applied in the PoC.

---

## What the fix looks like in the pipeline

Defects 1 to 3 are packaging bugs and are fully addressed by
[`packaging/build-studio-artifact.sh`](packaging/build-studio-artifact.sh),
which documents exactly the operations to port upstream:

| Defect | Fix to port into the build |
| --- | --- |
| 1 | Sign the bundle **after** injecting `Contents/Eclipse` and the icon, signing nested native code first (`--deep` does not descend into non-standard locations such as `Contents/Eclipse`) |
| 2 | Produce the archive on a macOS runner with `ditto -c -k --sequesterRsrc --keepParent`, which preserves permissions and symlinks |
| 3 | Bundle a JRE in `Contents/Eclipse/jre` and add `-vm ../Eclipse/jre/bin/java` before `-vmargs` in the `.ini` |
| 4 | Studio product change — see above |
