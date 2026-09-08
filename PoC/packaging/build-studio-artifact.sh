#!/usr/bin/env bash
#
# Transforme le ZIP brut sorti du pipeline de build en un artefact
# distribuable par Homebrew.
#
# Le ZIP livré par le pipeline souffre de trois défauts qui empêchent
# l'application de démarrer sur un Mac Apple Silicon :
#
#   1. il est écrit avec des attributs "fat" (Windows) : aucun bit
#      exécutable, aucun lien symbolique ;
#   2. l'injection de Contents/Eclipse et Resources/igrc.icns après coup
#      a invalidé la signature héritée du launcher Eclipse — le bundle
#      n'a plus de Contents/_CodeSignature, donc AMFI tue le process
#      au lancement (« l'application est endommagée ») ;
#   3. aucun JRE n'est embarqué et l'ini ne contient pas de -vm, donc
#      depuis le Finder (PATH minimal) aucune JVM n'est trouvée.
#
# Ce script corrige les trois points, puis réempaquette avec ditto pour
# préserver permissions et symlinks.
#
set -euo pipefail

VERSION="2026.08.24"
JRE_VERSION="21"
ARCH="aarch64"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" = ad-hoc ; sinon "Developer ID Application: ..."

usage() {
  cat <<EOF
usage: $0 --input <build.zip> [--version <v>] [--outdir <dir>]

  --input     ZIP brut produit par le pipeline (iGRCAnalyticsSetup_macosx_arm64_*.zip)
  --version   version du cask (défaut: $VERSION)
  --outdir    répertoire de sortie (défaut: ./dist)

env:
  SIGN_IDENTITY   identité codesign. "-" (défaut) = signature ad-hoc.
                  Renseigner un "Developer ID Application: ..." le jour où
                  vous aurez un certificat Apple : le reste du pipeline ne
                  change pas.
EOF
}

INPUT=""
OUTDIR="$(pwd)/dist"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)   INPUT="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --outdir)  OUTDIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "argument inconnu: $1" >&2; usage; exit 2 ;;
  esac
done
[[ -n "$INPUT" ]] || { usage; exit 2; }
[[ -f "$INPUT" ]] || { echo "introuvable: $INPUT" >&2; exit 1; }

# Nom du bundle tel qu'il sort du pipeline, et nom sous lequel on le distribue.
# Le launcher Eclipse deduit le chemin de son .ini du nom de l'executable
# (Contents/MacOS/igrcanalytics -> Contents/Eclipse/igrcanalytics.ini), pas du
# nom du bundle : renommer le repertoire .app est donc sans risque, renommer
# l'executable ne le serait pas.
SRC_APP_NAME="Igrcanalytics.app"
APP_NAME="Identity Observability Studio.app"
APP_DISPLAY_NAME="Identity Observability Studio"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/studio-pkg.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"
APP="$STAGE/$APP_NAME"
mkdir -p "$STAGE" "$OUTDIR"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- 1. extraction
step "Extraction de $(basename "$INPUT")"
ditto -x -k "$INPUT" "$STAGE"
[[ -d "$STAGE/$SRC_APP_NAME" ]] || { echo "le ZIP ne contient pas $SRC_APP_NAME" >&2; exit 1; }
mv "$STAGE/$SRC_APP_NAME" "$APP"
echo "$SRC_APP_NAME -> $APP_NAME"

# La quarantaine du ZIP source se propage à chaque fichier extrait.
# On la retire ici, sur notre copie de build, pendant qu'on en a le droit :
# une fois le bundle signé et posé dans /Applications, c'est bien plus délicat.
xattr -cr "$APP"

# --------------------------------------------------------------- 2. permissions
step "Restauration des permissions Unix perdues par le ZIP"
chmod 755 "$APP/Contents/MacOS/igrcanalytics"
find "$APP/Contents/Eclipse" -maxdepth 1 -name '*.sh' -exec chmod 755 {} +
# les .so/.jnilib sont chargés par dlopen, le bit x n'est pas requis,
# mais on l'aligne pour rester cohérent avec un build fait sur macOS.
find "$APP" \( -name '*.so' -o -name '*.dylib' -o -name '*.jnilib' \) -exec chmod 755 {} +
echo "launcher: $(stat -f '%Sp' "$APP/Contents/MacOS/igrcanalytics")"

# ---------------------------------------------------------------------- 3. JRE
step "Téléchargement du JRE Temurin $JRE_VERSION ($ARCH)"
API="https://api.adoptium.net/v3/assets/latest/${JRE_VERSION}/hotspot?architecture=${ARCH}&image_type=jre&os=mac&vendor=eclipse"
META="$WORK/jre.json"
curl -fsSL "$API" -o "$META"

JRE_URL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["binary"]["package"]["link"])' "$META")
JRE_SHA=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["binary"]["package"]["checksum"])' "$META")
JRE_SEMVER=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["version"]["semver"])' "$META")
echo "$JRE_SEMVER"

TARBALL="$WORK/jre.tar.gz"
curl -fsSL "$JRE_URL" -o "$TARBALL"
ACTUAL=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)
[[ "$ACTUAL" == "$JRE_SHA" ]] || { echo "checksum JRE invalide: $ACTUAL != $JRE_SHA" >&2; exit 1; }
echo "checksum ok"

step "Intégration du JRE dans $APP_NAME/Contents/Eclipse/jre"
mkdir -p "$WORK/jre"
tar -xzf "$TARBALL" -C "$WORK/jre"
JRE_HOME=$(find "$WORK/jre" -maxdepth 3 -type d -name Home -path '*/Contents/Home' | head -1)
[[ -n "$JRE_HOME" ]] || { echo "layout JRE inattendu" >&2; exit 1; }
rm -rf "$APP/Contents/Eclipse/jre"
ditto "$JRE_HOME" "$APP/Contents/Eclipse/jre"
"$APP/Contents/Eclipse/jre/bin/java" -version 2>&1 | sed 's/^/    /'

# ------------------------------------------------------------------- 4. ini -vm
step "Injection de -vm dans igrcanalytics.ini"
INI="$APP/Contents/Eclipse/igrcanalytics.ini"
# Les chemins de l'ini sont relatifs à Contents/MacOS (là où vit le launcher),
# d'où le ../Eclipse/. -vm doit impérativement précéder -vmargs.
python3 - "$INI" <<'PY'
import sys, pathlib
ini = pathlib.Path(sys.argv[1])
lines = ini.read_text().splitlines()
if "-vm" in lines:
    sys.exit(0)
i = lines.index("-vmargs")
lines[i:i] = ["-vm", "../Eclipse/jre/bin/java"]
ini.write_text("\n".join(lines) + "\n")
PY
grep -A1 -m1 '^-vm$' "$INI" | sed 's/^/    /'

# -------------------------------------------------------------- 5. Info.plist
step "Info.plist : version et nom affiche"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"
# CFBundleName pilote le titre du menu de l'application, CFBundleDisplayName le
# nom montre par le Finder. CFBundleIdentifier n'est PAS touche : c'est l'id du
# produit Eclipse (-product com.brainwave.igrcanalytics.product dans l'ini), le
# changer casserait le demarrage et la continuite des preferences utilisateur.
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_DISPLAY_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_DISPLAY_NAME" "$PLIST"
printf "    CFBundleName       = %s\n" "$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$PLIST")"
printf "    CFBundleIdentifier = %s (inchange)\n" "$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST")"

# ---------------------------------------------------------------- 6. signature
step "Signature (identité: $SIGN_IDENTITY)"
# On signe d'abord le code natif imbriqué (JRE + launcher Eclipse), puis le
# bundle : codesign --deep ne descend pas dans du code hors emplacements
# standards comme Contents/Eclipse.
find "$APP/Contents/Eclipse/jre" -type f \( -perm -u+x -o -name '*.dylib' \) -print0 \
  | xargs -0 -n 20 codesign --force --timestamp=none --sign "$SIGN_IDENTITY" 2>/dev/null || true
find "$APP/Contents/Eclipse/plugins" -type f \( -name '*.so' -o -name '*.dylib' -o -name '*.jnilib' \) -print0 \
  | xargs -0 -n 20 codesign --force --timestamp=none --sign "$SIGN_IDENTITY" 2>/dev/null || true
codesign --force --deep --timestamp=none --sign "$SIGN_IDENTITY" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
codesign -dv "$APP" 2>&1 | grep -E '^(Identifier|Signature|Authority|TeamIdentifier)' | sed 's/^/    /'

# --------------------------------------------------------------- 7. empaquetage
step "Empaquetage"
OUT="$OUTDIR/IdentityObservabilityStudio-${VERSION}-macos-arm64.zip"
rm -f "$OUT"
# ditto -c -k préserve bits exécutables, symlinks et xattrs — contrairement au
# ZIP "fat" produit par le pipeline actuel.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"

SHA=$(shasum -a 256 "$OUT" | cut -d' ' -f1)
printf '%s  %s\n' "$SHA" "$(basename "$OUT")" > "$OUT.sha256"

step "Terminé"
printf '  artefact : %s (%s)\n' "$OUT" "$(du -h "$OUT" | cut -f1)"
printf '  sha256   : %s\n' "$SHA"
printf '  version  : %s\n' "$VERSION"
printf '  jre      : %s\n' "$JRE_SEMVER"
