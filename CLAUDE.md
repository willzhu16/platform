<!-- Hand-written repo guide. Safe to edit. Part of the Artemis workspace — see the parent
     directory's CLAUDE.md / PROJECT-GUIDE.md for workspace-level rules if present. -->

# platform — shared CI, templates, and org tooling

This repo IS the product: reusable GitHub Actions workflows, copier project templates,
shared security rules, an ops handbook, and machine/project bootstrap scripts. Downstream
repos (including its sibling `athena` and every generated project) consume the workflows
pinned at the moving major tag `@v1`. There is **no package.json at the repo root** and no
service to run; the deploy target is GitHub itself.

## Map

- `.github/workflows/` — the core product. Reusable (have `workflow_call`):
  - `ci.yml` — TS/JS gate; runs the target's `lint`/`typecheck`/`test` package scripts +
    commitlint. Emits frozen check names `ci / lint|typecheck|test|commits`.
  - `ci-python.yml` — Python mirror (uv + ruff + pyright + pytest); emits the SAME frozen
    `ci / *` names so rulesets don't care about language.
  - `security.yml` — gitleaks + semgrep + osv, secretless, language-agnostic; fetches
    shared config from platform via `job.workflow_repository`/`job.workflow_sha` (contexts
    actionlint 1.7.7 doesn't know — suppressed in `.github/actionlint.yml`, don't "fix").
  - `athena-sync.yml` — weekly drift sync: checks out `<owner>/athena@v1`, recompiles the
    caller's instruction files, opens/updates one `chore/athena-sync` PR on drift.
  - `release.yml` — tag-driven build+optional Cloudflare deploy (`release / build|deploy`);
    `preview.yml` — per-PR `wrangler versions upload` + sticky comment (`preview / deploy`).
  - `codeql.yml` — single `analyze` job (deliberately not a matrix; keeps the frozen
    `codeql / analyze` name). Templates wire it only for public repos.
  - Repo-local: `selftest.yml` (runs on every PR with a `selftest-complete` aggregate gate —
    actionlint + shellcheck +
    runs ci/ci-python against the fixtures + copier-renders both templates and runs their
    gates), `release-platform.yml` (release-please), `update-major-tag.yml` (force-moves
    `v1` onto a published `vX.Y.Z`; regex-guarded), `cadence.yml` (scheduled maintenance
    issues; checklist text duplicated from `handbook/cadences.md` — keep in sync),
    `history-scan.yml` (manual full-history gitleaks; hardcodes `<owner>/platform`).
- `copier.yml` — the single question set for all templates (template, project_name,
  description, visibility, and cf-worker-only: bindings multiselect, needs_scheduled_jobs,
  public_forms). `_templates_suffix: .jinja`.
- `templates/cf-worker-app/`, `templates/py-tool/` — `.jinja` suffix = rendered; no suffix
  = copied verbatim; conditional filenames use `{% if … %}` in the filename itself (codeql,
  LICENSE, turnstile files). Generated workflows pin `@v1` and use the frozen job ids.
- `selftest-fixture/` (TS) and `selftest-fixture-py/` — minimal real packages the reusable
  CI is tested against. Same script contract as athena (`lint`/`typecheck`/`test`).
- `scripts/` — `new-project.sh` (creates REAL GitHub repos — never run as a test),
  `adopt-project.sh` (the retrofit path for a repo that ALREADY exists: à la carte,
  report-only by default, writes files and never commits/pushes/applies a ruleset — see
  `handbook/adopting-an-existing-repo.md`),
  `setup-machine.sh` (mutates the machine), `new-project.ps1` (thin WSL wrapper; D-20
  bash-first). Their pure string-building logic lives in `lib.sh`, regression-tested by
  `tests.sh` (`bash scripts/tests.sh`; needs jq + python3/PyYAML — safe to run, touches
  nothing). Shellcheck + the tests are gated by selftest.
- `security/` — `gitleaks.toml` (default rules + age key / GitHub PAT / CF token / ntfy
  custom rules) and the semgrep rules (`artemis-js/`, `artemis-python/`): 10 rules over
  `command-injection` + `workers` (D1 query interpolation, logging the whole `env`,
  `Math.random` for a secret) and `command-injection` + `unsafe-input` (unsafe `yaml.load`,
  `pickle.load`, `verify=False`). **These are the ONLY rules the fleet runs.**
  `security.yml`'s `semgrep-config` input defaults to empty, so no registry pack
  (`p/default`, `p/security-audit`) runs anywhere — breadth would be a decision about
  vendoring versus fetching at scan time, and the monthly cadence assumes vendoring.
  Every rule needs an annotated `ruleid:`/`ok:` fixture beside it, and both halves matter:
  a rule with no fixture is untested, and a fixture with no `ok:` lines never proves the
  rule stays off legitimate code. Run them locally with
  `wsl uvx semgrep==1.168.0 --test --metrics=off security/semgrep` (~7 s, no install).
- `handbook/` — cadences, definition-of-done, incident process, severity levels, frozen
  log schema, and doc templates (ADR, postmortem, runbook, session-log).
- `rulesets/main.json` — branch ruleset applied to new repos; hardcodes the 7 required
  check names by literal string.
- `renovate/default.json` — shared preset; isolates platform major bumps into their own PR.

## Verification (no local runner for workflows)

- Fixtures: `cd selftest-fixture && pnpm typecheck && pnpm lint && pnpm test`;
  `cd selftest-fixture-py && uv run ruff check . && uv run pyright && uv run pytest -q`.
  Or run the workspace `..\check.ps1`, which covers both.
- Workflows/templates/scripts: the real gate is `selftest.yml` on the PR. **selftest
  renders templates from git HEAD (`--vcs-ref HEAD`), not the working tree** — uncommitted
  template edits are invisible to it; commit first.
- Validate workflow YAML by eye against each file's header comment; those headers document
  intent and are kept current.

## Gotchas (verified 2026-07-11)

- **Frozen contract (D-18, breaking to rename):** consumer job ids (`ci`, `security`,
  `release`, `preview`, `codeql`, `sync`), the check names in `rulesets/main.json`, the
  `lint`/`typecheck`/`test` script contract, reusable-workflow input names, and plain
  `vX.Y.Z` tags (the moving `v1` depends on the shape).
- Optional `AUTOMATION_TOKEN` (PAT/App token) makes bot-created PRs trigger CI. Without
  it, GITHUB_TOKEN suppression still requires a human close/reopen. Release workflows
  explicitly dispatch the next workflow; do not simplify those dispatches away.
- release-please owns versioning (`.release-please-manifest.json`); the stray
  `platform-v1.1.0` tag is a harmless artifact of an old config — ignore it.
- Templates ship no lockfiles by design; `new-project.sh` generates them (CI installs are
  `--frozen`, so a missing lockfile means a red first PR).
- `.sops.yaml` has a placeholder recipient: configure a project-specific age public key
  before encrypting anything. Leak response is documented in `security/README.md`.
- Each template contains its own thin `security.yml` *caller* — don't confuse those with
  the reusable `security.yml` at this repo's root.
- **Both templates gate on more than coverage now.** `cf-worker-app` ships
  `stryker.config.json` and a repo-local `mutation.yml`; both selftest render jobs run
  `pnpm run test:mutation`, so a template test that stops catching things fails platform's
  own PR gate. Floors are measured, not guessed: re-measure by rendering and running,
  never by editing the number. **`py-tool` gates on mutation too** (mutmut +
  `scripts/mutation.py`, floor 80): its pytest `addopts` is deliberately free of `--cov`,
  because pytest-cov's collection fights mutmut's tracer and mutation testing cannot run at
  all with it there. Coverage still gates — `ci-python.yml` runs `pytest --cov` and the floor
  lives in `[tool.coverage.report]`. Do not move `--cov` back into addopts.
- **`cf-worker-app` ships a smoke script** (`scripts/smoke.sh`) that checks a *deployed*
  Worker: /healthz, the five security headers on two paths, and a live unexpired
  security.txt. `preview.yml` and `release.yml` run it when the repo has one
  (`if: hashFiles(...)`), so adopting it is opt-in per repo and existing repos are
  unaffected. It is tested in `scripts/tests.sh` against a stand-in server that can serve
  each contract wrongly — a smoke check that only ever passes is worse than none.
- **Diff coverage runs inside `ci / test`**, in both `ci.yml` and `ci-python.yml`. It needs
  a cobertura report (`coverage/cobertura-coverage.xml` for vitest, `coverage.xml` for
  pytest) and compares against the PR's base branch; a repo emitting neither skips it with a
  notice. Deliberately not its own check name: inside `ci / test` it is already required
  everywhere, with no ruleset edit and no way to opt out by omission. The `test` job now
  checks out with `fetch-depth: 0` because a shallow clone has no merge base to diff from.
- **`acceptance.yml` (reusable) gates criteria against tests.** It resolves the packet from
  the issue the PR closes, runs the consumer's `test` script, and hands both to athena's
  `acceptance` CLI. Advisory when no packet is linked; `require-packet: true` makes it
  mandatory.
- **`cf-worker-app` also ships property tests** (`tests/properties.test.ts`, fast-check).
  The seed is pinned on purpose: a moving score cannot sit under a ratcheted floor, and
  an unreproducible failure is worse than no test. Two generators are bounded with the
  reason written beside them — null-body statuses, and dates near the maximum Date — so
  neither reads as an unexplained exception.
- `.gitattributes` forces LF; keep it that way (athena's doctor is byte-exact downstream).

## Boundaries

- Never push, tag, or create releases; never commit to `main` — feature branch + PR,
  conventional commits (commitlint gates CI).
- Never run `scripts/new-project.sh` or `setup-machine.sh` casually — they create real
  GitHub repos / mutate the machine.
- Don't rename anything in the frozen contract above; don't edit lockfiles by hand.
