#!/usr/bin/env bash
#
# Publishes the artifact produced by build-studio-artifact.sh as a GitHub
# release asset in radiantlogic-devops/identity-observability-studio-dist,
# and prints the two lines to update in the Homebrew cask.
#
# This is the scripted form of what was done by hand during the PoC:
#   gh release create v2026.08.24 --repo <dist repo> --title ... <zip>
#
# The tag and the asset name are NOT free-form: the cask rebuilds both from
# its `version` stanza.
#   tag    v<version>
#   asset  IdentityObservabilityStudio-<version>-macos-arm64.zip
#
set -euo pipefail

REPO="${DIST_REPO:-radiantlogic-devops/identity-observability-studio-dist}"
VERSION=""
ARTIFACT=""
NOTES=""
DRY_RUN=0

usage() {
  cat <<EOF
usage: $0 --version <v> [--artifact <zip>] [--notes <text>] [--dry-run]

  --version   release version, without the leading "v" (e.g. 2026.08.24)
  --artifact  artifact to upload
              (default: ./dist/IdentityObservabilityStudio-<version>-macos-arm64.zip)
  --notes     release notes body
  --dry-run   print what would happen, upload nothing

env:
  DIST_REPO   distribution repository (default: $REPO)

requires: gh (brew install gh) authenticated with write access to \$DIST_REPO
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)  VERSION="$2";  shift 2 ;;
    --artifact) ARTIFACT="$2"; shift 2 ;;
    --notes)    NOTES="$2";    shift 2 ;;
    --dry-run)  DRY_RUN=1;     shift ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
[[ -n "$VERSION" ]] || { usage; exit 2; }

ASSET="IdentityObservabilityStudio-${VERSION}-macos-arm64.zip"
ARTIFACT="${ARTIFACT:-$(pwd)/dist/$ASSET}"
TAG="v${VERSION}"
NOTES="${NOTES:-macOS arm64. Bundled Temurin 21 JRE. Not notarised: see cask caveats.}"

[[ -f "$ARTIFACT" ]] || { echo "not found: $ARTIFACT" >&2; exit 1; }
[[ "$(basename "$ARTIFACT")" == "$ASSET" ]] || {
  echo "the artifact must be named $ASSET - the cask rebuilds this name from its version stanza" >&2
  exit 1
}
command -v gh >/dev/null || { echo "gh not found: brew install gh" >&2; exit 1; }

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

SHA=$(shasum -a 256 "$ARTIFACT" | cut -d' ' -f1)
SIZE=$(stat -f '%z' "$ARTIFACT")

step "Artifact"
printf '  file    : %s\n  size    : %s bytes\n  sha256  : %s\n' "$ARTIFACT" "$SIZE" "$SHA"

# GitHub caps a single release asset at 2 GB. Assets do not count towards the
# repository size, so accumulating versions is fine.
[[ "$SIZE" -lt 2147483648 ]] || { echo "asset over the 2 GB GitHub limit" >&2; exit 1; }

if [[ "$DRY_RUN" -eq 1 ]]; then
  step "Dry run - nothing published"
  printf '  gh release create %s --repo %s --title "Identity Observability Studio %s" --notes "%s" %s\n' \
    "$TAG" "$REPO" "$VERSION" "$NOTES" "$ARTIFACT"
else
  step "Publishing $TAG to $REPO"
  # The repository must already have at least one commit: GitHub refuses to
  # create a tag on an empty repository (HTTP 422 "Repository is empty").
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "release $TAG already exists - uploading the asset with --clobber"
    gh release upload "$TAG" "$ARTIFACT" --repo "$REPO" --clobber
  else
    gh release create "$TAG" \
      --repo "$REPO" \
      --title "Identity Observability Studio $VERSION" \
      --notes "$NOTES" \
      "$ARTIFACT"
  fi

  step "Verifying what GitHub actually stored"
  # GitHub computes the digest server-side, so this proves the published asset
  # is bit-for-bit the local one without re-downloading 700+ MB.
  gh release view "$TAG" --repo "$REPO" \
    --json assets --jq '.assets[] | "\(.name)  \(.size) bytes  \(.digest)  \(.state)"'
fi

step "Cask stanzas to update"
cat <<EOF
  In homebrew-tap/Casks/identity-observability-studio.rb:

    version "$VERSION"
    sha256 "$SHA"

  Resulting url:
    https://github.com/$REPO/releases/download/$TAG/$ASSET
EOF
