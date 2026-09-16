# Branch rulesets

`main.json` is the branch protection every generated repo gets. Apply it by hand, never
automatically — `adopt-project.sh` deliberately refuses to, because a repo with a workflow
that pushes straight to `main` starts failing the moment this lands.

```bash
gh api -X POST "repos/<owner>/<repo>/rulesets" --input rulesets/main.json
```

## What it requires, and why the names are exact

A required check is matched by **literal string**. A name that never reports does not fail —
it waits forever, and the pull request can never merge. That is why the job ids in the
caller workflows are a frozen contract (D-18): renaming one silently strands every repo.

| Context | Comes from |
|---|---|
| `ci / lint`, `ci / typecheck`, `ci / test`, `ci / commits` | the `ci` caller job |
| `security / gitleaks`, `security / semgrep`, `security / osv` | the `security` caller job |
| `codeql / analyze` | the `codeql` caller job (public repos) |
| `mutation` | the repo-local `mutation.yml` |
| `acceptance / acceptance` | the `acceptance` caller job (both templates) |

## One check deliberately left out

**`preview / deploy`** is a Cloudflare and network dependency, so it fails for reasons that
have nothing to do with the change under review.

## This file is for repos generated AFTER the checks existed

Every context here must already be reported by a workflow in the repo's default branch.
Applying this to an older repo generated before `mutation.yml` and `acceptance.yml` existed
locks it: the checks never report, so they never pass, and nothing can merge. Bring such a
repo up to date with a copier sweep first, confirm both workflows run on a pull request,
then apply the ruleset.

## Before adding a check here

The workflow that reports it must already be on the default branch of every repo this
ruleset is applied to. Requiring a check that a repo cannot run is how you lock a repo.
