# Converge Loop

Verify the tree after every implement pass, then converge — and optionally keep looping until the feature is done.

## Install

```bash
specify extension catalog add https://raw.githubusercontent.com/son1122/spec-kit-guard/main/catalog.json \
  --name spec-kit-guard --install-allowed
specify extension add converge-loop
```

## What it wires up

| Hook | Runs | Blocking |
|---|---|---|
| `after_implement` | `speckit.converge-loop.verify` | yes |
| `after_converge` | `speckit.implement` | prompts |

Every `/speckit.implement` is followed by verification. On success it hands off to `/speckit.converge`; on failure it stops and reports, and convergence does not run.

Verification comes **before** convergence deliberately. `/speckit.converge` reads the codebase as the source of truth about what has been built. Assessing a tree that does not compile, or whose tests fail, produces findings about *intent* when the actual problem is that the last pass left the code broken — and it then appends convergence tasks chasing gaps that do not exist.

If convergence appends tasks, the `after_converge` hook offers to run implement again. That is the loop, with one confirmation per iteration so it cannot run away unattended.

## Configuring verification

Create `.specify/verify-commands.txt` — one command per line, `#` for comments, `@slow` to mark a command that `--fast` skips:

```
npx tsc --noEmit
npm test
npm run test:integration @slow
```

That path is outside the extension directory, so updating the extension cannot overwrite it. With no file present, a Node project's typecheck and test script are autodetected, so a fresh project still gates on something real.

Run it directly:

```bash
.specify/extensions/converge-loop/scripts/bash/verify.sh [--fast] [--repo <path>]
```

Exit `0` when everything passed, `1` when anything failed. Usable as a CI step.

## Unattended looping

`/speckit.converge-loop.run` alternates implement → verify → converge until convergence reports nothing remaining.

Bounded at `max_iterations` (default 5, in `converge-loop-config.yml`), and stops early on any of:

- **no progress** — convergence appends substantively the same findings twice, so implement is not clearing them
- **task count not shrinking** across two iterations — convergence is diverging
- **implement changed no files**
- **a CRITICAL constitution violation surviving two iterations** — escalates to a human instead of looping, since that usually means the spec and the code genuinely disagree

Those stop conditions matter more than the iteration cap. A loop that keeps appending tasks it never completes burns tokens and grows `tasks.md` while the code stands still.

## A note on green builds

Do not make the gate pass by weakening it. Deleting a failing test, marking it skipped, or dropping a command from `verify-commands.txt` turns a broken build green without fixing anything, and the next convergence pass then assesses the tree as though it works. If a test is genuinely wrong, fix the test as its own change with the reasoning stated.

## Licence

MIT
