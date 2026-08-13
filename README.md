# spec-kit-guard

Two [Spec Kit](https://github.com/github/spec-kit) extensions that make spec-driven development harder to fool.

| Extension | What it does |
|---|---|
| **[guard](extensions/guard)** | Three deterministic gates — every requirement is cited by a task, the plan's Constitution Check matches the ratified constitution, and nothing is registered as supported before its handler exists |
| **[converge-loop](extensions/converge-loop)** | Verifies the tree builds and tests pass after every implement pass, then converges — and can loop implement → verify → converge until the feature is done |

Both are Bash, grep and sed only. No YAML parser, no Python, no network at runtime.

## Install

Add this catalog once per project, then install by name:

```bash
specify extension catalog add https://raw.githubusercontent.com/son1122/spec-kit-guard/main/catalog.json
specify extension add guard
specify extension add converge-loop
```

Update later:

```bash
specify extension update guard
specify extension update converge-loop
```

Or install straight from a release without registering the catalog:

```bash
specify extension add guard --from https://github.com/son1122/spec-kit-guard/releases/download/v1.0.0/guard.zip
```

## Why these exist

`/speckit.analyze` reasons across your artifacts and finds problems no pattern match could. It is also the pass that will occasionally miss an item, or report a gap that does not exist because it did not read your existing schema. These extensions are the opposite trade: narrow, mechanical checks that are exhaustive and safe to block on.

Each gate was written after a specific failure got through:

- A mandatory requirement was written into `spec.md` and never made it into `tasks.md`. Nothing noticed, because `tasks.md` read as complete without it.
- A plan's Constitution Check was written while the constitution was still the placeholder template, and stayed stale after ratification. The plan looked finished and its gate table looked populated.
- An element type was registered as supported before its handler existed, so the engine parsed it, walked straight past it, and reported the run as succeeded.
- An implement pass left the tree with failing tests, and convergence then assessed that tree as the truth about what was built.

## Spec Guard

Runs on `after_tasks` (blocking), `after_plan` (prompts), and `before_implement` (blocking).

1. **Requirement coverage** — every `FR-###` in `spec.md` is cited by at least one task. Word-boundary aware, so `FR-012` is not treated as covered by a task citing only `FR-012a`. Detects a missing *citation*, which is not identical to missing work: a requirement may be implemented by a task that does not name it. Fix by citing it there, never by tagging an unrelated task.
2. **Constitution freshness** — `plan.md`'s Constitution Check references the version in `.specify/memory/constitution.md`. An unratified constitution is a warning, not a failure.
3. **Registry / handler parity** — off until you define rules in `parity-rules.tsv`. Gates 1 and 2 need no configuration in any project; this one is inherently project-specific.

## Converge Loop

Runs on `after_implement` (blocking).

Verification comes **before** convergence, deliberately. `/speckit.converge` reads the codebase as the source of truth about what is built, so assessing a tree that does not compile produces findings about intent when the real problem is a broken tree.

Verify commands come from `.specify/verify-commands.txt`:

```
npx tsc --noEmit
npm test
npm run test:integration @slow
```

That path sits outside the extension directory, so updating the extension cannot overwrite it. With no file present, a Node project's typecheck and test script are autodetected.

`/speckit.converge-loop.run` alternates implement → verify → converge until convergence reports nothing remaining. It is bounded (default 5 iterations) and stops early on no progress, a task count that is not shrinking, an implement pass that changed no files, or a CRITICAL constitution violation surviving two iterations — because a loop that keeps appending tasks it never completes burns tokens while the code stands still.

## Configuration that survives updates

Anything under `.specify/extensions/<id>/` is replaced when an extension is updated. Keep project-specific configuration outside it:

| Setting | Put it here |
|---|---|
| Verify commands | `.specify/verify-commands.txt` |
| Parity rules | `.specify/guard-parity-rules.tsv` |

Both are read in preference to the in-extension copies.

## Exit codes

`0` pass · `1` fail. Both scripts are usable directly as CI steps:

```yaml
- run: .specify/extensions/guard/scripts/bash/guard-check.sh
- run: .specify/extensions/converge-loop/scripts/bash/verify.sh
```

## Licence

MIT
