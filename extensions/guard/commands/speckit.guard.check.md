---
description: "Run the requirement-coverage, constitution-freshness, and registry-parity gates"
---

# Spec Guard Check

Run three deterministic gates over the active feature. Every result is mechanical — a grep that either found the required reference or did not. Nothing here reasons or infers.

This complements `/speckit.analyze` rather than replacing it. Analyze reasons across artifacts and finds problems no pattern match could; it is also the pass that will occasionally miss an item or report a gap that does not exist because it did not read the existing schema. These gates are the opposite trade: narrow, exhaustive, and safe to block on.

## Execution

- **Bash**: `.specify/extensions/guard/scripts/bash/guard-check.sh`
- Machine-readable: append `--json`

Run the script and report its output. Do not re-derive the findings yourself — the script's exit code is the verdict.

## The gates

**1. Requirement coverage.** Every `FR-###` defined in `spec.md` must be referenced by at least one task in `tasks.md`. Matching is word-boundary aware, so `FR-012` is not considered covered by a task that only mentions `FR-012a`.

Prevents: a mandatory requirement written into the spec and then silently dropped during task generation. Nothing else in the toolchain notices, because tasks.md is internally consistent without it.

**2. Constitution freshness.** `plan.md`'s Constitution Check must reference the ratified constitution version. Fails if the plan still says `NOT EVALUABLE`, or if it references no version matching `constitution.md`.

Prevents: a Constitution Check written while the constitution was a placeholder, left stale after ratification. The plan looks complete and its gate table looks populated, so the staleness is invisible on inspection.

**3. Registry / handler parity.** For each rule in `parity-rules.tsv`, every token extracted from the source file must appear in the target file.

Prevents: registering a type as supported before the code that handles it exists. In an execution engine this is the worst failure available — the element parses, the run walks past it, and the operator is told the step succeeded. This is why the check exists as a gate rather than a review note.

## Interpreting the result

- **Exit 0** — all enabled gates pass. Proceed.
- **Exit 1** — at least one gate failed. Report exactly which, and what would resolve it:
  - *Uncovered requirements*: add tasks claiming them, or, if the requirement is genuinely out of scope for this feature, move it to the spec's Out of Scope section. Do not tag an unrelated task with the requirement id to silence the gate — that converts a real gap into a false clean.
  - *Stale constitution*: re-run `/speckit.plan`, or update the Constitution Check to cite the current version and principles.
  - *Parity violation*: implement the missing handler, or remove the registration until the handler exists.

Do not edit files to make a gate pass unless the fix is the genuine one. A gate that has been worked around is worse than no gate, because it is still reported as passing.

## Configuration

`.specify/extensions/guard/guard-config.yml` — each gate can be turned from failing to advisory. `.specify/extensions/guard/parity-rules.tsv` — one row per registry to hold to its implementation.
