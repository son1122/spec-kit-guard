#!/usr/bin/env bash
#
# Spec Guard — deterministic pre-implementation gates.
#
# Three checks, all mechanical. Nothing here infers or judges; every failure is
# a grep that found nothing where something was required. That is the point:
# the LLM-driven /speckit.analyze pass is good at reasoning and bad at being
# exhaustive, and it will occasionally report a gap that does not exist because
# it did not read the existing schema. These checks are the opposite trade —
# narrow, boring, and reliable enough to gate on.
#
# Exit 0 = all enabled gates pass. Exit 1 = at least one gate failed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

JSON=false
REPO_ROOT="${SPECIFY_REPO_ROOT:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON=true; shift ;;
    --repo) REPO_ROOT="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'USAGE'
guard-check.sh [--json] [--repo <path>]

  --json          machine-readable output
  --repo <path>   project root; defaults to the installed location, or the
                  nearest ancestor of $PWD containing .specify/

Exit 0 when all enabled gates pass, 1 otherwise.
USAGE
      exit 0 ;;
    *) echo "guard-check.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

# Repo root resolution. This script runs from two places: the copy installed
# into a project under .specify/extensions/guard, and the shared copy invoked
# from anywhere (e.g. a user-level agent skill). Deriving the root from the
# script's own path is only correct for the first.
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
  echo "GUARD: no Spec Kit project found (no .specify/ in $PWD or any parent). Use --repo <path>." >&2
  exit 1
fi

# Config resolution, most specific first. The `.specify/` paths sit OUTSIDE the
# extension directory on purpose: updating or reinstalling an extension replaces
# everything under .specify/extensions/<id>/, which has already silently
# discarded a project's parity rules once. Configuration a project owns must not
# live somewhere the package manager overwrites.
CONFIG="$EXT_DIR/guard-config.yml"
PARITY_RULES="$EXT_DIR/parity-rules.tsv"

for c in "$REPO_ROOT/.specify/extensions/guard/guard-config.yml" \
         "$REPO_ROOT/.specify/guard-config.yml"; do
  [[ -f "$c" ]] && CONFIG="$c"
done
for r in "$REPO_ROOT/.specify/extensions/guard/parity-rules.tsv" \
         "$REPO_ROOT/.specify/guard-parity-rules.tsv"; do
  [[ -f "$r" ]] && PARITY_RULES="$r"
done

# --- config -----------------------------------------------------------------
# Flat scalars only, so this stays parseable without a YAML dependency.
cfg() {
  local key="$1" default="$2" val
  [[ -f "$CONFIG" ]] || { printf '%s' "$default"; return; }
  val="$(grep -E "^${key}:" "$CONFIG" 2>/dev/null | head -1 | sed -E "s/^${key}:[[:space:]]*//; s/[[:space:]]*(#.*)?$//" || true)"
  printf '%s' "${val:-$default}"
}

FAIL_COVERAGE="$(cfg fail_on_uncovered_requirements true)"
FAIL_CONSTITUTION="$(cfg fail_on_stale_constitution true)"
FAIL_PARITY="$(cfg fail_on_parity_violation true)"
FAIL_STORIES="$(cfg fail_on_uncovered_user_stories true)"
# Defaults to advisory: a project adopting this mid-flight would otherwise be
# blocked by every pre-existing test file at once. Turn it on once the backlog
# is cleared.
FAIL_UNTRACED="$(cfg fail_on_untraced_tests false)"
# Defaults to blocking. A committed credential is worse than a noisy gate, and
# the patterns below match real token shapes rather than the word "secret".
FAIL_SECRETS="$(cfg fail_on_secrets_in_specs true)"
TEST_DIRS="$(cfg test_dirs "tests e2e")"

# --- locate the active feature ----------------------------------------------
FEATURE_DIR="${SPECIFY_FEATURE_DIRECTORY:-}"
if [[ -z "$FEATURE_DIR" && -f "$REPO_ROOT/.specify/feature.json" ]]; then
  FEATURE_DIR="$(sed -nE 's/.*"feature_directory"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
    "$REPO_ROOT/.specify/feature.json" | head -1)"
fi
[[ -n "$FEATURE_DIR" && "$FEATURE_DIR" != /* ]] && FEATURE_DIR="$REPO_ROOT/$FEATURE_DIR"

if [[ -z "$FEATURE_DIR" || ! -d "$FEATURE_DIR" ]]; then
  echo "GUARD: no active feature directory (set SPECIFY_FEATURE_DIRECTORY or run from a Spec Kit feature)" >&2
  exit 1
fi

SPEC="$FEATURE_DIR/spec.md"
TASKS="$FEATURE_DIR/tasks.md"
PLAN="$FEATURE_DIR/plan.md"
CONSTITUTION="$REPO_ROOT/.specify/memory/constitution.md"

failures=0
declare -a uncovered=() parity_violations=() uncovered_stories=() untraced=() secret_hits=()
constitution_status="skipped"
req_total=0
req_covered=0
story_total=0
scenario_total=0
test_files_total=0
test_files_checked=0

section() { $JSON || printf '\n%s\n' "$1"; }

# --- Check A: every requirement is claimed by at least one task --------------
# Catches the case where a mandatory requirement is written into the spec and
# then silently dropped during task generation. Word boundaries matter here:
# "FR-012" must not be considered covered by a task that only mentions
# "FR-012a", which is a different requirement.
if [[ -f "$SPEC" && -f "$TASKS" ]]; then
  section "── Requirement coverage ──"
  while IFS= read -r req; do
    [[ -z "$req" ]] && continue
    req_total=$((req_total + 1))
    if grep -qE "(^|[^A-Za-z0-9-])${req}([^A-Za-z0-9]|$)" "$TASKS"; then
      req_covered=$((req_covered + 1))
    else
      uncovered+=("$req")
    fi
  done < <(grep -oE '^- \*\*(FR-[0-9]+[a-z]*)\*\*' "$SPEC" 2>/dev/null \
             | grep -oE 'FR-[0-9]+[a-z]*' | sort -u -V)

  if ((${#uncovered[@]} > 0)); then
    $JSON || {
      printf '  FAIL  %d of %d requirements are cited by no task:\n' "${#uncovered[@]}" "$req_total"
      printf '        %s\n' "${uncovered[@]}"
      printf '        (a requirement may still be implemented by an uncited task;\n'
      printf '         cite it there rather than assuming it is covered)\n'
    }
    [[ "$FAIL_COVERAGE" == "true" ]] && failures=$((failures + 1))
  elif ((req_total == 0)); then
    # Reporting PASS here would be a false clean: finding no requirements means
    # the spec does not use the `- **FR-001**: ...` form this gate matches, not
    # that every requirement is covered. A gate that passes because it looked at
    # nothing is worse than no gate, because it still reports green.
    $JSON || {
      printf '  WARN  no requirements found in spec.md matching "- **FR-###**:"\n'
      printf '        This gate cannot verify coverage. Either the spec uses a\n'
      printf '        different requirement format, or it has no requirements yet.\n'
    }
  else
    $JSON || printf '  PASS  all %d requirements claimed by at least one task\n' "$req_total"
  fi
else
  section "── Requirement coverage ──"
  $JSON || printf '  SKIP  spec.md or tasks.md not present yet\n'
fi

# --- Check B: the plan's Constitution Check matches the ratified constitution -
# A Constitution Check written against a placeholder stays stale after the
# constitution is ratified, and nothing else in the toolchain notices.
if [[ -f "$CONSTITUTION" && -f "$PLAN" ]]; then
  section "── Constitution freshness ──"
  if grep -q '\[CONSTITUTION_VERSION\]' "$CONSTITUTION"; then
    constitution_status="unratified"
    $JSON || printf '  WARN  constitution is still the unratified template; run /speckit.constitution\n'
  else
    cver="$(grep -oE '^\*\*Version\*\*:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' "$CONSTITUTION" \
             | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [[ -z "$cver" ]]; then
      constitution_status="unparseable"
      $JSON || printf '  WARN  cannot read a version from constitution.md\n'
    # Order matters. Check for the version reference FIRST: a plan that has
    # been brought up to date may still mention "NOT EVALUABLE" in prose,
    # explaining what its Constitution Check used to say. Grepping for that
    # phrase first reports a current plan as stale — which this check did on
    # its first run against a plan it had itself just corrected.
    elif grep -qF "$cver" "$PLAN"; then
      constitution_status="current"
      $JSON || printf '  PASS  plan.md Constitution Check references v%s\n' "$cver"
    elif grep -q 'NOT EVALUABLE' "$PLAN"; then
      constitution_status="stale"
      $JSON || printf '  FAIL  plan.md Constitution Check says NOT EVALUABLE, but constitution v%s is ratified\n' "$cver"
      [[ "$FAIL_CONSTITUTION" == "true" ]] && failures=$((failures + 1))
    else
      constitution_status="stale"
      $JSON || printf '  FAIL  plan.md does not reference constitution v%s — re-run the Constitution Check\n' "$cver"
      [[ "$FAIL_CONSTITUTION" == "true" ]] && failures=$((failures + 1))
    fi
  fi
fi

# --- Check C: nothing is registered as supported before its handler exists ----
# Project-specific, declared in parity-rules.tsv. The failure this prevents is
# the worst one available in an execution engine: the element parses, the run
# walks past it, and the operator is told the step succeeded.
if [[ -f "$PARITY_RULES" ]]; then
  section "── Registry / handler parity ──"
  rule_count=0
  while IFS=$'\t' read -r name source pattern target transform || [[ -n "${name:-}" ]]; do
    [[ -z "${name:-}" || "$name" == \#* ]] && continue
    rule_count=$((rule_count + 1))

    # `source` may carry a sed address range after the path, e.g.
    #   path/to/file.ts:/const SUPPORTED_TYPES/,/\]\);/
    # Without it a pattern matches the whole file, which produces false
    # positives: a parser file normally mentions type names outside its
    # supported-types set, and none of those are meant to have a handler.
    if [[ "$source" == *:/* ]]; then
      src="$REPO_ROOT/${source%%:/*}"
      src_range="/${source#*:/}"
    else
      src="$REPO_ROOT/$source"
      src_range=""
    fi

    tgt="$REPO_ROOT/$target"
    if [[ ! -f "$src" || ! -f "$tgt" ]]; then
      $JSON || printf '  SKIP  %s (source or target not present yet)\n' "$name"
      continue
    fi

    if [[ -n "$src_range" ]]; then
      extracted="$(sed -n "${src_range}p" "$src" 2>/dev/null | grep -oE "$pattern" 2>/dev/null | sort -u || true)"
    else
      extracted="$(grep -oE "$pattern" "$src" 2>/dev/null | sort -u || true)"
    fi

    # Optional sed transform, for when the registry and the implementation
    # spell the same thing differently — a schema may store "HttpCall" for
    # what the parser calls "ext:HttpCall".
    if [[ -n "${transform:-}" ]]; then
      extracted="$(printf '%s\n' "$extracted" | sed -E "$transform" | sort -u)"
    fi

    missing=()
    while IFS= read -r token; do
      [[ -z "$token" ]] && continue
      grep -qF "$token" "$tgt" || missing+=("$token")
    done < <(printf '%s\n' "$extracted")

    if ((${#missing[@]} > 0)); then
      parity_violations+=("$name: ${missing[*]}")
      $JSON || {
        printf '  FAIL  %s — registered in %s with no handler in %s:\n' "$name" "$source" "$target"
        printf '        %s\n' "${missing[@]}"
      }
      [[ "$FAIL_PARITY" == "true" ]] && failures=$((failures + 1))
    else
      $JSON || printf '  PASS  %s\n' "$name"
    fi
  done < "$PARITY_RULES"
  ((rule_count == 0)) && { $JSON || printf '  SKIP  no parity rules defined\n'; }
fi

# --- Check D: every user story is claimed by at least one task ---------------
# Requirement coverage alone misses this. A spec's user stories carry the
# acceptance scenarios that define "done", and a story with no task is a whole
# slice of intent nobody scheduled.
if [[ -f "$SPEC" && -f "$TASKS" ]]; then
  section "── User story coverage ──"
  scenario_total="$(grep -cE '^\s*[0-9]+\.\s+\*\*Given\*\*' "$SPEC" 2>/dev/null || true)"
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    story_total=$((story_total + 1))
    us="US${n}"
    grep -qE "(\[${us}\]|(^|[^A-Za-z0-9])${us}([^A-Za-z0-9]|$))" "$TASKS" \
      || uncovered_stories+=("$us")
  done < <(grep -oE '^### User Story [0-9]+' "$SPEC" 2>/dev/null | grep -oE '[0-9]+$' | sort -un)

  if ((story_total == 0)); then
    $JSON || printf '  WARN  no "### User Story N" headings found in spec.md\n'
  elif ((${#uncovered_stories[@]} > 0)); then
    $JSON || {
      printf '  FAIL  %d of %d user stories have no task:\n' "${#uncovered_stories[@]}" "$story_total"
      printf '        %s\n' "${uncovered_stories[@]}"
    }
    [[ "$FAIL_STORIES" == "true" ]] && failures=$((failures + 1))
  else
    $JSON || printf '  PASS  all %d user stories (%s acceptance scenarios) claimed by tasks\n' \
      "$story_total" "$scenario_total"
  fi
fi

# --- Check E: every test file says which requirement it validates ------------
# A test suite that cannot be traced back to requirements cannot answer "is this
# requirement tested?" — you can only answer "do the tests pass?", which is a
# different and much weaker question.
section "── Test traceability ──"
declare -a test_files=()
# shellcheck disable=SC2086  # TEST_DIRS is a space-separated list by design
for d in $TEST_DIRS; do
  [[ -d "$REPO_ROOT/$d" ]] || continue
  while IFS= read -r f; do test_files+=("$f"); done < <(
    find "$REPO_ROOT/$d" -type f \
      \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
         -o -name '*.py' -o -name '*.go' -o -name '*.rb' -o -name '*.rs' \
         -o -name '*.java' -o -name '*.sh' \) 2>/dev/null | sort
  )
done
test_files_total=${#test_files[@]}
if ((test_files_total == 0)); then
  $JSON || printf '  SKIP  no test files found under: %s\n' "$TEST_DIRS"
else
  for f in "${test_files[@]}"; do
    # Harnesses are not tests. setup, fixtures, helpers and conftest exist to
    # support the suite, so demanding a requirement reference on them produces
    # noise that trains people to ignore this gate.
    case "$(basename "$f")" in
      setup.*|*-setup.*|global-setup.*|fixtures.*|*-fixtures.*|helpers.*|*-helpers.*|conftest.*|*.config.*) continue ;;
    esac
    test_files_checked=$((test_files_checked + 1))
    grep -qE 'Spec:\s*[A-Za-z]{2,3}-?[0-9]' "$f" || untraced+=("${f#"$REPO_ROOT"/}")
  done
  if ((${#untraced[@]} > 0)); then
    lbl="WARN"; [[ "$FAIL_UNTRACED" == "true" ]] && lbl="FAIL"
    $JSON || {
      printf '  %s  %d of %d test files carry no "Spec:" reference:\n' \
        "$lbl" "${#untraced[@]}" "$test_files_checked"
      printf '        %s\n' "${untraced[@]:0:15}"
      ((${#untraced[@]} > 15)) && printf '        … and %d more\n' "$((${#untraced[@]} - 15))"
    }
    [[ "$FAIL_UNTRACED" == "true" ]] && failures=$((failures + 1))
  else
    $JSON || printf '  PASS  all %d test files carry a Spec: reference\n' "$test_files_checked"
  fi
fi

# --- Check F: no credentials in specification artifacts ----------------------
# Specs, plans and research notes accumulate real hostnames, sample tokens and
# API URLs, and then get committed and shared. Code gets scanned for secrets as
# a matter of course; the documents beside it almost never do.
section "── Secrets in spec artifacts ──"
SECRET_SCAN_DIRS=()
[[ -d "$REPO_ROOT/specs" ]] && SECRET_SCAN_DIRS+=("$REPO_ROOT/specs")
[[ -d "$REPO_ROOT/.specify/memory" ]] && SECRET_SCAN_DIRS+=("$REPO_ROOT/.specify/memory")

if ((${#SECRET_SCAN_DIRS[@]} == 0)); then
  $JSON || printf '  SKIP  no specs/ or .specify/memory/ to scan\n'
else
  ALLOWLIST="$REPO_ROOT/.specify/guard-secret-allowlist.txt"
  # Tight patterns: real token shapes and credentials-in-URL, not the mere
  # appearance of the word "secret". A gate that cries wolf gets disabled.
  SECRET_PATTERNS='-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{32,}|AIza[0-9A-Za-z_-]{30,}|(api[_-]?key|secret|token|password)["'"'"']?\s*[:=]\s*["'"'"'][^"'"'"'[:space:]]{16,}["'"'"']|[a-z][a-z0-9+.-]*://[^/[:space:]:@]+:[^/[:space:]:@]+@'
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    # Drop obvious placeholders before reporting — these are what specs are
    # legitimately full of.
    echo "$hit" | grep -qiE 'example|placeholder|redacted|your[-_]|changeme|xxxx|<[^>]+>|\$\{|dummy|sample|fake|test[-_]?key' && continue
    [[ -f "$ALLOWLIST" ]] && echo "$hit" | grep -qEf "$ALLOWLIST" && continue
    secret_hits+=("${hit#"$REPO_ROOT"/}")
  # -e is mandatory, not stylistic: this pattern starts with "-----BEGIN", so
  # without it grep parses the whole alternation as command-line options, exits
  # with a usage error, and the scan silently matches nothing forever.
  done < <(grep -rEIn -e "$SECRET_PATTERNS" "${SECRET_SCAN_DIRS[@]}" 2>/dev/null || true)

  if ((${#secret_hits[@]} > 0)); then
    $JSON || {
      printf '  FAIL  %d possible credential(s) in specification artifacts:\n' "${#secret_hits[@]}"
      # Values are truncated: printing a live credential in full into CI logs
      # would republish the very thing this gate exists to catch.
      for h in "${secret_hits[@]:0:10}"; do printf '        %.120s\n' "$h"; done
      ((${#secret_hits[@]} > 10)) && printf '        … and %d more\n' "$((${#secret_hits[@]} - 10))"
      printf '        Rotate anything real, then add false positives as regexes to\n'
      printf '        .specify/guard-secret-allowlist.txt\n'
    }
    [[ "$FAIL_SECRETS" == "true" ]] && failures=$((failures + 1))
  else
    $JSON || printf '  PASS  no credential patterns in %d scanned location(s)\n' "${#SECRET_SCAN_DIRS[@]}"
  fi
fi

# --- report ------------------------------------------------------------------
if $JSON; then
  printf '{"feature_dir":"%s","requirements_total":%d,"requirements_covered":%d,' \
    "$FEATURE_DIR" "$req_total" "$req_covered"
  printf '"uncovered":['
  for i in "${!uncovered[@]}"; do
    ((i > 0)) && printf ','
    printf '"%s"' "${uncovered[$i]}"
  done
  printf '],"constitution":"%s","parity_violations":%d,' \
    "$constitution_status" "${#parity_violations[@]}"
  printf '"user_stories_total":%d,"user_stories_uncovered":%d,"acceptance_scenarios":%s,' \
    "$story_total" "${#uncovered_stories[@]}" "${scenario_total:-0}"
  printf '"test_files":%d,"tests_untraced":%d,"secret_hits":%d,"failures":%d}\n' \
    "$test_files_checked" "${#untraced[@]}" "${#secret_hits[@]}" "$failures"
else
  printf '\n'
  if ((failures == 0)); then
    printf 'GUARD: PASS — %d/%d requirements claimed, constitution %s\n' \
      "$req_covered" "$req_total" "$constitution_status"
  else
    printf 'GUARD: FAIL — %d gate(s) failed. Resolve before /speckit.implement.\n' "$failures"
  fi
fi

exit $((failures > 0 ? 1 : 0))
