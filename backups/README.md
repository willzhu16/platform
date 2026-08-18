# Backups

Retention policy for the per-project D1 backup buckets (spec 08 §4b). Applied by the
reusable `backup-d1.yml` workflow on every run, so a bucket edited by hand converges
back to this file the next night.

## Why the policy lives here and not in the workflow

`r2-lifecycle.json` is enforced by R2 itself, not by code we wrote. The nightly job
only ever *writes* objects — it never deletes. That is deliberate: a retention bug in
an unattended nightly job destroys the backups it exists to protect, and date
arithmetic that decides what to delete is exactly the kind of code that fails silently
until the day you need a restore.

Keeping the policy in git rather than only in bucket config preserves the part that
matters for review: retention changes show up as diffs.

## The policy

| Prefix | Kept for | Effect |
|---|---|---|
| `daily/` | 30 days | ~30 rolling nightly exports |
| `monthly/` | 190 days | ~6 monthly exports (written on the 1st) |

190 rather than 180 so a 31-day month never expires the sixth copy early.

Monthly copies are written as a **second copy** on the 1st, not promoted from `daily/`.
Nothing has to move an object later, so there is no second job to get wrong.

## Restoring

A backup that has not been restored is a rumor. To restore, download the dump and
replay it into a scratch database, then run the project's smoke test against it:

```sh
wrangler r2 object get backups-<project>/daily/<project>-<YYYY-MM-DD>.sql \
  --file restore.sql --remote
wrangler d1 create <project>-restore-check
wrangler d1 execute <project>-restore-check --remote --file restore.sql
```

The quarterly cadence issue carries this as a checklist item.

## Recovery point objective

24 hours, at solo scale. Stated so it reads as a decision rather than an accident.
Projects with real users should revisit it per project.
