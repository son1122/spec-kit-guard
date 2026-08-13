# Spec Guard

Deterministic pre-implementation gates for Spec Kit projects.

`/speckit.analyze` reasons across your artifacts and finds problems no pattern match could. It is also the pass that will occasionally miss an item, or report a gap that does not exist because it did not read your existing schema. Spec Guard is the opposite trade: three narrow, mechanical checks that are exhaustive and safe to block on.

## Install into any project

```bash
cd /path/to/your-speckit-project
specify extension add ~/.local/share/speckit-extensions/guard --dev
```

Then run it directly, or let the hooks fire:

```bash
.specify/extensions/guard/scripts/bash/guard-check.sh
.specify/extensions/guard/scripts/bash/guard-check.sh --json
```

Your agent also gets a `/speckit.guard.check` command.

## The three gates

**1. Requirement coverage.** Every `FR-###` defined in `spec.md` must be cited by at least one task in `tasks.md`. Matching is word-boundary aware, so `FR-012` is not treated as covered by a task that only mentions `FR-012a`.

Catches a requirement written into the spec and then dropped during task generation. Nothing else notices, because `tasks.md` reads as complete and internally consistent without it.

Note what this gate does and does not prove. It detects a missing *citation*. A requirement may well be implemented by a task that simply does not name it — that is still worth fixing, because an uncited requirement is indistinguishable from a forgotten one on the next pass. Cite it in the task that implements it; do not tag an unrelated task to silence the gate.

**2. Constitution freshness.** `plan.md`'s Constitution Check must reference the version in `.specify/memory/constitution.md`.

Catches a Constitution Check written while the constitution was still the placeholder and left stale after ratification. The plan looks complete and its gate table looks populated, so this is invisible on inspection.

Reports the constitution as unratified (a warning, not a failure) when it is still the template.

**3. Registry / handler parity.** Off by default; see `parity-rules.tsv`.

Catches something registered as supported before its implementation exists. This is the worst failure available in a dispatcher: the entry parses, execution walks past it, and the operator is told it succeeded.

## Configuration

- `guard-config.yml` — turn any gate from failing to advisory.
- `parity-rules.tsv` — one row per registry to hold to its implementation. No rules are active by default; gates 1 and 2 need no configuration.

## Hooks

| Hook | Blocking | Purpose |
|---|---|---|
| `after_tasks` | yes | Catch an uncited requirement the moment tasks are generated |
| `after_plan` | no (prompts) | Confirm the Constitution Check is current |
| `before_implement` | yes | Nothing gets built on a stale plan or a dropped requirement |

Disable any of them in `.specify/extensions.yml`, or `specify extension disable guard`.

## Exit codes

`0` all enabled gates pass · `1` at least one failed.

Usable in CI directly:

```yaml
- run: .specify/extensions/guard/scripts/bash/guard-check.sh
```

## Requirements

Bash, grep, sed. No YAML parser, no Python, no network.
