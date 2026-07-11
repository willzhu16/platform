# Severity levels

**Frozen enum — exactly three levels.** Consumed by spec 08 alert routing; the strings
`SEV1`/`SEV2`/`SEV3` are a contract, not a suggestion. A solo dev with more levels routes
everything to "later" — three is the discipline.

| Level | Meaning | Routing | Examples |
|---|---|---|---|
| **SEV1** | Page — act now | ntfy push (interrupt) | production down; data loss in progress; suspected security breach; error rate >5% for 5 min |
| **SEV2** | Today | reviewed same day | prod degraded but a workaround holds; a security-scan finding on `main` |
| **SEV3** | Digest | weekly cadence review | everything else worth recording |

## Rules

- **SEV1 is allowed to interrupt a human.** If it wouldn't justify stopping what you are
  doing, it is not a SEV1 — downgrade it, don't cry wolf.
- **When unsure between two levels, pick the higher one once**, then correct at review.
  Under-paging is more expensive than one noisy alert.
- The level is set at **declare** time (see [incident-process.md](incident-process.md))
  and may be revised as understanding changes; the final level lands in the postmortem.
- SEV3 is not a graveyard: the weekly digest is *read*, and recurring SEV3s are a signal
  to file a systemic fix (that is the [cadence](cadences.md) working).
