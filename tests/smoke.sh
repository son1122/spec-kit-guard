#!/usr/bin/env bash
#
# Smoke tests for both extensions, run against tests/fixture — a minimal but
# complete Spec Kit project.
#
# These exist because every bug shipped in these scripts so far was found by
# hand: a stale-constitution false positive, two parity rules that matched the
# wrong tokens, and a coverage gate that reported PASS when it had found zero
# requirements. Each assertion below corresponds to one of those.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$ROOT/tests/fixture"
GUARD="$ROOT/extensions/guard/scripts/bash/guard-check.sh"
VERIFY="$ROOT/extensions/converge-loop/scripts/bash/verify.sh"

pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n' "$1"; printf '       %s\n' "${2:-}"; fail=$((fail+1)); }

# Work on a scratch copy so tests can mutate the fixture freely.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -r "$FIXTURE/." "$WORK/"

run_guard() { "$GUARD" --repo "$WORK" "$@" 2>&1; }

echo "── guard: clean fixture ──"
out="$(run_guard)"; rc=$?
[[ $rc -eq 0 ]] && ok "exits 0 on a satisfied project" || bad "expected exit 0, got $rc" "$out"
grep -q "all 4 requirements" <<<"$out" && ok "counts 4 requirements" || bad "requirement count wrong" "$out"
grep -q "all 2 user stories (3 acceptance scenarios)" <<<"$out" \
  && ok "counts stories and acceptance scenarios" || bad "story/scenario count wrong" "$out"
grep -q "references v2.3.1" <<<"$out" && ok "reads constitution version" || bad "constitution check wrong" "$out"
grep -q "all 1 test files carry" <<<"$out" \
  && ok "excludes setup.ts from traceability" || bad "harness exclusion broken" "$out"

echo "── guard: FR-002 vs FR-002a word boundary ──"
sed -i 's/ (FR-002a)//' "$WORK/specs/001-demo/tasks.md"
out="$(run_guard)"
grep -q "FR-002a" <<<"$out" && ok "reports FR-002a as uncited" || bad "missed uncited FR-002a" "$out"
grep -qE "^\s+FR-002$" <<<"$out" && bad "FR-002 wrongly reported" "$out" \
  || ok "FR-002 still counted as covered (not confused with FR-002a)"
cp "$FIXTURE/specs/001-demo/tasks.md" "$WORK/specs/001-demo/tasks.md"

echo "── guard: zero requirements must not report PASS ──"
printf '# Spec\n\nNo requirements in the matched format.\n' > "$WORK/specs/001-demo/spec.md"
out="$(run_guard)"
grep -q "no requirements found" <<<"$out" && ok "warns instead of falsely passing" || bad "zero-requirement false clean" "$out"
cp "$FIXTURE/specs/001-demo/spec.md" "$WORK/specs/001-demo/spec.md"

echo "── guard: stale constitution ──"
printf '# Plan\n\n## Constitution Check\n\n**Status: NOT EVALUABLE**\n' > "$WORK/specs/001-demo/plan.md"
out="$(run_guard)"; rc=$?
[[ $rc -eq 1 ]] && ok "fails on a stale Constitution Check" || bad "expected exit 1, got $rc" "$out"
echo "── guard: a corrected plan may still mention NOT EVALUABLE in prose ──"
printf '# Plan\n\n## Constitution Check\n\n**Status: PASS** against v2.3.1.\nPreviously recorded as NOT EVALUABLE.\n' \
  > "$WORK/specs/001-demo/plan.md"
out="$(run_guard)"
grep -q "PASS  plan.md Constitution Check" <<<"$out" \
  && ok "version reference wins over the NOT EVALUABLE phrase" || bad "false positive returned" "$out"
cp "$FIXTURE/specs/001-demo/plan.md" "$WORK/specs/001-demo/plan.md"

echo "── guard: uncovered user story ──"
sed -i 's/\[US2\]/[US1]/' "$WORK/specs/001-demo/tasks.md"
out="$(run_guard)"
grep -q "US2" <<<"$out" && ok "reports the unscheduled user story" || bad "missed uncovered story" "$out"
cp "$FIXTURE/specs/001-demo/tasks.md" "$WORK/specs/001-demo/tasks.md"

echo "── guard: parity rule scoping and transform ──"
printf 'kinds have handlers\tsrc/registry.ts:/const SUPPORTED/,/\\]);/\tkind:[A-Za-z]+\tsrc/handlers.ts\n' \
  > "$WORK/.specify/guard-parity-rules.tsv"
out="$(run_guard)"
grep -q "PASS  kinds have handlers" <<<"$out" && ok "parity passes when handlers exist" || bad "parity false negative" "$out"
sed -i 's/    case "kind:Beta": return 2;//' "$WORK/src/handlers.ts"
out="$(run_guard)"
grep -q "kind:Beta" <<<"$out" && ok "parity catches a missing handler" || bad "parity missed a gap" "$out"
cp "$FIXTURE/src/handlers.ts" "$WORK/src/handlers.ts"

echo "── guard: secret scan ──"
out="$(run_guard)"
grep -q "PASS  no credential patterns" <<<"$out" && ok "clean specs pass" || bad "secret false positive" "$out"
printf '\nToken: ghp_abcdefghijklmnopqrstuvwxyz0123456789\n' >> "$WORK/specs/001-demo/spec.md"
out="$(run_guard)"; rc=$?
[[ $rc -eq 1 ]] && grep -q "possible credential" <<<"$out" \
  && ok "detects a committed token" || bad "missed a token in specs" "$out"
cp "$FIXTURE/specs/001-demo/spec.md" "$WORK/specs/001-demo/spec.md"
printf '\nExample token: ghp_your-token-here-placeholder-value-1234\n' >> "$WORK/specs/001-demo/spec.md"
out="$(run_guard)"
grep -q "PASS  no credential" <<<"$out" && ok "ignores obvious placeholders" || bad "placeholder false positive" "$out"
cp "$FIXTURE/specs/001-demo/spec.md" "$WORK/specs/001-demo/spec.md"

echo "── guard: JSON output ──"
json="$(run_guard --json)"
python3 -c "import json,sys; d=json.load(sys.stdin); assert d['requirements_total']==4; assert d['user_stories_total']==2" <<<"$json" \
  && ok "emits valid JSON with expected counts" || bad "JSON output malformed" "$json"

echo "── guard: outside a project ──"
out="$("$GUARD" --repo /nonexistent-path 2>&1)"; rc=$?
[[ $rc -eq 1 ]] && ok "fails cleanly on a bad --repo" || bad "expected exit 1, got $rc" "$out"

echo "── verify: no commands configured ──"
out="$("$VERIFY" --repo "$WORK" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && grep -q "SKIP" <<<"$out" && ok "skips when nothing to run" || bad "expected clean skip" "$out"

echo "── verify: configured commands ──"
printf 'true\n' > "$WORK/.specify/verify-commands.txt"
out="$("$VERIFY" --repo "$WORK" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "passes when the command succeeds" || bad "expected exit 0, got $rc" "$out"
printf 'true\nfalse\n' > "$WORK/.specify/verify-commands.txt"
out="$("$VERIFY" --repo "$WORK" 2>&1)"; rc=$?
[[ $rc -eq 1 ]] && grep -q "Do NOT converge" <<<"$out" \
  && ok "fails and refuses to converge on a broken tree" || bad "expected exit 1, got $rc" "$out"
printf 'true\nfalse @slow\n' > "$WORK/.specify/verify-commands.txt"
out="$("$VERIFY" --repo "$WORK" --fast 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "--fast skips @slow commands" || bad "@slow not skipped" "$out"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
