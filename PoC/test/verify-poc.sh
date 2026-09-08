#!/usr/bin/env bash
#
# Verification de bout en bout du PoC de distribution Homebrew.
# Rejoue le parcours utilisateur complet et controle chaque etape.
#
set -uo pipefail

TAP="radiantlogic-devops/tap"
CASK="identity-observability-studio"
APP="/Applications/Identity Observability Studio.app"
PASS=0; FAIL=0
FRESH=0
[[ "${1:-}" == "--fresh" ]] && FRESH=1

ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; PASS=$((PASS+1)); }
ko()   { printf '  \033[31mKO\033[0m   %s\n' "$*"; FAIL=$((FAIL+1)); }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

step "Le tap est visible par Homebrew"
brew tap | grep -qx "$TAP" && ok "$TAP tape" || ko "$TAP absent"
brew info --cask "$TAP/$CASK" >/dev/null 2>&1 && ok "cask resolu" || ko "cask non resolu"

step "Installation"
if [[ "$FRESH" -eq 1 ]]; then
  # Repart d'un bundle vierge : Eclipse ecrit dans Contents/Eclipse au premier
  # lancement et rompt le sceau, donc un test de signature n'a de sens que sur
  # une installation neuve.
  brew reinstall --cask "$TAP/$CASK" >/dev/null 2>&1
  xattr -dr com.apple.quarantine "$APP" 2>/dev/null
  ok "reinstallation propre + quarantaine levee"
else
  brew list --cask "$CASK" >/dev/null 2>&1 || brew install --cask "$TAP/$CASK"
fi
[[ -d "$APP" ]] && ok "$APP present" || { ko "$APP absent"; exit 1; }

step "Defauts du ZIP amont corriges"
[[ -x "$APP/Contents/MacOS/igrcanalytics" ]] \
  && ok "bit executable du launcher preserve" \
  || ko "launcher non executable (ditto n'a pas preserve les permissions)"
[[ -x "$APP/Contents/Eclipse/igrc_version.sh" ]] \
  && ok "bit executable des scripts igrc_*.sh preserve" \
  || ko "scripts igrc_*.sh non executables"

step "Signature de code"
if codesign --verify --deep --strict "$APP" 2>/dev/null; then
  ok "bundle scelle et valide"
else
  # Attendu apres un premier lancement : Eclipse ecrit dans
  # Contents/Eclipse/configuration et rompt le sceau. Voir README.
  ko "sceau invalide (normal si l'app a deja ete lancee une fois)"
fi
# NB: pas de "| grep -q" ici — avec pipefail, grep ferme le tube et le
# SIGPIPE fait echouer tout le pipeline, ce qui produit de faux negatifs.
CS_OUT=$(codesign -dv "$APP" 2>&1)
case "$CS_OUT" in
  *"Identifier=com.brainwave.igrcanalytics.product"*)
    ok "identifier = com.brainwave.igrcanalytics.product" ;;
  *) ko "identifier inattendu" ;;
esac

step "JRE embarque"
JAVA="$APP/Contents/Eclipse/jre/bin/java"
[[ -x "$JAVA" ]] && ok "JRE present dans le bundle" || ko "JRE absent"
grep -q '^\.\./Eclipse/jre/bin/java$' "$APP/Contents/Eclipse/igrcanalytics.ini" \
  && ok "-vm pointe sur le JRE embarque" \
  || ko "-vm absent ou incorrect dans igrcanalytics.ini"

step "Quarantaine"
Q=$(xattr -r -p com.apple.quarantine "$APP" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$Q" -eq 0 ]]; then
  ok "quarantaine levee ($Q fichier)"
else
  ko "$Q fichiers encore en quarantaine — l'app sera tuee au lancement"
  printf '       levez-la avec : xattr -dr com.apple.quarantine "%s"\n' "$APP"
fi

step "Demarrage reel (JVM + workbench)"
if [[ "$Q" -eq 0 ]]; then
  "$APP/Contents/MacOS/igrcanalytics" -nosplash >/dev/null 2>&1 &
  PID=$!
  JVM_SEEN=0
  for _ in $(seq 1 30); do
    sleep 1
    ps -p "$PID" >/dev/null 2>&1 || break
    LSOF_OUT=$(lsof -p "$PID" 2>/dev/null || true)
    case "$LSOF_OUT" in *"jre/lib/server/libjvm.dylib"*)
      JVM_SEEN=1
      break ;;
    esac
  done
  [[ "$JVM_SEEN" -eq 1 ]] \
    && ok "libjvm du JRE embarque chargee dans le launcher" \
    || ko "le launcher n'a pas charge le JRE embarque"
  if ps -p "$PID" >/dev/null 2>&1; then
    ok "le Studio tourne (pid $PID)"
    kill "$PID" 2>/dev/null
  else
    wait "$PID"; ko "le launcher s'est arrete (exit $?) — 137 = tue par AMFI/Gatekeeper"
  fi
else
  printf '  \033[33mSKIP\033[0m quarantaine encore posee\n'
fi

printf '\n\033[1m%d OK, %d KO\033[0m\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
