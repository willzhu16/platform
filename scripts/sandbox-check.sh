#!/usr/bin/env bash
# Validate the sandbox profile, and — where the kernel primitive is available — prove the
# isolation it describes actually holds.
#
#   bash scripts/sandbox-check.sh [path/to/srt-settings.json]
#
# Why a check and not just a file: a permission profile is a list of claims, and a claim that
# quietly stops being true reads exactly like one that holds. `.claude/settings.json` has the
# same problem, which is what athena's coherence manifest exists for. This is that idea
# applied to the sandbox: the profile says an agent cannot write its own hooks or read
# secrets, and this asserts both rather than trusting the file to stay correct.
#
# The distinction worth keeping straight: permission rules are matched against command text
# and are evadable by spelling (REVIEW-2026-07-15 #7). This is a kernel boundary. A denied
# path is not unreadable, it is *absent* — which is why the probe below checks for "No such
# file" rather than for a permission error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${1:-$(dirname "$SCRIPT_DIR")/security/sandbox/srt-settings.json}"
problems=0

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  problems=$((problems + 1))
}

ok() { printf 'ok    %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { echo 'FATAL: this check needs node' >&2; exit 1; }
[ -f "$PROFILE" ] || { echo "FATAL: no profile at $PROFILE" >&2; exit 1; }

# Read a JSON array as newline-separated values. Node rather than jq: node is already required
# by every repo this profile protects, and jq is not installed on the author's machine.
read_list() { # $1=dotted path
  node -e '
    const fs = require("node:fs");
    const profile = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const value = process.argv[2].split(".").reduce((acc, key) => acc?.[key], profile);
    if (Array.isArray(value)) process.stdout.write(value.join("\n"));
  ' "$PROFILE" "$1"
}

has() { # $1=needle $2=list
  printf '%s\n' "$2" | grep -qxF "$1"
}

node -e 'JSON.parse(require("node:fs").readFileSync(process.argv[1],"utf8"))' "$PROFILE" 2>/dev/null \
  && ok 'profile is valid JSON' \
  || { fail 'profile is not valid JSON'; exit 1; }

allow_write="$(read_list filesystem.allowWrite)"
deny_write="$(read_list filesystem.denyWrite)"
deny_read="$(read_list filesystem.denyRead)"
domains="$(read_list network.allowedDomains)"

# The agent must not be able to rewrite its own supervision. doctor reports such an edit as
# drift after the fact; here it cannot happen. These are also the paths the sandbox-runtime
# docs single out: a session that can write them persists hooks or permission rules that run
# UNSANDBOXED on the next launch, which turns one bad turn into a permanent foothold.
for path in .claude/hooks .claude/settings.json .claude/commands .claude/skills .mcp.json \
            .git/hooks .git/config '~/.claude/settings.json' '~/.bashrc'; do
  if has "$path" "$deny_write"; then
    ok "write denied: $path"
  else
    fail "the agent could rewrite its own supervision: $path is not in denyWrite"
  fi
done

# Secrets are denied for BOTH read and write. Write-only protection would still let a value
# reach the model, which is the failure 10-security is written to prevent.
for path in secrets .env; do
  has "$path" "$deny_write" && ok "write denied: $path" || fail "$path is not in denyWrite"
  has "$path" "$deny_read" && ok "read denied: $path" || fail "$path is not in denyRead"
done
for path in '~/.ssh' '~/.aws'; do
  has "$path" "$deny_read" && ok "read denied: $path" || fail "$path is not in denyRead"
done

# A single over-broad grant silently undoes every deny above it.
for path in / '~' '~/' /home /etc ..; do
  if has "$path" "$allow_write"; then
    fail "allowWrite contains $path, which defeats the profile"
  fi
done
ok 'no over-broad write grant'

# An empty allowlist means no network at all, which looks like a strict profile and is really
# a broken one: Claude Code cannot reach its own API and the session fails to start.
if has 'api.anthropic.com' "$domains"; then
  ok 'the model API is reachable'
else
  fail 'allowedDomains omits api.anthropic.com, so a session cannot start'
fi

# The profile describes a kernel boundary. Where that kernel is present, prove it rather than
# describing it. Skipped, never failed, where bubblewrap is absent — a check that cannot run
# has proved nothing, and failing here would just mean "wrong operating system".
if command -v bwrap >/dev/null 2>&1; then
  probe="$(mktemp -d)"
  outside="$(mktemp)"
  printf 'sensitive\n' > "$outside"
  if bwrap --ro-bind /usr /usr --ro-bind /bin /bin --ro-bind /lib /lib \
       --bind "$probe" "$probe" --dev /dev --unshare-all \
       -- /bin/cat "$outside" >/dev/null 2>&1; then
    fail 'bubblewrap did not isolate: a path outside the sandbox was still readable'
  else
    ok 'bubblewrap isolates: a path outside the sandbox is absent, not merely unreadable'
  fi
  rm -rf "$probe" "$outside"
else
  ok 'bubblewrap absent, kernel probe skipped (Linux/WSL2 only)'
fi

if [ "$problems" -eq 0 ]; then
  printf '\nsandbox profile OK\n'
else
  printf '\n%d problem(s)\n' "$problems" >&2
  exit 1
fi
