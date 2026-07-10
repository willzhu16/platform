# Definition of done

A change is done when **all** of these hold. Not "mostly"; the last 10% is where the
bugs live. Agents receive this via athena `00-universal.md`, which links here.

- [ ] **All CI checks green** — `ci / lint`, `ci / typecheck`, `ci / test`, `ci / commits`,
      and the `security /` checks (+ `codeql / analyze` on public repos). Not "the ones
      near my change" — the whole matrix.
- [ ] **Acceptance criteria demonstrated** — each maps to a test or a documented manual
      check. A criterion with neither is not met, it is hoped for.
- [ ] **Behavior verified by running it** — the affected flow was exercised and observed,
      not inferred from a green test. "It compiles" is not verification.
- [ ] **Docs updated in the same PR** — README, runbooks, or an ADR, as applicable. New
      config keys are documented where they are read.
- [ ] **The diff is clean** — no debug logging, commented-out experiments, or stray TODOs
      introduced by the change.
- [ ] **Scope matches the task** — everything asked for is done; nothing unasked-for
      snuck in. Partial work reported as done is worse than a question asked early.

## Why this exists

The gate matrix is the reviewer (D-04): with no second human to catch a rushed merge,
"done" has to mean something enforceable. This list is that meaning. A human still does a
final read before clicking merge — but the checklist is what makes the read short.
