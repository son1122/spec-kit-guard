#!/usr/bin/env bash
#
# Converge Loop — post-implement verification.
#
# Runs the project's own build and test commands after an implementation pass,
# before convergence assesses anything. The order matters: converge reads the
# codebase as the source of truth about what is built. Assessing a codebase
# that does not compile, or whose tests fail, produces findings about intent
# when the real problem is that the last pass left the tree broken.
#
# Exit 0 = every verify command passed (or none are configured).
# Exit 1 = at least one failed. The loop stops here rather than converging.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

REPO_ROOT="${SPECIFY_REPO_ROOT:-}"
FAST=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    --fast) FAST=true; shift ;;
    -h|--help)
      cat <<'USAGE'
verify.sh [--repo <path>] [--fast]

  --repo <path>  project root; defaults to the installed location, or the
                 nearest ancestor of $PWD containing .specify/
  --fast         skip commands tagged @slow in verify-commands.txt

Commands come from verify-commands.txt (project copy preferred). With none
configured, falls back to autodetecting a Node project's typecheck and tests.

Exit 0 when everything passed, 1 when anything failed.
USAGE
      exit 0 ;;
    *) echo "verify.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  if [[ "$EXT_DIR" == */.specify/extensions/* ]]; then
    REPO_ROOT="$(cd "$EXT_DIR/../../.." && pwd)"
  else
    d="$PWD"
    while [[ "$d" != "/" ]]; do
      if [[ -d "$d/.specify" ]]; then REPO_ROOT="$d"; break; fi
      d="$(dirname "$d")"
    done
  fi
fi

if [[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT" ]]; then
  echo "VERIFY: no Spec Kit project found (no .specify/ in $PWD or any parent). Use --repo <path>." >&2
  exit 1
fi

# Project-local list wins, and lives outside the extension directory so that
# reinstalling the extension cannot overwrite it.
LIST=""
for candidate in \
  "$REPO_ROOT/.specify/verify-commands.txt" \
  "$REPO_ROOT/.specify/extensions/converge-loop/verify-commands.txt" \
  "$EXT_DIR/verify-commands.txt"
do
  if [[ -f "$candidate" ]] && grep -qvE '^\s*(#|$)' "$candidate" 2>/dev/null; then
    LIST="$candidate"; break
  fi
done

declare -a CMDS=() LABELS=()

if [[ -n "$LIST" ]]; then
  while IFS= read -r line; do
    [[ -z "${line// }" || "$line" == \#* ]] && continue
    if $FAST && [[ "$line" == *"@slow"* ]]; then continue; fi
    CMDS+=("${line//@slow/}")
    LABELS+=("configured")
  done < "$LIST"
else
  # Autodetect, so a fresh Node project verifies something useful with no setup.
  if [[ -f "$REPO_ROOT/package.json" ]]; then
    if grep -qE '"typescript"\s*:' "$REPO_ROOT/package.json"; then
      CMDS+=("npx tsc --noEmit"); LABELS+=("autodetected")
    fi
    if grep -qE '"test"\s*:' "$REPO_ROOT/package.json"; then
      CMDS+=("npm test"); LABELS+=("autodetected")
    fi
  fi
fi

if ((${#CMDS[@]} == 0)); then
  echo "VERIFY: SKIP — no verify commands configured and none autodetected."
  echo "        Add them to .specify/verify-commands.txt to gate the loop on a real build."
  exit 0
fi

cd "$REPO_ROOT" || exit 1

failed=0
printf '── Verification (%s) ──\n' "${LABELS[0]}"
for cmd in "${CMDS[@]}"; do
  printf '\n$ %s\n' "$cmd"
  # Output is shown rather than captured: when this gate fails, the compiler or
  # test output is the thing the next implement pass needs to act on.
  if bash -c "$cmd"; then
    printf 'PASS  %s\n' "$cmd"
  else
    printf 'FAIL  %s\n' "$cmd"
    failed=$((failed + 1))
  fi
done

printf '\n'
if ((failed == 0)); then
  printf 'VERIFY: PASS — %d command(s) succeeded. Safe to converge.\n' "${#CMDS[@]}"
  exit 0
fi

printf 'VERIFY: FAIL — %d of %d command(s) failed. Do NOT converge on a broken tree.\n' \
  "$failed" "${#CMDS[@]}"
exit 1
