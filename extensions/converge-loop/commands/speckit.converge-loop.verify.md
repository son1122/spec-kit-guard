---
description: "Verify the tree builds and tests pass after an implementation pass, then hand off to convergence"
---

# Post-Implement Verification

Confirm the last implementation pass left a working tree, then continue to convergence. This runs automatically after every `/speckit.implement` via the `after_implement` hook.

Order matters here. `/speckit.converge` reads the codebase as the source of truth about what has been built. Assessing a tree that does not compile, or whose tests fail, produces findings about *intent* when the actual problem is that the last pass left the code broken — and it appends convergence tasks chasing phantom gaps.

## Execution

```bash
if [ -x .specify/extensions/converge-loop/scripts/bash/verify.sh ]; then
  .specify/extensions/converge-loop/scripts/bash/verify.sh
else
  ~/.local/share/speckit-extensions/converge-loop/scripts/bash/verify.sh
fi
```

Commands come from `.specify/verify-commands.txt` when present (one per line, `#` comments, `@slow` to mark a command that `--fast` skips). With none configured it autodetects a Node project's typecheck and test script, so a fresh project still verifies something.

## On PASS

Report which commands ran and that they passed, then proceed to `/speckit.converge`.

## On FAIL — stop

**Do not run `/speckit.converge`.** Report:

- which command failed, and the compiler or test output it produced
- that convergence was skipped deliberately, and why

Then either fix the failure and re-run this check, or hand back to the user. In a `/speckit.converge-loop.run` loop, a verification failure ends the loop — it does not count as an iteration that made progress.

Resist the urge to make the gate pass by weakening it. Deleting a failing test, marking it skipped, or removing a command from `verify-commands.txt` converts a broken build into a green one without fixing anything, and the next converge pass will then assess the tree as though it works. If a test is genuinely wrong, say so explicitly and fix the test as its own change with the reasoning stated — do not silently drop it.

## Configuring

Create `.specify/verify-commands.txt`:

```
npx tsc --noEmit
npm test
npm run test:integration @slow
```

That path is deliberately outside the extension directory, so reinstalling or updating the extension cannot overwrite it.
