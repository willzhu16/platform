# Cadences

The recurring maintenance that keeps the system from decaying. Implemented as scheduled
GitHub issues opened by [`platform/.github/workflows/cadence.yml`](../.github/workflows/cadence.yml)
— each issue body is its checklist below, so the ritual is unskippable, not remembered.
The workflow embeds a copy of these checklists (`CHECKLISTS`); edit both together.

## Weekly (Mondays)

- [ ] Review the **SEV3 digest** — anything recurring becomes a systemic fix (an issue).
- [ ] Merge the **Renovate batch** (the grouped non-major PR), once its checks are green.

## Monthly (1st)

- [ ] **`copier update` sweep** — pull template fixes into every active repo as diffs.
- [ ] **Semgrep rules + vendored actions review** — bump the vendored copies via PR.
- [ ] **Expired osv-ignores** — grep for lapsed suppression dates; re-triage or remove.
- [ ] **Session-log harvest** — read the month's agent session logs; convert recurring
      mistakes into a lint/CI rule (preferred, deterministic) or an instruction line
      (fallback). This is the athena flywheel (ARCHITECTURE §6.0 rule 5) made a ritual.

## Quarterly (Jan / Apr / Jul / Oct)

- [ ] **Token rotation + access review** — walk the spec 06 secrets inventory.
- [ ] **Session & device review** — review active sessions / devices / OAuth apps on GitHub
      + Cloudflare; revoke anything unrecognized same-day (spec 12 §2.1).
- [ ] **Restore test** — actually restore from backup (spec 08); an untested backup is a
      guess.
- [ ] **Stale sweep** — remove feature flags past 100% rollout and stale branches.

## Why rituals, not reminders

An intention decays; a scheduled issue with a checklist does not. The flywheel rule —
"any mistake that annoys you twice becomes a rule" — only compounds if there is a
standing appointment to harvest the mistakes. That appointment is the monthly issue.
