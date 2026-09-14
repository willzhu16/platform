# Adopting an existing repo

`new-project.sh` builds a repo from a template. That is the only adoption path Artemis had,
and it is useless for a repo that already has history. `scripts/adopt-project.sh` is the
other direction: it takes a repo that already exists and adds Artemis to it a piece at a
time.

```bash
scripts/adopt-project.sh ../some-repo                      # report only, writes nothing
scripts/adopt-project.sh ../some-repo --with security
scripts/adopt-project.sh ../some-repo --with security,instructions --stack ts
```

It writes files and stops. It never commits, never pushes, never creates a repo and never
applies a ruleset, so a bad run is undone with `git checkout`.

## Run the preflight first

With no `--with` it only reports, and that report is the point. The failure mode of a
retrofit is not a broken file, it is adopting a piece that quietly conflicts with how the
repo already works.

It distinguishes two severities deliberately:

- **warn** is about something that would happen *later*, if you took a further step. It
  never stops a write.
- **BLOCK** is about something this script is about to break itself. It refuses to write.

Existing requested workflows and `.athena/config.json` block all writes unless you pass
`--force`. Review the current config before replacing it: replacement resets its stack,
tools and permission tier to the requested defaults. Unknown pieces are rejected before
any files are written. Linked Git worktrees are supported as well as ordinary checkouts.

The warning that matters most: **a workflow that pushes directly to the default branch.**
The Artemis main ruleset requires pull requests and linear history, so applying it would
start rejecting that job. This is not hypothetical. `launch-start` refreshes a data
snapshot every night with `git push` straight to `main`; adopting the ruleset there would
have broken a job that had run daily for months.

## The pieces, and which to take

| Piece | Adds | Take it when |
|---|---|---|
| `security` | `security.yml` calling the shared gitleaks + semgrep + osv pipeline | Almost always. It is secretless, language-agnostic, needs no ruleset, and conflicts with nothing. |
| `ci` | `ci.yml` calling the shared TS pipeline | The repo has no CI of its own, and exposes `lint`, `typecheck` and `test`. |
| `codeql` | `codeql.yml` calling the shared analysis | Public repos without their own code scanning. |
| `instructions` | `.athena/config.json`, so athena can compile the repo | Agents actually work in this repo. |

**`security` is the piece with no strings attached.** It takes no secrets, so it is
identical for public and private repos, and a finding fails a check rather than breaking a
deploy.

**`ci` and `codeql` pin the repo to the moving `@v1` tag.** That is the whole benefit and
the whole cost: a platform release reaches the repo on its next run, with no staged rollout
and no opt-out. Worth it for a repo that has no pipeline. Not obviously worth it for one
that already has a working pipeline, where adopting is a lateral move that buys a
cross-repo dependency.

**`instructions` is standalone.** It needs no workflow and no platform dependency. After
writing the config, run `pnpm compile <repo-dir>` from the athena repo to produce
`CLAUDE.md` and `.claude/`. Pick `--targets ''` unless the repo really is a Worker or a
VS Code extension: an empty target list is valid, and no target layer is better than a
wrong one. Handing an agent the Workers layer for a static site is worse than handing it
nothing.

## What the script does not do

- **Apply the branch ruleset.** Do that by hand, and only once nothing pushes to the
  default branch directly. `rulesets/main.json` is the file.
- **Commit or push.** Review the diff, branch, and open a pull request like any other change.
- **Fix the script contract.** If `lint`, `typecheck` or `test` is missing, add it yourself;
  the reusable CI calls those three names and nothing else.

## Worked example

`launch-start` is a public Astro site with its own CI, its own deploy, and a nightly job
pushing to `main`. The preflight warned about that job, noted its existing `ci.yml`, and
confirmed the script contract was already satisfied. The answer was one piece:

```bash
scripts/adopt-project.sh ../launch-start --with security
```

No ruleset, no CI, no `@v1` pin on its build. The nightly job kept working.
