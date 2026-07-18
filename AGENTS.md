<!-- Hand-written repo guide for non-Claude agents (Codex etc.). Safe to edit. -->

# Agent instructions — platform

**Read `CLAUDE.md` in this directory in full before doing anything.** Despite its name it
is the canonical, tool-agnostic repo guide (map, verification, gotchas, boundaries) — this
file is only a pointer plus the non-negotiables.

Non-negotiable rules (duplicated here in case you skip the pointer):

- Never push, tag, or create GitHub releases; never commit to `main` — feature branch + PR
  with conventional-commit messages (commitlint gates CI).
- Frozen contract (breaking to rename): consumer job ids `ci|security|release|preview|
  codeql|sync`, check names `ci / lint|typecheck|test|commits` and
  `security / gitleaks|semgrep|osv`, the `lint`/`typecheck`/`test` package-script contract,
  reusable-workflow input names, and plain `vX.Y.Z` release tags.
- Never run `scripts/new-project.sh` or `scripts/setup-machine.sh` as a test — they create
  real GitHub repos / mutate the machine.
- Workflows and templates have no local runner; `selftest.yml` on the PR is the gate, and
  it renders templates from git HEAD — commit template changes to test them. Fixture code
  is verified locally via each fixture's own `lint`/`typecheck`/`test` commands.
- Keep all text files LF (`.gitattributes` enforces it).
