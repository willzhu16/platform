# platform

The CI, security, and scaffolding layer for Artemis projects. Nothing here is a service.
It publishes reusable GitHub Actions workflows that other repos call by URL, plus the
copier templates those repos are generated from.

**If you are an agent asked to start a new Artemis project, this file is the whole brief.
You do not need to read the rest of the repo.**

Its companion, [`willzhu16/athena`](https://github.com/willzhu16/athena), compiles the
agent instruction files (`CLAUDE.md`, `AGENTS.md`) that land inside each generated repo.

## Create a project

```bash
scripts/new-project.sh <name> \
  --template <cf-worker-app|py-tool> \
  --visibility <public|private> \
  [--description "one line"] \
  [--bindings kv,d1,r2,queues] \
  [--scheduled-jobs] \
  [--public-forms]
```

On Windows, `scripts/new-project.ps1` wraps this under WSL2. Linux is the canonical
environment.

`<name>` must be a lowercase slug matching `^[a-z][a-z0-9-]*$`. `--template` and
`--visibility` are required; everything else has a default. The script is idempotent, so
re-running it against an existing project is a no-op.

**Needs on PATH:** `gh` (authenticated), `copier`, `git`, `jq`, and either `pnpm`
(cf-worker-app) or `uv` (py-tool). `scripts/setup-machine.sh` installs them.

**This creates a real GitHub repository.** Do not run it to explore or to test something.

### The two templates

| Template | For | Ships with |
|---|---|---|
| `cf-worker-app` | A Cloudflare Worker | wrangler config, security headers, structured logging, `/healthz`, `/.well-known/security.txt`, Sentry wiring, vitest |
| `py-tool` | A Python CLI or library | uv, ruff, pyright, pytest, a console-script entry point |

`--bindings` applies only to `cf-worker-app`. Choosing `d1` also wires up a nightly
backup workflow. `--public-forms` adds a Turnstile widget and verify helper.

### What the script does, and what it cannot

Ten steps: preflight, render the template, generate the lockfile, `git init` and commit,
create the GitHub repo, apply the branch ruleset, create the `production` and `preview`
environments, enable Renovate, and compile the athena instruction files.

Three things stay manual and the script prints them at the end:

1. **Fill in `.athena/project.md` and the top of `THREAT.md`.** About ten minutes. This is
   the per-project context an agent cannot infer from the code, and it is the only
   instruction file in the repo you are allowed to edit by hand.
2. **Create a project-scoped Cloudflare API token** and add it as the environment secret
   `CLOUDFLARE_API_TOKEN` on `production` and `preview`. Deliberately not scripted.
3. **Add the deployed URL to uptime monitoring** once the first deploy exists.

## What a generated repo gets

Its CI is a handful of four-line files that call this repo's workflows at the moving `v1`
tag, so pipeline improvements arrive without touching the project:

```yaml
jobs:
  ci: # this job id is part of the check name — never rename it
    uses: willzhu16/platform/.github/workflows/ci.yml@v1
```

Every pull request runs seven required checks, eight on public repos:

| Check | Does |
|---|---|
| `ci / lint` `ci / typecheck` `ci / test` | Runs the project's own `lint`, `typecheck` and `test` scripts |
| `ci / commits` | Enforces Conventional Commits |
| `security / gitleaks` | Scans the diff for committed secrets |
| `security / semgrep` | Static analysis against shared rules |
| `security / osv` | Known vulnerabilities in locked dependencies |
| `codeql / analyze` | Deep data-flow analysis. Public repos only, because CodeQL is free only there |

Pull requests also get a preview deploy with a sticky comment carrying the URL. That check
is advisory and does not block a merge.

A branch ruleset requires those checks by exact name, forbids force-pushes and branch
deletion, and requires linear history.

## Rules for working in a generated repo

- **`lint`, `typecheck` and `test` are a contract.** The pipeline runs those three scripts
  and knows nothing else about the project. Swap tools freely; never rename the scripts.
- **Never rename a job id or check name.** They are referenced by literal string in every
  repo's ruleset. A rename means that repo can never merge again.
- **Never hand-edit `CLAUDE.md`, `AGENTS.md` or `.claude/settings.json`.** They are
  compiled output, stamped with `ATHENA-COMPILED`. Edit `.athena/project.md` for a rule
  that applies to this project, or an athena instruction layer for one that applies to
  every project, then recompile with `pnpm compile <repo>` from an athena checkout. A
  weekly job reverts hand-edits.
- **Conventional Commits decide the version.** `feat:` bumps the minor, `fix:` the patch,
  and anything else cuts no release at all. The message is an input, not a label.
- **Work on a branch named `agent/<tool>/<task-slug>`.** Never commit to `main`.
- **Merging to `main` deploys nothing.** release-please maintains a release pull request;
  merging that is the decision to ship. The tag then builds once and deploys that exact
  artifact.
- **Roll back** with `gh workflow run release.yml --ref vX.Y.Z -f tag=vX.Y.Z`. Same
  pipeline, earlier tag.

## Going deeper

- `CLAUDE.md` in this repo is the detailed map for agents working on platform itself.
- `handbook/` holds the process docs: definition of done, cadences, incident process,
  severity levels, log schema.
- `.github/workflows/*.yml` each open with a header comment explaining their contract.
  Read that header before changing one.
- `selftest.yml` gates every change to a workflow or template. There is no way to run
  these pipelines locally.
