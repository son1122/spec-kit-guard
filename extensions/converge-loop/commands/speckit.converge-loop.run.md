---
description: "Alternate implement and converge until the feature converges, bounded and with a no-progress stop condition"
---

# Converge Loop

Run `/speckit.implement` and `/speckit.converge` in alternation until convergence reports no remaining work, then stop.

This exists because a single implement pass rarely satisfies a whole feature, and `/speckit.converge` is the command that finds what is still missing. Running them in a loop closes the gap without a human re-issuing the same two commands.

## The loop

Track an iteration counter starting at 1 and a `max_iterations` limit (default 5, configurable in `.specify/extensions/converge-loop/converge-loop-config.yml`).

Each iteration:

1. Run `/speckit.implement`.
2. Run `/speckit.converge-loop.verify`. **If it fails, stop the loop** — report the failing command and its output. Never converge on a tree that does not build or whose tests fail: converge reads the codebase as the truth about what is built, so a broken tree produces findings that chase phantom gaps.
3. Run `/speckit.converge`.
4. Read converge's outcome:
   - **`converged`** — the implementation satisfies spec, plan, and tasks. **Stop. Report success.**
   - **`tasks_appended`** — record how many tasks it appended and under which phase, then continue to the next iteration.
4. Before starting the next iteration, evaluate the stop conditions below.

## Stop conditions — check every iteration

Stop and report, even when converge is still appending tasks, if any of these hold. An unbounded loop that keeps appending tasks it never completes will burn tokens indefinitely and leave `tasks.md` growing without the code improving.

**1. Iteration limit reached.** Stop at `max_iterations`. Report how many iterations ran and what converge still reports as outstanding.

**2. No progress.** If this iteration's converge appended tasks that are substantively the same as the previous iteration's — same source refs, same gap types — implement is not actually completing them. Stop and report the repeating findings. Looping again will produce the same result.

**3. Task count is growing, not shrinking.** If the count of appended tasks has not decreased across two consecutive iterations, stop. Convergence is diverging.

**4. Implement made no file changes.** If an implement pass modifies nothing, the loop cannot progress. Stop.

**5. A CRITICAL constitution violation persists** across two iterations. Stop and escalate to the user rather than looping — a MUST-principle violation that implement cannot clear needs a human decision, and may indicate the spec and the code genuinely disagree.

## Reporting

Report after every iteration, not only at the end, so the user can interrupt:

```
Iteration 2/5 — converge appended 4 tasks under Phase 11 (was 9 under Phase 10)
```

On completion, report: total iterations, whether it ended `converged` or on a stop condition, the total tasks appended and completed across the run, and anything still outstanding.

## Notes

- Every implement pass fires whatever `before_implement` gates are registered (e.g. Spec Guard). A blocked gate stops the loop — that is intended; fix the gate's finding rather than disabling it.
- Converge is append-only. It never rewrites or renumbers existing tasks, so a long loop leaves a readable history of what each pass found.
- If the user asked for a single pass, do not loop — run implement and converge once and report.
