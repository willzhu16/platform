# Runbook: <operation name>

> Copy this file into a project's `docs/runbooks/`. Replace the worked example below with
> yours. Rules: **Steps are copy-pasteable commands, not prose** ("run X", never "you
> should consider running X"). A runbook without a **Last tested** date is a rumor.

**Purpose** — one line: what this restores or changes, and when you reach for it.
**Preconditions** — access/tools/state assumed true before step 1.

## Steps

```bash
# numbered, literal, runnable top-to-bottom
```

## Verification

```bash
# the command that proves it worked, and the exact output to expect
```

## Rollback (of this runbook)

```bash
# how to undo the change this runbook made, if it goes wrong
```

**Last tested:** YYYY-MM-DD by <who>

---

# Runbook: roll back a Workers production deploy  ← worked example (executable as-is)

**Purpose** — revert production to the previous known-good version after a bad deploy.
**Preconditions** — `wrangler` authenticated (`wrangler whoami` succeeds); run from the
project root; you know the worker name (the `name` field in `wrangler.jsonc`).

## Steps

```bash
wrangler deployments list                 # find the id of the last known-good deploy
wrangler rollback --message "incident: revert to last good"   # prompts for the id
```

## Verification

```bash
curl -fsS https://<worker-name>.<subdomain>.workers.dev/healthz
# expect: HTTP 200 and {"version":"<the rolled-back-to tag>"}
```

## Rollback (of this runbook)

```bash
# a rollback is itself a deploy; to undo it, roll forward to the newer id the same way
wrangler deployments list && wrangler rollback
```

**Last tested:** 2026-07-07 by platform maintainer
