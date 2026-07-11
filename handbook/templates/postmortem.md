# Postmortem: <incident title>

Blameless. The system failed, not a person. Written within 48h of resolution (see
[incident-process.md](../incident-process.md)).

- **Date:** YYYY-MM-DD  · **Severity:** SEV1 | SEV2 | SEV3  · **Author:** <who>
- **Duration:** <detect → resolve>

## Impact

Who/what was affected and for how long, in concrete terms (users, requests, data). If you
can quantify it, do.

## Timeline (UTC)

| Time | Event |
|---|---|
| HH:MM | detected — <how> |
| HH:MM | declared — <severity> |
| HH:MM | mitigated — <action> |
| HH:MM | resolved |

## Root cause

The actual mechanism, followed to the point where a change would have prevented it. Not
"a bug" — *which* bug, and why it was reachable.

## Detection gap

Why didn't we know sooner? What signal was missing or ignored? (This is where the next
alert comes from.)

## Systemic fix (exactly one)

The single highest-leverage change that makes this class of incident impossible or
loud — filed as an issue: <link>. A lint rule, an alert, or a runbook step, **not** a
resolution to be careful. Additional gaps become normal follow-up issues, not fixes.
