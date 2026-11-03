# Cadences

The recurring maintenance that keeps the system from decaying. Implemented as scheduled
GitHub issues opened by [`platform/.github/workflows/cadence.yml`](../.github/workflows/cadence.yml),
which reads each issue's checklist from this file when it runs, so editing a list here is the
whole change. Opening an issue closes the previous open one of the same cadence, so an
unworked checklist does not pile up behind the next.

## Monthly (1st)

- [ ] **Open bot PRs.** Renovate's non-major batch and the lock file refresh merge themselves
      when green, and template sync opens a PR in each repo weekly. What is left is majors,
      anything that went red, and any sync PR that copier left with conflict markers.
- [ ] **Session-log harvest.** Read the month's agent session logs; convert recurring
      mistakes into a lint/CI rule (preferred, deterministic) or an instruction line
      (fallback). This is the athena flywheel (ARCHITECTURE §6.0 rule 5) made a ritual.
      Start by tallying the enumerated fields (Plan / Gates / Retries / Abstained, see
      `handbook/templates/session-log.md`) across the month's PRs; they are the part a
      program can count, so they say where to read closely before you read anything.

## Quarterly (Jan / Apr / Jul / Oct)

- [ ] **Tokens, sessions and devices.** Walk the spec 06 secrets inventory and rotate what is
      due, then review active sessions, devices and OAuth apps on GitHub and Cloudflare and
      revoke anything unrecognized the same day (spec 12 §2.1).

## Cut on 2026-11-03, and when each comes back

No box on these issues had been ticked since they began in July 2026, and most items had
nothing behind them. Add one back here when its condition holds:

- **SEV3 digest** (was weekly): both alert rules are dark, because Cloudflare cannot export
  custom metrics, so there is no digest to read. Back with the first alert that can fire.
- **Semgrep rules and vendored actions**: nothing is vendored, and Renovate bumps action pins.
- **Expired osv-ignores**: no repo has an ignore file. Back with the first one.
- **Restore test**: no project has a database. Back, quarterly, with the first D1 binding
  (steps in `backups/README.md`).
- **Stale sweep**: there are no feature flags, and merged branches now delete themselves.

## Why rituals, not reminders

An intention decays; a scheduled issue with a checklist does not. The flywheel rule —
"any mistake that annoys you twice becomes a rule" — only compounds if there is a
standing appointment to harvest the mistakes. That appointment is the monthly issue.
