# Runbook: respond to a leaked credential

**Purpose** — a credential has been committed, pushed, or printed somewhere it should not
have been. This gets it revoked, replaced, and confirmed dead, in the order that limits the
damage. Reach for it when `security / gitleaks` fails, when `history-scan.yml` reports a
finding, or when anyone notices a secret in a diff, a log, an issue or a screenshot.

**Preconditions** — `git` and `gh` authenticated (`gh auth status` succeeds); access to the
issuer of the credential (Cloudflare dashboard, GitHub settings, Bitwarden); `gitleaks`
installed if you want to rescan locally (`setup-machine.sh` installs it).

**Rotate before you clean up.** Deleting the value does not un-leak it, and the time spent
rewriting history is time the credential still works. If you only do one thing, do step 2.

## Step 1 — contain, without spreading it further

```bash
# Never paste the value into an issue, PR, chat, commit message or a scanner log.
# Every scan below uses --redact, which prints REDACTED in place of the match.
gitleaks detect --source . --config security/gitleaks.toml --redact --no-banner
```

A value pushed to a **public** repo is exposed the moment it lands. Public GitHub events are
streamed and scraped continuously, so "the branch was deleted a minute later" is not a
mitigation. Treat it as compromised and continue to step 2.

A value in a **private** repo is exposed to everyone with read access, every fork, and every
CI log the repo has produced. Usually less urgent, never zero.

## Step 2 — revoke or roll it at the issuer, first

Find the credential's type and do this before anything else.

| Credential | Where to revoke | Notes |
|---|---|---|
| Cloudflare API token | <https://dash.cloudflare.com/profile/api-tokens> → the token → Roll | Rolling changes the value and keeps the token's permissions and name |
| GitHub fine-grained PAT | <https://github.com/settings/tokens?type=beta> → the token → Delete | `AUTOMATION_TOKEN` is one of these; deleting it stops bot-opened PRs from getting checks until replaced |
| GitHub Actions secret | `gh secret set NAME --repo willzhu16/<repo>` | Overwrites in place; there is no "was it used" log, so also check recent workflow runs |
| Worker runtime secret | `wrangler secret put NAME` | Takes effect on the next deploy of that Worker |
| age private key | Generate a new one, then re-encrypt every file (below) | **Rotation does not protect what is already encrypted** — see the warning after this table |
| ntfy topic URL | Pick a new topic and update every publisher | The URL *is* the credential; there is no revoke |

Then confirm the old one is actually dead, rather than assuming the click worked:

```bash
# Cloudflare: the old token should now fail verification.
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer $OLD_TOKEN" \
  https://api.cloudflare.com/client/v4/user/tokens/verify
# expect: 401 (200 means it is still live — go back and roll it)
```

**The age key is the exception that catches people.** Every `secrets/*.env` in every repo is
encrypted *to a recipient*, so a leaked private key decrypts every file that was ever
encrypted to it, including the copies already in git history. Generating a new key protects
future files only. If the age key leaked, treat **every value in every sops file it can
open** as leaked too, and rotate those as well before re-encrypting:

```bash
# after rotating the underlying secrets and configuring the new recipient
sops updatekeys secrets/dev.env      # re-encrypt to the new recipient
```

## Step 3 — remove the value from the current source

```bash
# Replace the literal with a reference to the secret store, never with a blank you forget.
$EDITOR <the file>
git add -A && git commit -m "fix: replace leaked credential with a secret reference"
```

If the value was sitting unencrypted under `secrets/`, that directory is versioned, so it
went to the remote like anything else. Encrypt it properly before recommitting.

## Step 4 — decide about history, knowing what a rewrite does not fix

A rewrite is **optional and disruptive**. Rotation in step 2 is what makes the credential
worthless; this only removes the embarrassing copy. Do it when the value cannot be rotated
(a customer's data, a key held by a third party), and skip it when rotation was clean.

What it does not fix: forks, existing clones, anyone's local reflog, GitHub's cached views
of old commits (ask GitHub Support to purge those), and any CI log that printed the value.

```bash
pip install git-filter-repo          # not installed by setup-machine.sh
git filter-repo --invert-paths --path <the file>     # or --replace-text for one value
git push --force-with-lease origin main
```

Force-pushing `main` is blocked by the branch ruleset, so this needs the protection
temporarily lifted and put straight back. Coordinate it: everyone with a clone has to
re-clone, and a stale clone can push the value back.

## Verification

```bash
# 1. the value is gone from the working tree
gitleaks detect --source . --config security/gitleaks.toml --redact --no-banner --no-git
# expect: exit 0, "no leaks found"

# 2. and from history, IF you did step 4 (skip this line if you did not)
gitleaks detect --source . --config security/gitleaks.toml --redact --no-banner
# expect: exit 0. Exit 1 here after a rewrite means the rewrite missed a ref.

# 3. the replacement credential actually works
gh workflow run ci.yml --ref main && gh run watch
```

Step 2 of this verification is the one worth understanding: removing a value and committing
makes the **working tree** clean while history still holds it. Confirmed on 2026-09-26 with
gitleaks 8.30.1 on a scratch repo — `--no-git` returned exit 0 while the full scan still
returned exit 1 on the same checkout. A clean `--no-git` scan proves nothing about history.

## Rollback (of this runbook)

There is no rollback for a rotation, which is the point of doing it first. If the new
credential breaks a deployment, roll forward: issue another one and update the consumer. Do
not restore the old value.

```bash
gh run list --workflow release.yml --limit 5    # find what broke after the rotation
wrangler secret put NAME                        # set the replacement and redeploy
```

**Last tested:** 2026-09-26. Honestly scoped, because this runbook cannot be rehearsed end
to end without burning a real credential:

- **Tested** — the step 1 scan, the whole Verification block, and the working-tree-versus-
  history behaviour, against gitleaks 8.30.1 (the version `security.yml` pins) on a scratch
  repo with a fabricated Cloudflare-shaped token.
- **Not tested** — every revocation in step 2, and the `git filter-repo` rewrite in step 4.
  They need a real issuer and a force-push to a real repo. Reviewed, not proven; re-check
  the dashboard paths before relying on them under pressure.
