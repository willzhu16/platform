# platform security

The shared security pipeline every Artemis repo runs on every PR (spec 02). All three
gates run **unauthenticated** — no repo secrets are required, so the workflow is callable
from public and private repos alike.

## What runs where

| Check | Tool | Where | Fails when |
|---|---|---|---|
| `security / gitleaks` | gitleaks (pinned binary, checksum-verified) | every PR + push to main | a secret pattern is found (PR = diff range, push = Git history) |
| `security / semgrep` | Semgrep OSS engine | every PR | code matches a rule in `semgrep/` (or a project's extra `--config`) |
| `security / osv` | osv-scanner | every PR | a locked dependency has a known OSV advisory |
| `codeql / analyze` | CodeQL | **public** repos only | data-flow analysis finds a vulnerability |

Workflows: [`security.yml`](../.github/workflows/security.yml) (the three gates),
[`codeql.yml`](../.github/workflows/codeql.yml) (public-only),
[`history-scan.yml`](../.github/workflows/history-scan.yml) (manual full-history onboarding scan).

## Consumer snippet (baked into templates by spec 03)

```yaml
jobs:
  security: # job id MUST be `security` — it prefixes the check names
    uses: <owner>/platform/.github/workflows/security.yml@v1
```

Public repos additionally call `codeql.yml` from a `codeql` job that grants
`security-events: write`.

## Suppressing findings (all greppable and reviewable)

- **gitleaks**: add a `# gitleaks:allow` comment on the offending line, or an entry to a
  repo-root `.gitleaksignore`. Only for confirmed false positives — a real secret is
  rotated, never ignored.
- **semgrep**: add `# nosemgrep: <rule-id>` on the line. The AI review pass (spec 10) is
  instructed to challenge every newly added suppression.
- **osv**: add the advisory ID to a repo-root `osv-scanner.toml` **with an expiry date and
  a justifying comment**. The monthly cadence (spec 05) greps for expired ignores.

## The shared rules

- `gitleaks.toml` — the gitleaks default ruleset plus custom rules for the credential
  shapes this environment issues (Cloudflare API tokens, age private keys, GitHub
  fine-grained PATs, ntfy topic URLs).
- `semgrep/` — one directory per rule pack. **Current status: a curated starter set**
  (command-injection and dynamic-eval rules for JS/TS and Python) that covers the
  highest-value patterns. Vendoring the full registry packs (p/default, p/secrets, the
  OWASP packs, p/github-actions) as pinned local copies is a tracked follow-up — it needs
  a vendoring script and the Semgrep CLI, and lands rule updates as reviewable PRs.

Rules are vendored (not fetched from the registry at runtime) so the supply chain is
pinned and every rule change is a reviewable diff.

## When a gate fires

A potential secret finding blocks publication until it is investigated. Do not paste the
value into an issue, PR, chat, or scanner log — every scan command uses `--redact`.

**Follow [`handbook/runbooks/leak-response.md`](../handbook/runbooks/leak-response.md).**
It has the per-issuer revocation steps, the commands, and what a history rewrite does and
does not fix. The shape of it:

1. **Rotate at the issuer first.** Deleting the value does not un-leak it, and cleanup time
   is time the credential still works.
2. Replace the literal in the source with a secret-store reference.
3. A history rewrite is optional and disruptive; rotation is what makes the value
   worthless. It also does not reach forks, existing clones, or cached views.
4. Rescan and confirm — note that a clean working-tree scan (`--no-git`) proves nothing
   about history, which the runbook demonstrates.

The Semgrep fixtures deliberately contain vulnerable examples for scanner regression
coverage. They are not application code and must never be executed or copied into projects.
