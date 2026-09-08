# Turning the Studio into a properly Apple-signed application

What it takes to ship Identity Observability Studio as a real signed macOS
application — distributable through Homebrew (Developer ID + notarisation) and,
separately, through the Mac App Store — with the exact Apple prerequisites,
official links and costs.

Today the PoC artifact is signed **ad-hoc**. That is enough to satisfy AMFI on
Apple Silicon, but not Gatekeeper: the user must clear the quarantine attribute
by hand after every install and every upgrade.

---

## 1. The two channels are not the same project

| | **Developer ID + notarisation** | **Mac App Store** |
| --- | --- | --- |
| Serves | Homebrew, direct download, MDM | App Store, Apple Business Manager |
| Apple membership | Apple Developer Program ($99/yr) | same |
| Certificate | `Developer ID Application` | `Apple Distribution` / `Mac App Distribution` |
| Hardened Runtime | **required** | required |
| App Sandbox | not required | **required** |
| Apple review | automated notarisation, minutes | human review, days, can reject |
| Commission | none | 15 % or 30 % on App Store sales |
| Feasible for this product | **Yes — this is the target** | See §5. Very likely blocked by the sandbox |
| Effort | days | months, and a product redesign |

**Recommendation: go for Developer ID + notarisation.** It removes 100 % of the
friction users currently face with Homebrew. The App Store is a separate,
much larger programme whose main obstacle is not Apple's paperwork but App
Sandbox versus an Eclipse RCP application — see §5.

---

## 2. Apple Developer Program — Organization enrolment

The one account that unlocks everything below.

**Cost: 99 USD per membership year**, renewed annually. Prices vary by region and
are shown in local currency during enrolment.
Fee waivers exist for nonprofits, accredited educational institutions and
government entities — not applicable here.

Enrol at **https://developer.apple.com/programs/enroll/**

### Exact prerequisites (Apple's own wording)

| Requirement | Detail |
| --- | --- |
| **Apple Account with two-factor authentication** | Use an address on the company domain. The first and last names on the account must be the person's **legal** names — not aliases, nicknames or the company name. |
| **Legal binding authority** | The person enrolling becomes the **Account Holder** and must have legal authority to bind the organization to agreements with Apple: owner/founder, executive team member, senior project lead, or an employee to whom a senior employee has granted that authority. |
| **Legal entity name and status** | The organization must be a legal entity able to enter into contracts with Apple. Apple does **not** accept DBAs, fictitious business names, trade names or branches. This name is displayed as the seller name of the apps. |
| **D-U-N-S Number** | Required to verify identity, legal entity status and address. Free lookup / request: https://developer.apple.com/enroll/duns-lookup/ — see https://developer.apple.com/support/D-U-N-S/. A large company usually already has one; if not, obtaining it from Dun & Bradstreet takes up to 5 business days. |
| **Work email and phone** | The email address must be on the organization's domain. |
| **Public website** | Publicly reachable, functional, on a domain associated with the organization. Social-media pages or registrar parking pages are rejected. |

Apple verifies the D-U-N-S record against the legal entity; a mismatch between
the legal name, address or website is the usual cause of delay. Budget
**1 to 4 weeks** end to end.

### What is deliberately not the right programme

* **Apple Developer Enterprise Program** — 299 USD/yr, requires 100+ employees,
  and is restricted to **proprietary in-house apps distributed to employees
  only**. Public distribution and the App Store are explicitly forbidden.
  It does not cover shipping a product to customers.
  https://developer.apple.com/programs/enterprise/
* **Individual enrolment** — cheaper and faster, but the signature would carry a
  personal name as the seller/developer identity, and the certificate would be
  tied to one person. Not acceptable for a commercial product.

### Roles to plan for, inside the account

* **Account Holder** — one person, holds the legal agreement. **Only the Account
  Holder can create `Developer ID Application` certificates**, and an account is
  limited to **five** of them. Pick someone durable; a departure means a
  transfer of the Account Holder role.
* **Admin** — manages App Store Connect users, App Store certificates and keys.
* **Developer** — day-to-day certificates.

Practical consequence for CI: do **not** hand the Account Holder's Apple ID to
the pipeline. Create an **App Store Connect API key** (Issuer ID + Key ID +
`.p8` private key) for notarisation, and store the signing certificate in the
build system's keychain / secret store.

---

## 3. Developer ID + notarisation — the technical path

### 3.1 Certificates

1. Account Holder signs in to https://developer.apple.com/account/resources/certificates
2. Create a **Developer ID Application** certificate (used to sign `.app`).
3. Create a **Developer ID Installer** certificate too, if a `.pkg` is ever
   needed. Not required for the Homebrew ZIP.
4. Export as `.p12` with a strong passphrase and store it in the secret manager;
   import into the macOS build agent's keychain.

Reference: https://developer.apple.com/help/account/create-certificates/create-developer-id-certificates

The signing identity string then looks like:

```
Developer ID Application: Radiant Logic, Inc. (XXXXXXXXXX)
```

where `XXXXXXXXXX` is the Team ID.

> Certificates expire. A build signed **with a secure timestamp**
> (`codesign --timestamp`) keeps validating after the certificate expires, which
> is why the timestamp is mandatory and why the current PoC's
> `--timestamp=none` must be dropped for real releases.

### 3.2 Hardened Runtime and JVM entitlements

Notarisation requires the **Hardened Runtime** (`codesign --options runtime`).
A JVM will not run under it without explicit exceptions, because it allocates
executable memory for the JIT and loads native libraries signed by other teams
(SWT, Temurin, Eclipse JNI libraries).

`packaging/entitlements.plist` to add:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key><true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
    <key>com.apple.security.cs.disable-library-validation</key><true/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key><true/>
</dict>
</plist>
```

`disable-library-validation` is the one that matters most: without it the
launcher cannot load `libjvm.dylib` and the SWT/JNI `.jnilib`s, which are signed
by a different team.

Reference: https://developer.apple.com/documentation/security/hardened-runtime

### 3.3 Signing

The order already implemented in
[`packaging/build-studio-artifact.sh`](packaging/build-studio-artifact.sh)
stays valid — inside out, nested native code first, bundle last, because
`--deep` does not descend into non-standard locations such as
`Contents/Eclipse`. Only the flags change:

```bash
CODESIGN_FLAGS=(--force --timestamp --options runtime
                --entitlements packaging/entitlements.plist
                --sign "Developer ID Application: Radiant Logic, Inc. (XXXXXXXXXX)")

# 1. every nested Mach-O: JRE binaries and dylibs, .so / .dylib / .jnilib in plugins
# 2. then the bundle itself
codesign "${CODESIGN_FLAGS[@]}" "Identity Observability Studio.app"
codesign --verify --deep --strict --verbose=2 "Identity Observability Studio.app"
```

### 3.4 Notarisation

Store the credentials once (or pass them per call in CI):

```bash
xcrun notarytool store-credentials "radiantlogic-notary" \
  --key /secure/AuthKey_XXXXXXXXXX.p8 \
  --key-id XXXXXXXXXX \
  --issuer 00000000-0000-0000-0000-000000000000
```

Submit, wait, and read the log on rejection:

```bash
ditto -c -k --sequesterRsrc --keepParent "Identity Observability Studio.app" upload.zip
xcrun notarytool submit upload.zip --keychain-profile "radiantlogic-notary" --wait
xcrun notarytool log <submission-id> --keychain-profile "radiantlogic-notary"
```

Then **staple** the ticket so the app validates offline, and only then build the
distribution archive:

```bash
xcrun stapler staple "Identity Observability Studio.app"
xcrun stapler validate "Identity Observability Studio.app"
ditto -c -k --sequesterRsrc --keepParent "Identity Observability Studio.app" \
  "dist/IdentityObservabilityStudio-<version>-macos-arm64.zip"
```

> A ticket cannot be stapled to a `.zip`. Notarise the zip, staple the `.app`
> inside it, then re-zip. Getting this order wrong is the most common mistake.

Final acceptance check — this is literally what Gatekeeper runs:

```bash
spctl --assess --type execute --verbose=4 "Identity Observability Studio.app"
# → accepted / source=Notarized Developer ID
```

References:
https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
· https://developer.apple.com/documentation/security/resolving-common-notarization-issues
· https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool

### 3.5 Hard prerequisite from the product side

**Eclipse must stop writing inside its own bundle** — defect 4 in
[`UPSTREAM_BUILD_DEFECTS.md`](UPSTREAM_BUILD_DEFECTS.md). A notarised, stapled
app that rewrites itself on first launch breaks its own seal. Move the Equinox
writable areas out of the bundle via `igrcanalytics.ini`:

```
-Dosgi.configuration.area=@user.home/Library/Application Support/Igrcanalytics/configuration
-Dosgi.sharedConfiguration.area=../Eclipse/configuration
-Dosgi.instance.area.default=@user.home/Igrcanalytics-workspace
```

This is a Studio product change, not a packaging one.

### 3.6 What this buys, concretely

| | Today (ad-hoc) | Notarised |
| --- | --- | --- |
| `brew install --cask …` | works | works |
| `xattr -dr com.apple.quarantine …` | **required, and again after every upgrade** | **not needed** |
| First launch | works once quarantine is cleared | works, no dialog |
| Cask `caveats` | 12 lines of instructions | can be removed |
| `brew upgrade` | user must re-run `xattr` | transparent |

The cask itself does not change beyond deleting the `caveats` block: the
`SIGN_IDENTITY` environment variable is already the only knob in the build
script.

---

## 4. Cost and effort summary — Developer ID path

| Item | Cost | Lead time |
| --- | --- | --- |
| Apple Developer Program, Organization | **99 USD / year** | 1–4 weeks (D-U-N-S verification) |
| D-U-N-S Number, if not already held | free | up to 5 business days |
| Developer ID Application certificate | included | minutes, Account Holder only |
| App Store Connect API key for CI | included | minutes |
| Entitlements + hardened runtime in the build | engineering | ~1–2 days |
| Equinox writable-area fix (defect 4) | engineering, Studio team | to be estimated |
| Notarisation per release | free, no volume limit | 2–15 minutes per submission |
| macOS build agent (required to sign and notarise) | infrastructure | to be arranged |

There is **no per-release fee and no revenue share** on this channel.

---

## 5. Mac App Store — the honest assessment

Everything in §2 and §3 also applies, plus:

1. **App Sandbox is mandatory.** Every app on the Mac App Store must adopt
   `com.apple.security.app-sandbox`.
   https://developer.apple.com/documentation/security/app-sandbox
2. A sandboxed app cannot freely read or write outside its container, cannot
   launch arbitrary helper processes, and reaches the network and the user's
   files only through declared entitlements and user-driven pickers.
3. An Eclipse RCP application does the opposite by design: arbitrary workspace
   paths, plug-in installation, external tool invocation, a JVM that JITs, an
   OSGi configuration area, keyring access.
4. Signing changes too: `Apple Distribution` certificate, upload through
   App Store Connect, human review against the
   [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
   with a real chance of rejection for a developer-tooling application.
5. **Commission** on paid apps and in-app purchases: **30 %**, or **15 %** under
   the [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/)
   (developers under 1 M USD in proceeds in the prior calendar year).

**Conclusion: not a realistic target for the Studio as it stands.** Shipping it
on the Mac App Store would mean re-architecting the product around the sandbox,
not repackaging it.

### The B2B alternative that does exist

If the goal behind "App Store" is *managed, private distribution to enterprise
customers*, the right mechanism is **Custom Apps with Apple Business Manager**:
the app is distributed privately to named organizations, deployed via MDM, and
never appears on the public App Store.
https://developer.apple.com/business/custom-apps/

It still requires App Sandbox, so the same technical obstacle applies — but it
is the correct channel to name if the requirement is enterprise deployment
rather than consumer discoverability.

---

## 6. Recommended sequence

1. **Now** — open the Apple Developer Program Organization enrolment (§2). It is
   the long pole and nothing else can start without it.
2. **In parallel** — fix the build pipeline defects 1–3
   ([`UPSTREAM_BUILD_DEFECTS.md`](UPSTREAM_BUILD_DEFECTS.md)) and provision a
   macOS build agent.
3. **Studio team** — fix defect 4, the Equinox writable areas.
4. **When the account is live** — Developer ID certificate, hardened runtime and
   entitlements, notarisation in the pipeline (§3).
5. **Then** — drop the `caveats` from the cask, merge the cask PR into
   `radiantlogic-devops/homebrew-tap`, publish the install guide.
6. **Only if enterprise MDM distribution is genuinely required** — reopen the
   App Sandbox question (§5) as a product initiative, not a packaging task.

---

## 7. Request template for the Product Owner → Radiant Logic Buyer

> **Subject: Approval request — Apple Developer Program membership (Organization), 99 USD/year**
>
> **What we are asking for**
>
> Approval to enrol Radiant Logic in the **Apple Developer Program** as an
> organization. The cost is **99 USD per year** (https://developer.apple.com/programs/).
> There is no other fee: notarising our releases with Apple is free and
> unlimited, and this channel carries no revenue share.
>
> **Why**
>
> We distribute Identity Observability Studio to macOS users. macOS blocks any
> application Apple has not certified, and recent versions removed the simple
> click-through override: our users currently have to run a terminal command to
> lift that block after every install and every update. That is a poor first
> impression for a security product, it generates
> support load, and a customer's IT policy may forbid the workaround outright.
>
> Membership lets us sign and notarise the application with Apple, so it
> installs and launches like any commercial Mac software — no warning, no
> workaround. It is the industry-standard baseline; every macOS product our
> customers install already does this.
>
> **What we need from the company**
>
> Apple requires more than a payment. Enrolling as an organization requires:
>
> 1. A **D-U-N-S Number** for the legal entity — we likely already have one;
>    confirmation from Finance/Legal is needed
>    (https://developer.apple.com/enroll/duns-lookup/).
> 2. Confirmation of the **exact legal entity name and registered address**,
>    which must match the D-U-N-S record. Apple does not accept trade names or
>    branches. This name will appear publicly as the publisher of our
>    application.
> 3. A named **Account Holder** who has **legal authority to bind the company**
>    to Apple's agreements — an owner, executive team member or senior project
>    lead, or an employee formally granted that authority. This person signs the
>    Apple Developer Program License Agreement on behalf of the company, holds
>    the account, and is the only person able to create the signing certificate.
>    We propose that this be [NAME, TITLE], with a designated backup, and that
>    the role be treated as a company asset to be transferred if that person
>    leaves.
> 4. A company **Apple Account** on our domain with two-factor authentication,
>    and a work email on our domain.
> 5. Our public website, on our own domain — already satisfied.
>
> **Timeline and risk**
>
> Apple verifies the legal entity against the D-U-N-S record; enrolment
> typically takes one to four weeks and stalls only when the legal name, address
> or website do not match. Engineering work on our side is a few days once the
> account exists.
>
> **Scope of this request**
>
> This covers distribution outside the App Store (our Homebrew channel and
> direct download), which is what our users need. Publishing on the Mac App
> Store is a separate question: it would require re-architecting the Studio
> around Apple's sandbox, and carries a 15–30 % commission on any sales made
> through it. We are **not** requesting that today.
>
> **Decision needed:** approval of the 99 USD/year membership, designation of
> the Account Holder, and Legal/Finance confirmation of the legal entity name
> and D-U-N-S Number.

---

## Sources

* [Apple Developer Program](https://developer.apple.com/programs/) · [Enrolment and requirements](https://developer.apple.com/programs/enroll/) · [Compare memberships](https://developer.apple.com/support/compare-memberships/)
* [D-U-N-S Number support](https://developer.apple.com/support/D-U-N-S/) · [D-U-N-S lookup](https://developer.apple.com/enroll/duns-lookup/) · [Fee waiver](https://developer.apple.com/support/fee-waiver/)
* [Apple Developer Enterprise Program](https://developer.apple.com/programs/enterprise/)
* [Create Developer ID certificates](https://developer.apple.com/help/account/create-certificates/create-developer-id-certificates)
* [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)
* [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues) · [TN3147: migrating to the latest notarization tool](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)
* [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox) · [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
* [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/) · [Volume Purchase and Custom Apps](https://developer.apple.com/business/custom-apps/)
