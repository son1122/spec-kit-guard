#!/usr/bin/env bash
#
# Generate catalog.json from the extension manifests.
#
# The catalog is the file `specify extension update` consults, and its version
# fields are the only thing that tells anyone a new release exists. Maintaining
# it by hand means that bumping extension.yml and forgetting catalog.json
# silently ships an update nobody is ever offered — a registry that has drifted
# from its implementation, which is precisely what this repo's own guard gate
# exists to catch. So it is generated, and CI fails if it is out of date.
#
# Usage: scripts/build-catalog.sh [--check]
#   --check   regenerate to a temp file and diff; non-zero if catalog.json is stale

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OWNER="son1122"
REPO="spec-kit-guard"
CHECK=false
[[ "${1:-}" == "--check" ]] && CHECK=true

manifest_field() { # file, key
  grep -E "^  $2:" "$1" | head -1 | sed -E "s/^  $2:[[:space:]]*//; s/^\"//; s/\"$//"
}

VERSION=""
for ext in guard converge-loop; do
  v="$(manifest_field "$REPO_ROOT/extensions/$ext/extension.yml" version)"
  if [[ -z "$VERSION" ]]; then
    VERSION="$v"
  elif [[ "$v" != "$VERSION" ]]; then
    echo "build-catalog: version mismatch — guard is $VERSION but $ext is $v." >&2
    echo "  Both extensions share one release tag, so bump them together." >&2
    exit 1
  fi
done
TAG="v$VERSION"

OUT="$REPO_ROOT/catalog.json"
$CHECK && OUT="$(mktemp)"

{
  printf '{\n  "schema_version": "1.0",\n'
  printf '  "catalog_url": "https://raw.githubusercontent.com/%s/%s/main/catalog.json",\n' "$OWNER" "$REPO"
  printf '  "extensions": {\n'
  first=true
  for ext in guard converge-loop; do
    m="$REPO_ROOT/extensions/$ext/extension.yml"
    $first || printf ',\n'; first=false
    printf '    "%s": {\n' "$ext"
    printf '      "id": "%s",\n' "$ext"
    printf '      "name": "%s",\n' "$(manifest_field "$m" name)"
    printf '      "version": "%s",\n' "$(manifest_field "$m" version)"
    printf '      "description": "%s",\n' "$(manifest_field "$m" description)"
    printf '      "author": "%s",\n' "$OWNER"
    printf '      "license": "MIT",\n'
    printf '      "category": "%s",\n' "$(manifest_field "$m" category)"
    printf '      "effect": "%s",\n' "$(manifest_field "$m" effect)"
    printf '      "download_url": "https://github.com/%s/%s/releases/download/%s/%s.zip",\n' \
      "$OWNER" "$REPO" "$TAG" "$ext"
    printf '      "repository": "https://github.com/%s/%s",\n' "$OWNER" "$REPO"
    printf '      "documentation": "https://github.com/%s/%s/blob/main/extensions/%s/README.md",\n' \
      "$OWNER" "$REPO" "$ext"
    printf '      "requires": { "speckit_version": ">=0.9.0" },\n'
    printf '      "verified": false\n'
    printf '    }'
  done
  printf '\n  }\n}\n'
} > "$OUT"

if $CHECK; then
  if diff -q "$OUT" "$REPO_ROOT/catalog.json" >/dev/null 2>&1; then
    echo "catalog.json is in sync with the manifests (version $VERSION)."
    rm -f "$OUT"
  else
    echo "catalog.json is STALE. Regenerate it with scripts/build-catalog.sh" >&2
    diff "$REPO_ROOT/catalog.json" "$OUT" >&2 || true
    rm -f "$OUT"
    exit 1
  fi
else
  echo "Wrote catalog.json for $TAG (both extensions at $VERSION)."
fi
