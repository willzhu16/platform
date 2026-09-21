# Sandbox profile

A permission profile asks an agent not to do something. This stops it.

`srt-settings.json` configures [`@anthropic-ai/sandbox-runtime`](https://github.com/anthropic-experimental/sandbox-runtime),
which wraps the whole Claude Code process in the OS isolation primitives (bubblewrap on
Linux and WSL2, Seatbelt on macOS). Inside it, a denied path is not merely unreadable, it is
**absent** — the process gets "No such file or directory", whatever command it runs and
however that command is spelled.

That difference is the point. `.claude/settings.json` denies `Bash(git push --force:*)`, and
`git push origin main --force` walks straight past it, because permission rules match command
text and text has many spellings. This boundary has none.

## Using it

```bash
npx @anthropic-ai/sandbox-runtime --settings security/sandbox/srt-settings.json claude
```

Linux and WSL2 need `bubblewrap` and `socat` installed; macOS needs nothing. Native Windows
is unsupported, so run it inside WSL2. Verify with:

```bash
bash scripts/sandbox-check.sh
```

That validates the profile's claims and, where bubblewrap is present, proves the isolation
actually holds rather than describing it. It runs in CI via `scripts/tests.sh`.

## What it protects

- **The agent cannot rewrite its own supervision.** `.claude/hooks`, `.claude/settings.json`,
  `.claude/commands`, `.claude/skills`, `.mcp.json`, `.git/hooks` and `.git/config` are all
  deny-write. `doctor` reports such an edit as drift *after the fact*; here it cannot happen.
  This matters more than it sounds: the sandbox-runtime docs single these out because a
  session that can write them persists hooks or permission rules that run **unsandboxed** on
  the next launch, turning one bad turn into a permanent foothold.
- **Secrets are denied for reading as well as writing.** `secrets/`, `.env`, `~/.ssh`,
  `~/.aws`, `~/.gnupg`. Write-only protection would still let a value reach the model, which
  is the exact failure athena's 10-security layer is written to prevent.
- **Network is deny-by-default.** An omitted `allowedDomains` means no network at all, so the
  list here is the complete set a session needs: the model API, GitHub, and the package
  registries. Anything else is unreachable, including a URL an agent was talked into fetching.

## What it does not protect

Worth stating plainly, because a boundary people overestimate is worse than one they know
the shape of.

- **Nothing inside the project directory.** The agent can write the whole repo, which is the
  job. The sandbox stops it escaping, not making a mess at home.
- **Exfiltration through an allowed domain.** GitHub is reachable, so anything readable can
  in principle leave through it. Deny-by-default narrows the exits; it does not seal them.
- **Anything the profile is not pointed at.** Launch Claude Code without the runtime and none
  of this applies. There is no enforcement that it was used.
- **The model's own judgement.** Isolation limits blast radius. It does not make a bad change
  good, and every gate in `ci.yml` still has to pass.

On Linux and WSL2 the runtime builds its deny list once at launch, so directories the session
creates afterwards — `git clone`, scaffolding — are not covered. Review what the session
created before trusting the boundary held over a long run.
