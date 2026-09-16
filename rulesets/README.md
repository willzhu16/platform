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

## Two checks deliberately left out

**`acceptance / acceptance`** works only for TypeScript repos today. The reusable workflow
runs the consumer's `test` script and reads a vitest JSON report; `py-tool` produces neither.
Add it per-repo for a TS project once that repo is writing packets with criterion ids:

```bash
gh api -X PUT "repos/<owner>/<repo>/rulesets/<id>" --input <(...)   # add {"context": "acceptance / acceptance"}
```

**`preview / deploy`** is a Cloudflare and network dependency, so it fails for reasons that
have nothing to do with the change under review.

## Before adding a check here

The workflow that reports it must already be on the default branch of every repo this
ruleset is applied to. Requiring a check that a repo cannot run is how you lock a repo.
