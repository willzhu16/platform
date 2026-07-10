# Incident process

Five steps. The order matters more than the paperwork — **mitigate before you diagnose**.

1. **Detect** — an alert fired, or you noticed something. Either counts.
2. **Declare** — say it out loud in the project's incident issue, with a timestamp and a
   [severity](severity-levels.md). Declaring a false alarm costs nothing; a silent
   incident costs trust. One issue per incident is the source of truth.
3. **Mitigate first** — stop the bleeding. Reach for the
   [rollback runbook](templates/runbook.md) by default. Fixing forward is a deliberate
   choice made with a clear head, not a reflex under pressure.
4. **Resolve** — service restored to normal; confirm with the same signal that detected
   the problem (the alert clears, the metric recovers), not by assumption.
5. **Postmortem within 48h** — use [templates/postmortem.md](templates/postmortem.md):
   timeline · impact · root cause · **detection gap** (why didn't we know sooner?) ·
   exactly **one** systemic fix.

## The one-systemic-fix rule

Every postmortem ends with exactly one systemic fix, filed as a `platform`/template issue
— **systemic fixes become code, not vows.** "Be more careful next time" is not a fix;
a new lint rule, a new alert, or a runbook step is. One fix, actually shipped, beats five
resolutions that decay by Friday. If the incident revealed two real gaps, file the second
as a normal issue and pick the highest-leverage one as *the* fix.

## Blamelessness

The system failed, not a person. The postmortem asks what made the mistake easy to make
and hard to catch — those are the fixable surfaces.
