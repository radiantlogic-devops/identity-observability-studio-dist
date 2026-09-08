#!/usr/bin/env bash
#
# Downloads the macOS Studio installer produced by the Azure DevOps build
# pipeline, so that build-studio-artifact.sh can be run without a manual
# trip through the Azure DevOps web UI.
#
# STATUS: NOT exercised during the PoC. The ZIP used in the PoC was downloaded
# by hand from the pipeline's "Artifacts" tab. This script encodes the same
# download as a REST call; validate it once with a PAT before wiring it into
# any automation.
#
# The values below were recovered from the quarantine metadata of that manual
# download (`mdls -name kMDItemWhereFroms <zip>`), whose artifact identifier
# base64-decodes to:
#
#   pipelineartifact://bw-dev-ops
#     /projectId/b99e16c9-357f-4fc8-a117-aeea64859320
#     /buildId/55582
#     /artifactName/igrc-installers5
#
set -euo pipefail

ORG="${AZDO_ORG:-bw-dev-ops}"
PROJECT="${AZDO_PROJECT:-b99e16c9-357f-4fc8-a117-aeea64859320}"
ARTIFACT="${AZDO_ARTIFACT:-igrc-installers5}"
API_VERSION="7.1"
BUILD_ID=""
FILE="iGRCAnalyticsSetup_macosx_arm64_Eiffel-IDO-R2-SP2_2026-08-24.zip"
OUTDIR="$(pwd)/studio-bin"

usage() {
  cat <<EOF
usage: $0 --build-id <id> [--file <name>] [--outdir <dir>]

  --build-id  Azure DevOps build id (e.g. 55582)
  --file      file to extract from the artifact
              (default: $FILE)
  --outdir    output directory (default: ./studio-bin)

env:
  AZDO_PAT       required. Personal Access Token with scope "Build (read)".
                 Create one at https://dev.azure.com/$ORG/_usersSettings/tokens
  AZDO_ORG       Azure DevOps organization (default: $ORG)
  AZDO_PROJECT   project id or name       (default: $PROJECT)
  AZDO_ARTIFACT  pipeline artifact name   (default: $ARTIFACT)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-id) BUILD_ID="$2"; shift 2 ;;
    --file)     FILE="$2";     shift 2 ;;
    --outdir)   OUTDIR="$2";   shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
[[ -n "$BUILD_ID" ]] || { usage; exit 2; }
[[ -n "${AZDO_PAT:-}" ]] || { echo "AZDO_PAT is not set" >&2; exit 2; }

# Azure DevOps takes the PAT as the password of a basic auth pair with an
# empty username.
AUTH="Authorization: Basic $(printf ':%s' "$AZDO_PAT" | base64 | tr -d '\n')"
BASE="https://dev.azure.com/$ORG/$PROJECT/_apis/build/builds/$BUILD_ID"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

step "Resolving artifact '$ARTIFACT' of build $BUILD_ID"
META=$(curl -fsSL -H "$AUTH" \
  "$BASE/artifacts?artifactName=$ARTIFACT&api-version=$API_VERSION")
DOWNLOAD_URL=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["resource"]["downloadUrl"])' "$META")
echo "$DOWNLOAD_URL"

# The artifact is a container holding every installer of the build (Windows,
# Linux, macOS x86_64, macOS arm64). Pulling the whole thing would be several
# gigabytes, so we ask the service for a single file: `format=file` plus the
# `subPath` of the entry we want. This is the same URL shape the web UI uses
# when you click one file rather than "Download artifact".
SINGLE_URL="${DOWNLOAD_URL%%\?*}?format=file&subPath=%2F$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$FILE")"

mkdir -p "$OUTDIR"
OUT="$OUTDIR/$FILE"
step "Downloading $FILE"
curl -fL -H "$AUTH" --progress-bar "$SINGLE_URL" -o "$OUT"

# A wrong subPath does not 404: the service answers 200 with an HTML error
# page or an empty container. Check that we really got a ZIP.
head -c 2 "$OUT" | grep -q 'PK' || {
  echo "the downloaded file is not a ZIP - check --file / --build-id" >&2
  rm -f "$OUT"; exit 1
}

step "Done"
printf '  file   : %s (%s)\n' "$OUT" "$(du -h "$OUT" | cut -f1)"
printf '  sha256 : %s\n' "$(shasum -a 256 "$OUT" | cut -d' ' -f1)"
printf '\n  next   : ./packaging/build-studio-artifact.sh --input "%s"\n' "$OUT"
