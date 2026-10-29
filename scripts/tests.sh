#!/usr/bin/env bash
# Regression tests for scripts/lib.sh plus one workflow invariant.
#
#   bash scripts/tests.sh
#
# Needs bash, git, jq and python3 with PyYAML — nothing else. new-project.sh and
# setup-machine.sh are never executed here (they create real GitHub repos and mutate the
# machine), which is exactly why their pure logic lives in lib.sh. The adoption CLI is
# exercised only against disposable local repos. Gated by selftest.yml.
#
# Deliberately NOT `set -e`: a failing assertion must be reported and the run continue, so
# one pass shows everything that is broken.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

# Hard requirement, checked up front: every YAML assertion parses with PyYAML under
# `2>/dev/null`. Without this guard a missing PyYAML makes parse_answers print nothing,
# and the workflow-invariant check (which expects empty output) would pass vacuously.
python3 -c 'import yaml' 2>/dev/null \
  || { echo 'FATAL: these tests need python3 with PyYAML' >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
passed=0 failed=0

check() { # $1=name $2=expected $3=actual
  if [ "$2" = "$3" ]; then
    printf '  ok    %s\n' "$1"
    passed=$((passed + 1))
  else
    printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' "$1" "$2" "$3"
    failed=$((failed + 1))
  fi
}

# Parse an answers file and print "k=v|k=v" sorted by key. Prints nothing if the YAML is
# invalid, which is itself the assertion for the ": " and newline cases below.
parse_answers() {
  python3 - "$1" <<'PY' 2>/dev/null
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print("|".join(f"{k}={d[k]!r}" for k in sorted(d)))
PY
}

echo '== build_answers_file (new-project.sh)'

# Regression: `echo "description: ${DESCRIPTION}"` made this an invalid YAML plain scalar,
# so copier failed on a perfectly reasonable --description.
TEMPLATE='py-tool' NAME='my-tool' VISIBILITY='private' DESCRIPTION='CLI: does X' \
  BINDINGS='' SCHEDULED='false' PUBLIC_FORMS='false'
build_answers_file > "$TMP/colon.yml"
check 'a description containing ": " stays one valid scalar' \
  "description='CLI: does X'|project_name='my-tool'|template='py-tool'|visibility='private'" \
  "$(parse_answers "$TMP/colon.yml")"

# Regression: a newline let the description inject a second answer key. YAML is
# last-key-wins, so an injected `template:` (emitted after the real one) would win.
TEMPLATE='py-tool' NAME='my-tool' VISIBILITY='private' \
  DESCRIPTION="$(printf 'safe desc\ntemplate: EVIL')" \
  BINDINGS='' SCHEDULED='false' PUBLIC_FORMS='false'
build_answers_file > "$TMP/inject.yml"
check 'a newline in the description cannot inject an answer key' \
  "py-tool" \
  "$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["template"])' "$TMP/inject.yml" 2>/dev/null)"

TEMPLATE='cf-worker-app' NAME='my-app' VISIBILITY='public' DESCRIPTION='An app.' \
  BINDINGS='KV,R2' SCHEDULED='true' PUBLIC_FORMS='false'
build_answers_file > "$TMP/bindings.yml"
check 'bindings render as a YAML list' \
  "['KV', 'R2']" \
  "$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["bindings"])' "$TMP/bindings.yml" 2>/dev/null)"

TEMPLATE='cf-worker-app' NAME='my-app' VISIBILITY='public' DESCRIPTION='An app.' \
  BINDINGS='' SCHEDULED='false' PUBLIC_FORMS='false'
build_answers_file > "$TMP/empty-bindings.yml"
check 'empty bindings render as an empty list' \
  "[]" \
  "$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["bindings"])' "$TMP/empty-bindings.yml" 2>/dev/null)"

TEMPLATE='py-tool' NAME='my-tool' VISIBILITY='private' DESCRIPTION='A tool.' \
  BINDINGS='' SCHEDULED='false' PUBLIC_FORMS='false'
build_answers_file > "$TMP/py.yml"
check 'py-tool omits the cf-worker-only answers' \
  "description|project_name|template|visibility" \
  "$(python3 -c 'import sys,yaml; print("|".join(sorted(yaml.safe_load(open(sys.argv[1])))))' "$TMP/py.yml" 2>/dev/null)"

echo '== tool_version (setup-machine.sh)'

printf '#!/bin/sh\necho "no dotted version here"\n' > "$TMP/noversion"
printf '#!/bin/sh\necho "faketool version 2.31.7 (linux)"\n' > "$TMP/withversion"
chmod +x "$TMP/noversion" "$TMP/withversion"
PATH="$TMP:$PATH"

# Regression: this was a bare assignment, so under `set -euo pipefail` a tool printing no
# dotted version made grep exit 1 and killed the whole self-check table mid-render.
check 'a tool with no dotted version does not abort the caller under set -e' \
  'REACHED:' \
  "$(set -euo pipefail; v="$(tool_version noversion)"; printf 'REACHED:%s' "$v")"

check 'a dotted version is extracted' \
  '2.31.7' \
  "$(tool_version withversion)"

# Regression: new-project.sh recorded `_commit: v1` in every generated repo, so
# `copier update` compared the template against itself and applied nothing.
check 'newest_release_tag picks the highest concrete release' \
  'v1.10.0' \
  "$(printf 'v1.7.0\nv1\nv1.10.0\nplatform-v1.1.0\nv1.9.0\n' | newest_release_tag)"

check 'newest_release_tag rejects moving major tags' \
  '' \
  "$(printf 'v1\nv2\n' | newest_release_tag)"

check 'newest_release_tag survives an empty tag list under pipefail' \
  'REACHED:' \
  "$(set -euo pipefail; t="$(printf '' | newest_release_tag)"; printf 'REACHED:%s' "$t")"

echo '== workflow invariants'

# Property, not instance: athena-sync.yml shipped without a permissions block, so assert
# the rule for EVERY reusable workflow — including the next one someone adds.
# Property, not instance: `selftest-complete` is the only check the ruleset requires, so a
# job missing from its `needs` is silently ungated and can fail a PR green.
check 'every selftest job is gated by selftest-complete'   ''   "$(python3 - "$PLATFORM_ROOT" <<'PY' 2>/dev/null
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1] + "/.github/workflows/selftest.yml")) or {}
jobs = doc.get("jobs", {})
gated = set(jobs.get("selftest-complete", {}).get("needs", []))
print(",".join(sorted(j for j in jobs if j != "selftest-complete" and j not in gated)))
PY
)"

# Regression: a `paths:` filter here meant a docs-only PR started no jobs at all, so a
# required check could never report and the PR would wait on it forever. That is why this
# repo had no branch protection while every repo it generates has eight required checks.
check 'selftest has no paths filter, so it reports on every PR'   ''   "$(python3 - "$PLATFORM_ROOT" <<'PY' 2>/dev/null
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1] + "/.github/workflows/selftest.yml")) or {}
triggers = doc.get("on", doc.get(True)) or {}
pr = triggers.get("pull_request") or {}
print(",".join(sorted(pr.get("paths", []))))
PY
)"

check 'every reusable workflow declares permissions' \
  '' \
  "$(python3 - "$PLATFORM_ROOT" <<'PY' 2>/dev/null
import glob, sys, yaml
missing = []
for path in sorted(glob.glob(sys.argv[1] + "/.github/workflows/*.yml")):
    doc = yaml.safe_load(open(path)) or {}
    # PyYAML (YAML 1.1) parses the bare key `on:` as the boolean True.
    triggers = doc.get("on", doc.get(True))
    if isinstance(triggers, dict) and "workflow_call" in triggers and not doc.get("permissions"):
        missing.append(path.rsplit("/", 1)[-1])
print(",".join(missing))
PY
)"

check 'template workflows forward only named secrets' \
  '' \
  "$(python3 - "$PLATFORM_ROOT" <<'PY' 2>/dev/null
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
failures = []
for path in (root / 'templates').glob('*/.github/workflows/*'):
    try:
        document = yaml.safe_load(path.read_text()) or {}
        for job in document.get('jobs', {}).values():
            if job.get('secrets') == 'inherit':
                failures.append(str(path.relative_to(root)))
    except (OSError, ValueError, TypeError, AttributeError, yaml.YAMLError):
        failures.append(str(path.relative_to(root)) + ': invalid workflow')
print(','.join(failures))
PY
)"

check 'third-party Actions are pinned and data inputs stay out of shell source' \
  '' \
  "$(python3 - "$PLATFORM_ROOT" <<'PY' 2>/dev/null
import pathlib, re, sys, yaml
root = pathlib.Path(sys.argv[1])
failures = []
paths = list((root / '.github/workflows').glob('*.yml')) + list((root / 'templates').glob('*/.github/workflows/*'))
for path in paths:
    try:
        document = yaml.safe_load(path.read_text()) or {}
        for job in document.get('jobs', {}).values():
            for step in job.get('steps', []):
                ref = step.get('uses', '')
                if ref and not ref.startswith(('./', 'willzhu16/')) and not re.search(r'@(?:[0-9a-f]{40}|sha256:[0-9a-f]{64})$', ref):
                    failures.append(path.name + ': unpinned ' + ref)
                script = step.get('run', '')
                if re.search(r'\$\{\{\s*inputs\.', script) and script != '${{ inputs.publish-command }}':
                    failures.append(path.name + ': input interpolated into shell')
    except (OSError, ValueError, TypeError, AttributeError, yaml.YAMLError):
        failures.append(path.name + ': invalid workflow')
print(','.join(failures))
PY
)"

check 'Vitest minimum is patched in the fixture and Worker template' \
  '' \
  "$(python3 - "$PLATFORM_ROOT" <<'PY' 2>/dev/null
import json, sys
root = sys.argv[1]
failures = []
for relative in ('selftest-fixture/package.json', 'templates/cf-worker-app/package.json.jinja'):
    try:
        dependencies = json.load(open(root + '/' + relative))['devDependencies']
        for package in ('vitest', '@vitest/coverage-v8'):
            version = tuple(map(int, dependencies[package].lstrip('^~').split('.')))
            if version < (4, 1, 11):
                failures.append(relative + ': ' + package + ' permits vulnerable Vitest')
    except (OSError, ValueError, KeyError, AttributeError, TypeError):
        failures.append(relative + ': cannot validate Vitest minimum')
print(','.join(failures))
PY
)"

# --- adopt-project.sh helpers ---------------------------------------------------------
# The retrofit path writes workflow callers into repos that already have history, so the
# job ids (the frozen check-name contract) and the owner substitution are the two things
# that must never quietly drift.

for piece in security ci codeql; do
  check "caller_workflow ${piece} keeps the frozen job id" \
    "${piece}" \
    "$(render_caller_workflow "$piece" someone | python3 -c 'import sys,yaml; print(",".join(yaml.safe_load(sys.stdin)["jobs"]))' 2>/dev/null)"

  check "caller_workflow ${piece} substitutes the owner" \
    "someone/platform/.github/workflows/${piece}.yml@v1" \
    "$(render_caller_workflow "$piece" someone | python3 -c 'import sys,yaml; d=yaml.safe_load(sys.stdin); print(list(d["jobs"].values())[0]["uses"])' 2>/dev/null)"
done

check 'caller_workflow rejects an unknown pipeline' \
  'rejected' \
  "$(caller_workflow nonsense >/dev/null 2>&1 && echo accepted || echo rejected)"

# The launch-start review turned on exactly this check: a nightly job pushing to main is
# what the Artemis ruleset would start rejecting the moment that repo adopted it.
check 'workflow_pushes_directly spots a job pushing to a branch' \
  'yes' \
  "$(printf 'steps:\n  - run: |\n      git commit -m x\n      git push\n' | workflow_pushes_directly && echo yes || echo no)"

check 'workflow_pushes_directly ignores a workflow that only reads' \
  'no' \
  "$(printf 'steps:\n  - run: git log --oneline\n  - run: pnpm test\n' | workflow_pushes_directly && echo yes || echo no)"

check 'has_script_contract accepts all three scripts' \
  'yes' \
  "$(echo '{"scripts":{"lint":"x","typecheck":"y","test":"z"}}' | has_script_contract && echo yes || echo no)"

check 'has_script_contract rejects a missing script' \
  'no' \
  "$(echo '{"scripts":{"lint":"x","test":"z"}}' | has_script_contract && echo yes || echo no)"

# Empty targets must stay an empty array: a repo that is neither a Worker nor a VS Code
# extension takes no target layer rather than a wrong one.
check 'build_athena_config emits an empty targets array' \
  'v1|ts|0|1' \
  "$(build_athena_config ts '' claude | jq -r '"\(.athenaVersion)|\(.stack)|\(.targets|length)|\(.tools|length)"' 2>/dev/null)"

check 'build_athena_config splits comma lists' \
  'workers,vscode-ext|claude,codex' \
  "$(build_athena_config ts workers,vscode-ext claude,codex | jq -r '"\(.targets|join(","))|\(.tools|join(","))"' 2>/dev/null)"

echo '== adopt-project.sh (temporary repositories only)'

# Exercise the CLI itself: helper tests cannot catch writes that happen before validation.
git init -q "$TMP/adopt" || exit 1
mkdir -p "$TMP/adopt/.athena"
printf '{"athenaVersion":"v1","stack":"python","targets":[],"tools":["codex"],"tier":0}\n' \
  > "$TMP/adopt/.athena/config.json"
cp "$TMP/adopt/.athena/config.json" "$TMP/original-config.json"
check 'adoption refuses to overwrite an existing instruction config' \
  'rejected' \
  "$(bash "$SCRIPT_DIR/adopt-project.sh" "$TMP/adopt" --with security,instructions >"$TMP/adopt.log" 2>&1 && echo accepted || echo rejected)"
check 'refused instruction adoption preserves the config byte for byte' \
  'preserved' \
  "$(cmp -s "$TMP/original-config.json" "$TMP/adopt/.athena/config.json" && echo preserved || echo changed)"
check 'an overwrite blocker prevents all requested writes' \
  'absent' \
  "$([ -e "$TMP/adopt/.github/workflows/security.yml" ] && echo present || echo absent)"
check 'force permits replacing an instruction config' \
  'accepted' \
  "$(bash "$SCRIPT_DIR/adopt-project.sh" "$TMP/adopt" --with instructions --force >"$TMP/adopt.log" 2>&1 && echo accepted || echo rejected)"
check 'forced instruction adoption writes the requested stack' \
  'ts' \
  "$(jq -r '.stack' "$TMP/adopt/.athena/config.json")"

git init -q "$TMP/invalid-piece" || exit 1
check 'report-only adoption succeeds without creating files' \
  'accepted:absent' \
  "$(bash "$SCRIPT_DIR/adopt-project.sh" "$TMP/invalid-piece" >"$TMP/adopt.log" 2>&1 && printf accepted || printf rejected):$([ -e "$TMP/invalid-piece/.github" ] && echo present || echo absent)"
check 'adoption rejects an unknown piece' \
  'rejected' \
  "$(bash "$SCRIPT_DIR/adopt-project.sh" "$TMP/invalid-piece" --with security,typo >"$TMP/adopt.log" 2>&1 && echo accepted || echo rejected)"
check 'an unknown piece leaves no partial workflow behind' \
  'absent' \
  "$([ -e "$TMP/invalid-piece/.github" ] && echo present || echo absent)"

git init -q "$TMP/multiline-piece" || exit 1
check 'adoption rejects a multiline piece list without writing' \
  'rejected:absent' \
  "$(bash "$SCRIPT_DIR/adopt-project.sh" "$TMP/multiline-piece" --with $'security\ntypo' >"$TMP/adopt.log" 2>&1 && printf accepted || printf rejected):$([ -e "$TMP/multiline-piece/.github" ] && echo present || echo absent)"

git -C "$TMP/adopt" -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m 'test fixture' || exit 1
git -C "$TMP/adopt" worktree add -q --detach "$TMP/worktree" || exit 1
check 'adoption accepts a linked Git worktree' \
  'accepted' \
  "$(bash "$SCRIPT_DIR/adopt-project.sh" "$TMP/worktree" --with security >"$TMP/adopt.log" 2>&1 && echo accepted || echo rejected)"
check 'worktree adoption installs the requested workflow' \
  'present' \
  "$([ -f "$TMP/worktree/.github/workflows/security.yml" ] && echo present || echo absent)"

# --- templates/cf-worker-app/scripts/smoke.sh ------------------------------------------
# The smoke script only ever runs against a real deployment, so the failure that matters is
# it passing while the deployment is broken. These point it at a stand-in Worker that can
# serve each contract wrongly on request, and assert it notices.
SMOKE="${PLATFORM_ROOT}/templates/cf-worker-app/scripts/smoke.sh"

smoke_result() { # $1=mode -> "ok" | "failed" | "no-server"
  local mode="$1" port_file="$TMP/port.$1" pid port result
  rm -f "$port_file"
  python3 "$SCRIPT_DIR/smoke-fixture-server.py" "$mode" "$port_file" &
  pid=$!
  for _ in $(seq 1 50); do
    [ -s "$port_file" ] && break
    sleep 0.1
  done
  port="$(cat "$port_file" 2>/dev/null || true)"
  if [ -z "$port" ]; then
    kill "$pid" 2>/dev/null
    echo 'no-server'
    return
  fi
  if bash "$SMOKE" "http://127.0.0.1:${port}" >"$TMP/smoke.$mode.log" 2>&1; then
    result=ok
  else
    result=failed
  fi
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  echo "$result"
}

check 'smoke passes against a healthy deployment' 'ok' "$(smoke_result good)"
check 'smoke fails when a security header is missing' 'failed' "$(smoke_result missing-header)"
check 'smoke fails on an expired security.txt' 'failed' "$(smoke_result expired-security-txt)"
check 'smoke fails when /healthz is unhealthy' 'failed' "$(smoke_result bad-healthz)"
check 'smoke fails when security.txt is absent' 'failed' "$(smoke_result no-security-txt)"
check 'smoke refuses to run without a base url' \
  'rejected' \
  "$(bash "$SMOKE" >/dev/null 2>&1 && echo accepted || echo rejected)"

# --- session-log validator -------------------------------------------------------------
# The block is the only record of HOW a change was made, and the monthly harvest is meant to
# count it. These assert the enumerated half actually gates: a log that reads complete but
# carries an unfilled placeholder, or an unenumerated Plan value, is exactly what would
# otherwise reach the harvest as data.
# shellcheck source=scripts/session-log.sh
. "$SCRIPT_DIR/session-log.sh"

WELL_FORMED='## Session log
Tool/model: claude/opus-5
Packet: #42
Plan: before-first-edit
Gates: lint typecheck test
Retries: 0 gate failures before green
Abstained: no
Tried: scoped the ban to src/ and proved it by rule name
Dead ends: asserted on the exit code, which a formatting error also satisfies
Decisions and why: listed bare specifiers so the rule stands on its own'

log_verdict() { # $1=block -> ok, or the first problem reported
  local out
  if out="$(validate_session_log "$1" 2>&1)"; then echo ok; else echo "$out" | head -1; fi
}

mutate_log() { # $1=sed script -> WELL_FORMED with one field changed
  printf '%s\n' "$WELL_FORMED" | sed "$1"
}

check 'a filled session log passes' 'ok' "$(log_verdict "$WELL_FORMED")"

check 'a body with no session log is rejected' \
  'no "## Session log" heading — every agent PR body ends with one' \
  "$(log_verdict 'Some PR prose and nothing else.')"

check 'a missing enumerated field is named' \
  'missing field: Plan' \
  "$(log_verdict "$(printf '%s\n' "$WELL_FORMED" | grep -v '^Plan:')")"

check 'an unenumerated Plan value is rejected' \
  'field Plan does not match ^(before-first-edit|mid-task|none)$: sort of' \
  "$(log_verdict "$(mutate_log 's/^Plan: .*/Plan: sort of/')")"

check 'a non-numeric retry count is rejected' \
  'field Retries does not match ^[0-9]+: several' \
  "$(log_verdict "$(mutate_log 's/^Retries: .*/Retries: several/')")"

check 'an unfilled placeholder is rejected, not read as an answer' \
  'placeholder left unfilled: Tried' \
  "$(log_verdict "$(mutate_log 's|^Tried: .*|Tried: <the approach that worked>|')")"

check 'abstaining yes without a reason is rejected' \
  'field Abstained does not match ^(no|yes[[:space:]]*[—-].+)$: yes' \
  "$(log_verdict "$(mutate_log 's/^Abstained: .*/Abstained: yes/')")"

check 'abstaining yes with a reason passes' 'ok' \
  "$(log_verdict "$(mutate_log 's/^Abstained: .*/Abstained: yes — the packet named two outcomes/')")"

check 'a field stated twice is reported rather than silently resolved' \
  'field stated 2 times: Plan' \
  "$(log_verdict "$(printf '%s\n%s\n' "$WELL_FORMED" 'Plan: mid-task')")"

# Closes the loop the semgrep and gitleaks fixtures close: the shipped template and the
# validator that judges it cannot drift apart without this going red.
check "the handbook template's worked example satisfies the validator" 'ok' \
  "$(log_verdict "$(awk '/^## Example/{flag=1} flag' "$PLATFORM_ROOT/handbook/templates/session-log.md" \
      | sed -n '/^```/,/^```$/p' | sed '1d;$d')")"

# --- sandbox profile ------------------------------------------------------------------
# The profile is a list of claims about what an agent cannot reach. A claim that quietly
# stops being true reads exactly like one that holds, so these assert the check itself
# fails on the weakenings that matter — not just that the shipped profile passes today.
SANDBOX_CHECK="$SCRIPT_DIR/sandbox-check.sh"
SHIPPED_PROFILE="$PLATFORM_ROOT/security/sandbox/srt-settings.json"

sandbox_verdict() { # $1=profile json -> ok | first FAIL line
  local file="$TMP/profile-$RANDOM.json" out
  printf '%s' "$1" > "$file"
  if out="$(bash "$SANDBOX_CHECK" "$file" 2>&1)"; then
    echo ok
  else
    grep -m 1 '^FAIL' <<<"$out" | sed 's/^FAIL  //'
  fi
}

weakened() { # $1=node expression mutating `profile`
  node -e "
    const fs = require('node:fs');
    const profile = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
    $1;
    process.stdout.write(JSON.stringify(profile));
  " "$SHIPPED_PROFILE"
}

check 'the shipped sandbox profile passes its own check' 'ok' \
  "$(sandbox_verdict "$(cat "$SHIPPED_PROFILE")")"

check 'a profile letting the agent rewrite its own hooks is rejected' \
  'the agent could rewrite its own supervision: .claude/hooks is not in denyWrite' \
  "$(sandbox_verdict "$(weakened "profile.filesystem.denyWrite = profile.filesystem.denyWrite.filter((p) => p !== '.claude/hooks')")")"

check 'a profile that stops denying reads of secrets is rejected' \
  'secrets is not in denyRead' \
  "$(sandbox_verdict "$(weakened "profile.filesystem.denyRead = profile.filesystem.denyRead.filter((p) => p !== 'secrets')")")"

check 'an over-broad write grant is rejected even with every deny intact' \
  'allowWrite contains ~, which defeats the profile' \
  "$(sandbox_verdict "$(weakened "profile.filesystem.allowWrite.push('~')")")"

# An empty allowlist looks stricter and is actually broken: the session cannot start, and a
# profile nobody can run protects nothing.
check 'a profile with no reachable model API is rejected' \
  'allowedDomains omits api.anthropic.com, so a session cannot start' \
  "$(sandbox_verdict "$(weakened 'profile.network.allowedDomains = []')")"

check 'the check exits non-zero on a weakened profile, since the exit code is the gate' \
  'rejected' \
  "$(printf '%s' "$(weakened "profile.filesystem.denyWrite = []")" > "$TMP/weak.json";
     bash "$SANDBOX_CHECK" "$TMP/weak.json" >/dev/null 2>&1 && echo accepted || echo rejected)"


# --- secrets/ encryption gate ------------------------------------------------------------
#
# sops_findings needs no sops and no age: it reads files. That is deliberate, because the
# check ships into every repo in the fleet through the reusable security workflow, including
# repos that never installed either tool.

# shellcheck source=scripts/sops-check.sh
. "$SCRIPT_DIR/sops-check.sh"

SOPS_BOOTSTRAP="$SCRIPT_DIR/sops-bootstrap.sh"
# A structurally valid age public key: "age1" plus 58 bech32 characters, 62 in total.
SOPS_VALID_RECIPIENT='age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p'

# Build a throwaway project. $1 names it; the rest are "path:content" pairs under secrets/.
sops_fixture() { # $1=name, $2...=relative-path:content
  local name="$1"; shift
  local root="$TMP/sops-$name"
  rm -rf "$root"
  mkdir -p "$root/secrets"
  local pair path
  for pair in "$@"; do
    path="$root/${pair%%:*}"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "${pair#*:}" >"$path"
  done
  printf '%s\n' "$root"
}

echo '== secrets/ encryption gate (scripts/sops-check.sh)'

check 'a repo with no secrets/ directory has nothing to report' \
  '' \
  "$(mkdir -p "$TMP/sops-bare" && sops_findings "$TMP/sops-bare")"

check 'an unencrypted file under secrets/ is reported' \
  'unencrypted secrets/dev.env — encrypt in place before committing: sops -e -i secrets/dev.env' \
  "$(sops_findings "$(sops_fixture plain 'secrets/dev.env:API_KEY=hunter2')")"

check 'a SOPS-encrypted file is accepted' \
  '' \
  "$(sops_findings "$(sops_fixture enc 'secrets/dev.env:API_KEY=ENC[AES256_GCM,data:xx,type:str]')")"

# These three are structure, not secrets. Requiring them to be encrypted would make the
# template's own secrets/README.md fail the gate it ships with.
check 'README.md, .gitignore and .gitkeep are not required to be encrypted' \
  '' \
  "$(sops_findings "$(sops_fixture exempt 'secrets/README.md:# secrets' \
    'secrets/.gitignore:*.tmp' 'secrets/.gitkeep:')")"

check 'a file in a subdirectory of secrets/ is checked too' \
  'unencrypted secrets/preview/api.env — encrypt in place before committing: sops -e -i secrets/preview/api.env' \
  "$(sops_findings "$(sops_fixture nested 'secrets/preview/api.env:TOKEN=abc')")"

# grep -F, not grep: the marker contains a bracket, and as a pattern "ENC[AES256_GCM" is an
# unterminated character class. Matched as a regex this file would be accepted or the grep
# would error out, and either way an unencrypted secret would pass.
check 'the ciphertext marker is matched literally, so a near-miss is still unencrypted' \
  'unencrypted secrets/dev.env — encrypt in place before committing: sops -e -i secrets/dev.env' \
  "$(sops_findings "$(sops_fixture nearmiss 'secrets/dev.env:API_KEY=ENCxAES256_GCM,data:xx')")"

check 'the placeholder recipient is reported when something needs encrypting' \
  'unencrypted secrets/dev.env — encrypt in place before committing: sops -e -i secrets/dev.env
unconfigured .sops.yaml — recipient is still the template placeholder, so sops -e cannot run; fix with scripts/sops-bootstrap.sh' \
  "$(root="$(sops_fixture unconfigured 'secrets/dev.env:API_KEY=hunter2')" &&
     cp "$PLATFORM_ROOT/templates/cf-worker-app/.sops.yaml" "$root/.sops.yaml" &&
     sops_findings "$root")"

# A repo straight out of the template must be silent. The placeholder is not a defect until
# there is a secret it cannot encrypt, and a gate that fires on every new project gets muted.
check 'a freshly generated repo with only README.md is silent despite the placeholder' \
  '' \
  "$(root="$(sops_fixture fresh 'secrets/README.md:# secrets')" &&
     cp "$PLATFORM_ROOT/templates/cf-worker-app/.sops.yaml" "$root/.sops.yaml" &&
     sops_findings "$root")"

check 'the committed cf-worker-app template passes its own gate' \
  'PASS  secrets/ holds no files to encrypt' \
  "$(bash "$SCRIPT_DIR/sops-check.sh" "$PLATFORM_ROOT/templates/cf-worker-app")"

# The PASS wording distinguishes "checked files, all encrypted" from "found nothing to check".
# Identical wording would let a rename that empties secrets/ report success unchanged.
check 'a pass over an empty store does not claim it verified files' \
  'PASS  secrets/ holds no files to encrypt' \
  "$(bash "$SCRIPT_DIR/sops-check.sh" "$(sops_fixture empty 'secrets/README.md:# r')")"

check 'a pass over a populated store says how many files it verified' \
  'PASS  2 file(s) under secrets/ are SOPS-encrypted' \
  "$(bash "$SCRIPT_DIR/sops-check.sh" "$(sops_fixture counted \
    'secrets/README.md:# r' 'secrets/a.env:K=ENC[AES256_GCM,data:x]' \
    'secrets/b.env:K=ENC[AES256_GCM,data:y]')")"

check 'the check exits non-zero on an unencrypted file, since the exit code is the gate' \
  'rejected' \
  "$(bash "$SCRIPT_DIR/sops-check.sh" "$(sops_fixture exitcode 'secrets/dev.env:K=v')" \
    >/dev/null 2>&1 && echo accepted || echo rejected)"

echo '== sops bootstrap (scripts/sops-bootstrap.sh)'

# The whole point of --recipient: it is how a shared key gets used deliberately, without one
# being committed to a public template where everybody would hold the private half.
check 'a valid recipient replaces the placeholder and leaves the rules intact' \
  "    age: $SOPS_VALID_RECIPIENT|  - path_regex: secrets/.*\\.(env|json|yaml)\$" \
  "$(root="$(sops_fixture boot 'secrets/README.md:# r')" &&
     cp "$PLATFORM_ROOT/templates/cf-worker-app/.sops.yaml" "$root/.sops.yaml" &&
     bash "$SOPS_BOOTSTRAP" "$root" --recipient "$SOPS_VALID_RECIPIENT" >/dev/null 2>&1 &&
     printf '%s|%s' "$(grep 'age:' "$root/.sops.yaml")" "$(grep 'path_regex' "$root/.sops.yaml")")"

check 'a recipient of the wrong length is refused before anything is written' \
  'refused' \
  "$(root="$(sops_fixture shortkey 'secrets/README.md:# r')" &&
     cp "$PLATFORM_ROOT/templates/cf-worker-app/.sops.yaml" "$root/.sops.yaml" &&
     { bash "$SOPS_BOOTSTRAP" "$root" --recipient age1short >/dev/null 2>&1 \
       && echo accepted || echo refused; })"

# b, i, o and 1 are not in the bech32 alphabet, so a key containing one is a typo. Catching it
# here matters because the failure otherwise surfaces as files nobody can decrypt.
check 'a recipient with a non-bech32 character is refused' \
  'refused' \
  "$(root="$(sops_fixture badchar 'secrets/README.md:# r')" &&
     cp "$PLATFORM_ROOT/templates/cf-worker-app/.sops.yaml" "$root/.sops.yaml" &&
     { bash "$SOPS_BOOTSTRAP" "$root" --recipient \
       age1bl3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p >/dev/null 2>&1 \
       && echo accepted || echo refused; })"

check 'passing both a recipient and a key path is refused rather than reporting a phantom file' \
  'refused' \
  "$(root="$(sops_fixture bothflags 'secrets/README.md:# r')" &&
     cp "$PLATFORM_ROOT/templates/cf-worker-app/.sops.yaml" "$root/.sops.yaml" &&
     { bash "$SOPS_BOOTSTRAP" "$root" --recipient "$SOPS_VALID_RECIPIENT" \
       --key-out "$TMP/never.agekey" >/dev/null 2>&1 && echo accepted || echo refused; })"

check 'a directory with no .sops.yaml is refused' \
  'refused' \
  "$(bash "$SOPS_BOOTSTRAP" "$(sops_fixture nosops 'secrets/README.md:# r')" \
    --recipient "$SOPS_VALID_RECIPIENT" >/dev/null 2>&1 && echo accepted || echo refused)"

check 'no private key file is created when a recipient is supplied' \
  'none' \
  "$(root="$(sops_fixture nokey 'secrets/README.md:# r')" &&
     cp "$PLATFORM_ROOT/templates/cf-worker-app/.sops.yaml" "$root/.sops.yaml" &&
     bash "$SOPS_BOOTSTRAP" "$root" --recipient "$SOPS_VALID_RECIPIENT" >/dev/null 2>&1 &&
     { grep -q . < <(find "$root" -name '*.agekey') && echo found || echo none; })"
# --- fleet audit ------------------------------------------------------------------------
#
# fleet_findings carries most of these: it is the whole decision, and it takes the inventory
# on stdin precisely so these tests need no network. The token guard sits on the gh path
# instead, so its two checks at the end swap gh for a function.

# shellcheck source=scripts/fleet-audit.sh
. "$SCRIPT_DIR/fleet-audit.sh"

FLEET_FILE="$PLATFORM_ROOT/fleet/unmanaged.json"

# Column padding is asserted once, on its own, below. Everywhere else the spaces are squeezed
# so an assertion is about which repo was reported and why, not about a field width.
fleet_verdict() { # $1=acknowledgement JSON text; inventory on stdin
  printf '%s' "$1" >"$TMP/fleet.json"
  fleet_findings "$TMP/fleet.json" | tr -s ' '
}

FLEET_ACK_PLATFORM='{"epoch":"2026-07-01",
  "acknowledged":[{"repo":"platform","reason":"the source of the harness, not a consumer"}]}'
FLEET_NO_ACK='{"epoch":"2026-07-01","acknowledged":[]}'

# A roster acknowledging nothing, on disk, for the checks that are about the report itself
# rather than about the committed file's contents. Pointing those at the real roster couples
# them to it: an inventory omitting athena, platform or artemis draws three correct "absent
# from the inventory" findings, which drown the assertion.
printf '%s' "$FLEET_NO_ACK" >"$TMP/plain-fleet.json"

echo '== fleet-audit (scripts/fleet-audit.sh)'

check 'an in-scope repo with no config and no acknowledgement is a finding' \
  'unmanaged memoria — created 2026-09-14, no .athena/config.json and no entry in fleet/unmanaged.json' \
  "$(fleet_verdict "$FLEET_NO_ACK" <<<"$(printf 'memoria\t2026-09-14\tno\n')")"

check 'a managed repo is not reported' \
  '' \
  "$(fleet_verdict "$FLEET_NO_ACK" <<<"$(printf 'canary-worker\t2026-07-12\tyes\n')")"

# The narrowing that makes the audit usable at all: 19 of the owner's repos predate Artemis
# and were never candidates. Without the epoch this check reports all of them and gets muted.
check 'a repo created before the epoch is ignored even though it is unmanaged' \
  '' \
  "$(fleet_verdict "$FLEET_NO_ACK" <<<"$(printf 'FlappyBird\t2024-09-26\tno\n')")"

# Boundary: the epoch is inclusive, so a repo created exactly on it is in scope. An off-by-one
# here silently excuses whatever was created that day.
check 'a repo created exactly on the epoch is in scope' \
  'unmanaged same-day — created 2026-07-01, no .athena/config.json and no entry in fleet/unmanaged.json' \
  "$(fleet_verdict "$FLEET_NO_ACK" <<<"$(printf 'same-day\t2026-07-01\tno\n')")"

check 'the day before the epoch is out of scope' \
  '' \
  "$(fleet_verdict "$FLEET_NO_ACK" <<<"$(printf 'day-before\t2026-06-30\tno\n')")"

check 'an acknowledged repo is not reported' \
  '' \
  "$(fleet_verdict "$FLEET_ACK_PLATFORM" <<<"$(printf 'platform\t2026-07-06\tno\n')")"

check 'an acknowledged repo that has since been adopted is reported stale' \
  'stale platform — acknowledged as unmanaged, but it now has .athena/config.json; remove the entry' \
  "$(fleet_verdict "$FLEET_ACK_PLATFORM" <<<"$(printf 'platform\t2026-07-06\tyes\n')")"

check 'an acknowledged repo missing from the inventory is reported without guessing why' \
  'stale platform — acknowledged, but absent from the inventory: deleted, renamed, or invisible to this token' \
  "$(fleet_verdict "$FLEET_ACK_PLATFORM" <<<"$(printf 'memoria\t2026-09-14\tyes\n')")"

check 'an acknowledgement with no reason is rejected' \
  'config gizmo — acknowledged with no reason; say why it stays outside the fleet' \
  "$(fleet_verdict '{"epoch":"2026-07-01","acknowledged":[{"repo":"gizmo"}]}' \
    <<<"$(printf 'gizmo\t2026-08-01\tno\n')")"

# A reason pasted from an example and never filled in is the failure this guards: it reads as
# a decision to whoever skims the file next.
check 'an acknowledgement whose reason is still a placeholder is rejected' \
  'config gizmo — reason is still a placeholder: <why it stays out>' \
  "$(fleet_verdict '{"epoch":"2026-07-01","acknowledged":[{"repo":"gizmo","reason":"<why it stays out>"}]}' \
    <<<"$(printf 'gizmo\t2026-08-01\tno\n')")"

# An empty inventory is the dangerous case: a failed gh call produces no lines, and reporting
# that as a clean fleet would be the audit claiming it checked something it never saw.
check 'an empty inventory is reported, never treated as a clean fleet' \
  'config inventory — no repos read — nothing was checked' \
  "$(fleet_verdict "$FLEET_NO_ACK" </dev/null)"

check 'an epoch that is not a date is rejected rather than compared as a string' \
  'config '"$TMP"'/fleet.json — epoch "July 2026" is not a YYYY-MM-DD date' \
  "$(fleet_verdict '{"epoch":"July 2026","acknowledged":[]}' \
    <<<"$(printf 'gizmo\t2026-08-01\tno\n')")"

check 'a fleet file with no epoch is rejected' \
  'config '"$TMP"'/fleet.json — unreadable, or no "epoch" field: cannot tell which repos are in scope' \
  "$(fleet_verdict '{"acknowledged":[]}' <<<"$(printf 'gizmo\t2026-08-01\tno\n')")"

check 'a missing fleet file is reported rather than crashing the run' \
  'config /nope/fleet.json — unreadable, or no "epoch" field: cannot tell which repos are in scope' \
  "$(fleet_findings /nope/fleet.json <<<"$(printf 'gizmo\t2026-08-01\tno\n')" | tr -s ' ')"

# The one assertion about the column format, so the tests above can squeeze padding without
# leaving the report layout unpinned.
check 'findings print as padded columns' \
  'unmanaged gizmo' \
  "$(fleet_findings "$TMP/plain-fleet.json" <<<"$(printf 'gizmo\t2026-08-01\tno\n')" | cut -c1-15)"

# The committed file has to be well-formed and its entries live, or the audit's silence stops
# meaning anything. Adopting any repo listed in it will fail this deliberately.
FLEET_ACKNOWLEDGED_INVENTORY="$(printf '%s\n' \
  $'athena\t2026-07-06\tno' $'platform\t2026-07-06\tno' $'artemis\t2026-07-06\tno' \
  $'launch-start\t2026-07-04\tno' $'memoria\t2026-09-14\tno' $'idea-scout\t2026-09-18\tno' \
  $'animation_studio\t2026-07-17\tno')"
check 'the committed fleet/unmanaged.json is well-formed and holds no stale entries' \
  '' \
  "$(fleet_findings "$FLEET_FILE" <<<"$FLEET_ACKNOWLEDGED_INVENTORY")"

check 'the audit exits non-zero on a finding, since the exit code is the gate' \
  'reported' \
  "$(bash "$SCRIPT_DIR/fleet-audit.sh" --fleet-file "$TMP/plain-fleet.json" \
    --inventory <(printf 'gizmo\t2026-08-01\tno\n') >/dev/null 2>&1 && echo clean || echo reported)"

check 'the audit exits zero when every in-scope repo is managed' \
  'clean' \
  "$(bash "$SCRIPT_DIR/fleet-audit.sh" --fleet-file "$TMP/plain-fleet.json" \
    --inventory <(printf 'canary-worker\t2026-07-12\tyes\n') >/dev/null 2>&1 && echo clean || echo reported)"

# The token guard lives in the gh path, so these run fleet_audit_main against a stand-in for
# gh. It lists one public repo, gizmo, in scope and unmanaged, and answers a request for
# private repos with $1. Only the findings are kept; the summary line after them is not the
# subject here.
fleet_audit_with_gh() { # $1=private repo names the token can see, one per line
  local fake_private_repos="$1"
  (
    gh() {
      case "$*" in
        'repo list '*'--visibility private'*) printf '%s\n' "$fake_private_repos" ;;
        'repo list '*) printf 'gizmo\t2026-08-01\n' ;;
        *) return 1 ;;
      esac
    }
    fleet_audit_main --fleet-file "$TMP/plain-fleet.json" | sed '/^$/,$d' | tr -s ' '
  )
}

# Regression: the weekly job ran on 2026-09-28, 10-05 and 10-12 under a token that could not
# see private repos. It reported launch-start, missed the three private repos in the same state,
# and called the private `artemis` entry stale. The audit has to refuse, not half-report.
check 'a token that sees no private repo stops the audit instead of reporting half the fleet' \
  'config token — lists no private repos for willzhu16: an audit under it would see only the public half of the fleet' \
  "$(fleet_audit_with_gh '')"

check 'a token that sees private repos runs the audit' \
  'unmanaged gizmo — created 2026-08-01, no .athena/config.json and no entry in fleet/unmanaged.json' \
  "$(fleet_audit_with_gh 'memoria')"

# --- osv coverage gate ------------------------------------------------------------------
#
# The scanner's output is faked as JSON in the shape `--all-packages` prints, so these need no
# scanner and no network. selftest's test-osv-coverage job runs the real one on the fixtures.

# shellcheck source=scripts/osv-coverage.sh
. "$SCRIPT_DIR/osv-coverage.sh"

# A repo holding the given files, staged. Staging is enough: the gate reads `git ls-files`.
osv_fixture() { # $1=name, $2...=relative-path:content
  local name="$1"; shift
  local root="$TMP/osv-$name"
  rm -rf "$root"
  mkdir -p "$root"
  git -C "$root" init -q
  local pair path
  for pair in "$@"; do
    path="$root/${pair%%:*}"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "${pair#*:}" >"$path"
  done
  git -C "$root" add -A
  printf '%s\n' "$root"
}

# What osv-scanner would print having read each lockfile under /scan, its count after the colon.
osv_json() { # $1...=repo-relative-path:package-count
  local pair
  for pair in "$@"; do
    jq -n --arg path "/scan/${pair%%:*}" --argjson n "${pair#*:}" \
      '{source: {path: $path, type: "lockfile"},
        packages: [range($n) | {package: {name: "pkg\(.)", version: "1.0.0"}}]}'
  done | jq -s '{results: .}'
}

osv_verdict() { # $1=repo dir; the scanner's JSON on stdin
  cat >"$TMP/osv.json"
  osv_coverage_findings "$TMP/osv.json" "$1" /scan
}

# Three packages: vite appears twice with different peers, and neither the packages: section
# nor the keys nested under a snapshot are packages of their own.
OSV_PNPM="lockfileVersion: '9.0'

importers:

  .:
    devDependencies:
      vite:
        specifier: ^8.1.4
        version: 8.1.4(@types/node@24.0.0)

packages:

  '@types/node@24.0.0':
    resolution: {integrity: sha512-a}

  esbuild@0.25.0:
    resolution: {integrity: sha512-b}

  vite@8.1.4:
    resolution: {integrity: sha512-c}

snapshots:

  '@types/node@24.0.0': {}

  esbuild@0.25.0:
    optionalDependencies:
      '@esbuild/linux-x64': 0.25.0

  vite@8.1.4(@types/node@24.0.0):
    dependencies:
      esbuild: 0.25.0

  vite@8.1.4(@types/node@25.0.0):
    dependencies:
      esbuild: 0.25.0"

# pnpm 12's shape: a small document for pnpm's own config dependencies, then the lockfile.
# Four packages in all, one of them in both documents.
OSV_PNPM12="---
lockfileVersion: '9.0'

snapshots:

  pnpm@12.0.0: {}

  '@pnpm/config@1.0.0': {}

---
lockfileVersion: '9.0'

snapshots:

  esbuild@0.25.0: {}

  vite@8.1.4(@types/node@24.0.0): {}

  '@pnpm/config@1.0.0': {}"

OSV_UV='version = 1
requires-python = ">=3.12"

[[package]]
name = "colorama"
version = "0.4.6"

[[package]]
name = "demo"
version = "0.1.0"
source = { editable = "." }

[[package]]
name = "pytest"
version = "8.4.0"'

OSV_UV_TEN="$(for i in 1 2 3 4 5 6 7 8 9 10; do printf '[[package]]\nname = "p%s"\n\n' "$i"; done)"

echo '== osv coverage gate (scripts/osv-coverage.sh)'

check 'a pnpm lockfile counts distinct snapshots, not peer variants or nested keys' \
  '3' \
  "$(osv_lockfile_count "$(osv_fixture pnpm "pnpm-lock.yaml:$OSV_PNPM")/pnpm-lock.yaml")"

check 'a pnpm 12 lockfile counts both YAML documents, each package once' \
  '4' \
  "$(osv_lockfile_count "$(osv_fixture pnpm12 "pnpm-lock.yaml:$OSV_PNPM12")/pnpm-lock.yaml")"

check 'a uv.lock counts every [[package]] block, the project itself included' \
  '3' \
  "$(osv_lockfile_count "$(osv_fixture uv "uv.lock:$OSV_UV")/uv.lock")"

check 'a scanner that read every package of every lockfile is silent' \
  '' \
  "$(osv_json pnpm-lock.yaml:3 py/uv.lock:3 |
     osv_verdict "$(osv_fixture full "pnpm-lock.yaml:$OSV_PNPM" "py/uv.lock:$OSV_UV")")"

# Regression: on 2026-10-26 osv-scanner 2.3.8 read only the first YAML document of the pnpm 12
# lockfiles, 15 of athena's 309 packages, and `security / osv` passed the Renovate PRs.
check 'a scanner that read only the first document of a pnpm 12 lockfile fails the gate' \
  'partial pnpm-lock.yaml: osv-scanner read 2 of 4 packages; the rest were never checked' \
  "$(osv_json pnpm-lock.yaml:2 | osv_verdict "$(osv_fixture first-doc "pnpm-lock.yaml:$OSV_PNPM12")")"

check 'a committed lockfile the scanner never listed is reported' \
  'unscanned py/uv.lock: osv-scanner did not list it, so none of its 3 packages were checked' \
  "$(osv_json pnpm-lock.yaml:3 |
     osv_verdict "$(osv_fixture skipped "pnpm-lock.yaml:$OSV_PNPM" "py/uv.lock:$OSV_UV")")"

# Matching on a path suffix would let app/pnpm-lock.yaml stand in for the root one.
check 'a lockfile is matched by its full path, not by a file name it shares' \
  'unscanned pnpm-lock.yaml: osv-scanner did not list it, so none of its 3 packages were checked' \
  "$(osv_json app/pnpm-lock.yaml:3 |
     osv_verdict "$(osv_fixture same-name "pnpm-lock.yaml:$OSV_PNPM" "app/pnpm-lock.yaml:$OSV_PNPM")")"

check 'an untracked lockfile is not required, since the scanner skips ignored paths' \
  '' \
  "$(root="$(osv_fixture untracked "pnpm-lock.yaml:$OSV_PNPM")" &&
     printf '%s\n' "$OSV_UV" >"$root/uv.lock" &&
     osv_json pnpm-lock.yaml:3 | osv_verdict "$root")"

check 'reading exactly 90% of a lockfile passes' \
  '' \
  "$(osv_json uv.lock:9 | osv_verdict "$(osv_fixture ninety "uv.lock:$OSV_UV_TEN")")"

check 'reading less than 90% of a lockfile fails' \
  'partial uv.lock: osv-scanner read 8 of 10 packages; the rest were never checked' \
  "$(osv_json uv.lock:8 | osv_verdict "$(osv_fixture eighty "uv.lock:$OSV_UV_TEN")")"

# A format this check cannot read must not pass as an empty lockfile while the scanner reads it.
check 'a lockfile the scanner reads but this check counts as empty is reported' \
  'uncounted pnpm-lock.yaml: osv-scanner read 5 packages and this check counted none' \
  "$(osv_json pnpm-lock.yaml:5 |
     osv_verdict "$(osv_fixture new-format "pnpm-lock.yaml:lockfileVersion: '99.0'")")"

check 'a lockfile with no packages has nothing to miss' \
  '' \
  "$(osv_json | osv_verdict "$(osv_fixture empty-lock "pnpm-lock.yaml:lockfileVersion: '9.0'")")"

# The PASS line carries the counts, so a pass over nothing cannot read like a pass over a fleet.
check 'the PASS line says how many packages and lockfiles were compared' \
  'PASS  osv-scanner read 6 of 6 packages across 2 lockfile(s)' \
  "$(root="$(osv_fixture pass-line "pnpm-lock.yaml:$OSV_PNPM" "py/uv.lock:$OSV_UV")" &&
     osv_json pnpm-lock.yaml:3 py/uv.lock:3 >"$TMP/osv-pass.json" &&
     bash "$SCRIPT_DIR/osv-coverage.sh" "$TMP/osv-pass.json" "$root" /scan)"

check 'a missing package list fails instead of passing unchecked' \
  'rejected' \
  "$(bash "$SCRIPT_DIR/osv-coverage.sh" "$TMP/no-such.json" \
    "$(osv_fixture no-json "uv.lock:$OSV_UV")" /scan >/dev/null 2>&1 && echo accepted || echo rejected)"

check 'the gate exits non-zero on a finding, since the exit code is the gate' \
  'rejected' \
  "$(root="$(osv_fixture exit "uv.lock:$OSV_UV_TEN")" &&
     osv_json uv.lock:1 >"$TMP/osv-exit.json" &&
     bash "$SCRIPT_DIR/osv-coverage.sh" "$TMP/osv-exit.json" "$root" /scan >/dev/null 2>&1 &&
     echo accepted || echo rejected)"

# selftest's copy of the scan is only a guard for security.yml's while the two are identical.
check 'selftest runs the coverage scan with the same scanner pin and arguments as security.yml' \
  'same' \
  "$(python3 - "$PLATFORM_ROOT/.github/workflows" <<'PY' 2>/dev/null
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
def scans(name):
    jobs = yaml.safe_load((root / name).read_text())["jobs"]
    return {(step["uses"], step["with"]["scan-args"])
            for job in jobs.values() for step in job.get("steps", [])
            if step.get("uses", "").startswith("google/osv-scanner-action/")
            and "--all-packages" in step.get("with", {}).get("scan-args", "")}
security, selftest = scans("security.yml"), scans("selftest.yml")
print("same" if security and security == selftest else f"{sorted(security)} != {sorted(selftest)}")
PY
)"

# Regression: the non-major batch moved security.yml's semgrep job to Python 3.15, where
# semgrep-core crashes, and selftest's semgrep job, on the same Python, missed it because it
# only ran --test. Its real scan now guards security.yml's, but only on identical setups.
check 'selftest runs semgrep with the same version and Python as security.yml' \
  'same' \
  "$(python3 - "$PLATFORM_ROOT/.github/workflows" <<'PY' 2>/dev/null
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
def setup(name, job_id):
    doc = yaml.safe_load((root / name).read_text())
    job = doc["jobs"][job_id]
    version = {**doc.get("env", {}), **job.get("env", {})}.get("SEMGREP_VERSION")
    pythons = [step["with"]["python-version"] for step in job["steps"]
               if step.get("uses", "").startswith("actions/setup-python@")]
    return version, pythons
security = setup("security.yml", "semgrep")
selftest = setup("selftest.yml", "test-semgrep-rules")
print("same" if security[0] and security[1] and security == selftest else f"{security} != {selftest}")
PY
)"

# --- template sync ----------------------------------------------------------------------
#
# copier is stood in for here, as gh is for the fleet audit, so these pin the decisions made
# around it. selftest's test-template-sync job runs the real copier on both templates.

# shellcheck source=scripts/template-sync.sh
. "$SCRIPT_DIR/template-sync.sh"

# A committed repo that records template version $2, holding the given files.
tsync_fixture() { # $1=name, $2=recorded _commit, $3...=relative-path:content
  local name="$1" recorded="$2"; shift 2
  local root="$TMP/tsync-$name"
  rm -rf "$root"
  mkdir -p "$root"
  git -C "$root" init -q
  printf '_commit: %s\n_src_path: gh:willzhu16/platform\n' "$recorded" >"$root/.copier-answers.yml"
  local pair path
  for pair in "$@"; do
    path="$root/${pair%%:*}"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "${pair#*:}" >"$path"
  done
  git -C "$root" add -A
  git -C "$root" -c user.name=t -c user.email=t@invalid commit -qm init
  printf '%s\n' "$root"
}

# template_sync_main with copier replaced by the function named $1, run inside the repo.
tsync_with() { # $1=stand-in function, $2=target ref, $3=repo
  local stand_in="$1"
  (
    template_sync_copier() { "$stand_in" "$@"; }
    template_sync_main "$2" "$3" 2>/dev/null
  )
}

copier_updates() { printf 'v2\n' >README.md; sed -i 's/^_commit: .*/_commit: v1.14.1/' .copier-answers.yml; }
copier_conflicts() {
  printf '<<<<<<< before updating\nmine\n=======\ntheirs\n>>>>>>> after updating\n' >biome.json
}
copier_rejects() { printf 'hunk\n' >ci.yml.rej; }
copier_marks_run() { touch .copier-ran; }
copier_fails() { return 1; }
# What copier did in CI on 2026-10-29: asked for a release, it recorded a moving tag instead.
copier_records_canary() { sed -i 's/^_commit: .*/_commit: canary/' .copier-answers.yml; }

TSYNC_TAGS="$(printf '%s\n' \
  $'aaa111\trefs/tags/v1' $'aaa111\trefs/tags/canary' $'aaa111\trefs/tags/v1.14.1' \
  $'bbb222\trefs/tags/v1.14.0' $'fff666\trefs/tags/v1.12.0' $'ddd444\trefs/tags/v1.12.0^{}')"

echo '== template sync (scripts/template-sync.sh)'

check 'the release a moving tag points at is found by commit, the moving tags ignored' \
  'v1.14.1' \
  "$(release_tag_at aaa111 <<<"$TSYNC_TAGS")"

check 'an annotated release tag is found through its peeled commit line' \
  'v1.12.0' \
  "$(release_tag_at ddd444 <<<"$TSYNC_TAGS")"

check 'a commit no release tag points at gives nothing' \
  '' \
  "$(release_tag_at eee555 <<<"$TSYNC_TAGS")"

check 'the recorded template version is read with or without quotes' \
  'v1.7.0' \
  "$(root="$(tsync_fixture quoted v1.0.0)" &&
     printf "_commit: 'v1.7.0'\n" >"$root/.copier-answers.yml" && template_sync_recorded "$root")"

check 'a repo already on the target release runs nothing' \
  'current v1.14.1
not run' \
  "$(root="$(tsync_fixture current v1.14.1 'README.md:v1')" &&
     tsync_with copier_marks_run v1.14.1 "$root" &&
     { [ -e "$root/.copier-ran" ] && echo ran || echo 'not run'; })"

check 'a clean update reports the versions it moved between' \
  'updated v1.7.0 -> v1.14.1' \
  "$(tsync_with copier_updates v1.14.1 "$(tsync_fixture clean v1.7.0 'README.md:v1')")"

check 'files copier left conflict markers in are reported by name' \
  'conflicts v1.7.0 -> v1.14.1: biome.json' \
  "$(tsync_with copier_conflicts v1.14.1 "$(tsync_fixture marked v1.7.0 'biome.json:{}')")"

check 'a .rej file copier left is reported as a conflict' \
  'conflicts v1.7.0 -> v1.14.1: ci.yml.rej' \
  "$(tsync_with copier_rejects v1.14.1 "$(tsync_fixture rejected v1.7.0 'ci.yml:on: push')")"

check 'a release is pinned over the moving tag copier recorded' \
  '_commit: v1.15.0' \
  "$(root="$(tsync_fixture pin v1)" &&
     pin_template_commit "$root/.copier-answers.yml" v1.15.0 && grep '^_commit' "$root/.copier-answers.yml")"

check 'a ref that is not a release, like HEAD, is left as copier recorded it' \
  '_commit: v1.14.1-1-gec08a5d' \
  "$(root="$(tsync_fixture head v1.14.1-1-gec08a5d)" &&
     pin_template_commit "$root/.copier-answers.yml" HEAD && grep '^_commit' "$root/.copier-answers.yml")"

# Regression: a render asked for v1.14.1 recorded `v1` in CI, because `git describe` took the
# first of the tags on that commit. Recorded as-is, the next sync updates from a moving tag to
# itself and applies nothing, which is how the monthly sweep stayed broken until 2026-09-11.
check 'a sync records the release it was asked for, not the moving tag copier wrote' \
  'updated v1.7.0 -> v1.15.0|_commit: v1.15.0' \
  "$(root="$(tsync_fixture records v1.7.0 'README.md:v1')" &&
     printf '%s|%s' "$(tsync_with copier_records_canary v1.15.0 "$root")" \
       "$(grep '^_commit' "$root/.copier-answers.yml")")"

check 'a copier failure fails the sync instead of passing for current' \
  'rejected' \
  "$(tsync_with copier_fails v1.14.1 "$(tsync_fixture broken v1.7.0 'README.md:v1')" >/dev/null &&
     echo accepted || echo rejected)"

# A stand-in pnpm that only records that it ran, so the decision is tested and not pnpm.
mkdir -p "$TMP/fake-pnpm"
printf '#!/usr/bin/env bash\ntouch .pnpm-ran\n' >"$TMP/fake-pnpm/pnpm"
chmod +x "$TMP/fake-pnpm/pnpm"

# Generated repos commit a lockfile the template never ships, so an update that changes
# package.json leaves it stale, and CI's frozen install fails before anything is checked.
check 'an update that changes package.json refreshes the pnpm lockfile' \
  'refreshed' \
  "$(root="$(tsync_fixture lock-stale v1.7.0 'package.json:{}' 'pnpm-lock.yaml:x')" &&
     printf '{"name":"x"}\n' >"$root/package.json" &&
     PATH="$TMP/fake-pnpm:$PATH" template_sync_refresh_lockfiles "$root" 2>/dev/null &&
     { [ -e "$root/.pnpm-ran" ] && echo refreshed || echo untouched; })"

check 'an update that leaves package.json alone leaves the lockfile alone' \
  'untouched' \
  "$(root="$(tsync_fixture lock-fresh v1.7.0 'package.json:{}' 'pnpm-lock.yaml:x')" &&
     printf 'v2\n' >"$root/README.md" &&
     PATH="$TMP/fake-pnpm:$PATH" template_sync_refresh_lockfiles "$root" 2>/dev/null &&
     { [ -e "$root/.pnpm-ran" ] && echo refreshed || echo untouched; })"

# --- canary-gated release ---------------------------------------------------------------
#
# The verdict reads a canary run's job list, so these feed it job lists. The promotion itself
# runs against a stand-in for gh, as the fleet audit does, with the clock passed in.

# shellcheck source=scripts/canary-promote.sh
. "$SCRIPT_DIR/canary-promote.sh"

canary_jobs() { # $1=name, $2...="job name:conclusion" -> path of a jobs JSON file
  local file="$TMP/canary-$1.json" pair
  for pair in "${@:2}"; do
    jq -n --arg name "${pair%:*}" --arg conclusion "${pair##*:}" '{name: $name, conclusion: $conclusion}'
  done | jq -s . >"$file"
  printf '%s\n' "$file"
}

CANARY_CLEAN="$(canary_jobs clean 'pending:success' \
  'stable-ci / lint:success' 'canary-ci / lint:success' \
  'stable-security / semgrep:success' 'canary-security / semgrep:success')"
CANARY_REGRESSED="$(canary_jobs regressed 'pending:success' \
  'stable-ci / lint:success' 'canary-ci / lint:success' \
  'stable-security / semgrep:success' 'canary-security / semgrep:failure')"

echo '== canary-gated release (scripts/canary-promote.sh)'

check 'a canary run where every job matches v1 clears the release' \
  'PASS  2 canary job(s) match v1 (0 fail on both and are not held against the release)' \
  "$(canary_verdict "$CANARY_CLEAN")"

# Regression: 1.13.1 reached every repo at once and broke `security / semgrep` there. This is
# that release seen through the canary, which now holds it back.
check 'a job that passes on v1 and fails on canary holds the release back' \
  'regressed canary-security / semgrep: failure on canary, success on v1' \
  "$(canary_verdict "$CANARY_REGRESSED" 2>&1 >/dev/null)"

# canary-worker had osv red for over a week in October on its own lockfile. A gate that blamed
# each release for that would have held every release, and soon been bypassed.
check 'a job that fails on v1 and canary alike is not held against the release' \
  'PASS  1 canary job(s) match v1 (1 fail on both and are not held against the release)' \
  "$(canary_verdict "$(canary_jobs both 'stable-security / osv:failure' 'canary-security / osv:failure')")"

check 'a job that ran on v1 but is missing on canary holds the release back' \
  'missing canary-ci / test: stable-ci / test ran on v1 and canary has no such job' \
  "$(canary_verdict "$(canary_jobs missing 'stable-ci / lint:success' 'canary-ci / lint:success' \
    'stable-ci / test:success')" 2>&1 >/dev/null)"

check 'a failing canary job with nothing on v1 to compare holds the release back' \
  'unpaired canary-ci / audit: no stable-ci / audit ran to compare it with' \
  "$(canary_verdict "$(canary_jobs unpaired 'canary-ci / audit:failure')" 2>&1 >/dev/null)"

check 'a run where no canary job ran clears nothing' \
  'rejected' \
  "$(canary_verdict "$(canary_jobs skipped 'pending:success' 'stable-ci / lint:skipped' \
    'canary-ci / lint:skipped')" >/dev/null 2>&1 && echo accepted || echo rejected)"

CANARY_PUBLISHED="$(date -u -d 2026-10-29T12:00:00Z +%s)"

# canary_promote_main against a stand-in gh. v1 is at aaa111 (v1.14.1); the canary tag is at
# $1, ccc333 being v1.15.0, published at CANARY_PUBLISHED. $2 is the canary run found, or none.
canary_with_gh() { # $1=canary sha or '', $2=run id or '', $3=jobs file, $4=now, $5...=main args
  local canary_sha="$1" run_id="$2" jobs_file="$3" now="$4"
  shift 4
  : >"$TMP/canary-dispatch.log"
  (
    export PLATFORM_REPO=o/platform CANARY_REPO=o/canary-worker CANARY_NOW="$now"
    gh() {
      case "$*" in
        'api repos/o/platform/git/ref/tags/canary '*) [ -n "$canary_sha" ] && echo "$canary_sha" ;;
        'api repos/o/platform/git/ref/tags/v1 '*) echo aaa111 ;;
        'api repos/o/platform/git/matching-refs/tags/v '*)
          printf 'aaa111\trefs/tags/v1.14.1\nccc333\trefs/tags/v1.15.0\n' ;;
        'api repos/o/platform/releases/tags/v1.15.0 '*) echo 2026-10-29T12:00:00Z ;;
        'api repos/o/canary-worker/actions/workflows/canary.yml/runs?'*)
          [ "$run_id" != unreadable ] && echo "$run_id" ;;
        'api repos/o/canary-worker/actions/runs/'*) cat "$jobs_file" ;;
        'workflow run update-major-tag.yml '*) echo "$*" >>"$TMP/canary-dispatch.log" ;;
        *) return 1 ;;
      esac
    }
    canary_promote_main "$@" 2>&1
  )
}

check 'with no canary tag yet there is nothing to promote' \
  'nothing to promote: there is no canary tag yet' \
  "$(canary_with_gh '' '' "$CANARY_CLEAN" "$CANARY_PUBLISHED")"

check 'with v1 already at the canary release there is nothing to promote' \
  'nothing to promote: v1 is already at the canary release' \
  "$(canary_with_gh aaa111 '' "$CANARY_CLEAN" "$CANARY_PUBLISHED")"

check 'a release whose canary run has not happened yet waits quietly' \
  'waiting: no completed canary run of v1.15.0 yet' \
  "$(canary_with_gh ccc333 '' "$CANARY_CLEAN" "$((CANARY_PUBLISHED + 3600))")"

# Without this, a disabled canary.yml would leave v1 stuck on the old release with every
# promote run green, which reads exactly like "nothing to do".
check 'a release that has waited six hours with no canary run fails the promotion' \
  'v1.15.0 has waited over 6 hours with no canary run; check canary.yml in o/canary-worker' \
  "$(canary_with_gh ccc333 '' "$CANARY_CLEAN" "$((CANARY_PUBLISHED + 7 * 3600))")"

check 'a failed read of the canary runs fails loudly instead of passing for not run yet' \
  'could not read canary runs from o/canary-worker' \
  "$(canary_with_gh ccc333 unreadable "$CANARY_CLEAN" "$((CANARY_PUBLISHED + 3600))")"

check 'a cleared release dispatches the move of v1 to that release' \
  'workflow run update-major-tag.yml --repo o/platform --ref main -f tag=v1.15.0' \
  "$(canary_with_gh ccc333 9001 "$CANARY_CLEAN" "$((CANARY_PUBLISHED + 3600))" >/dev/null &&
     cat "$TMP/canary-dispatch.log")"

check 'a release the canary run did not clear leaves v1 where it is' \
  'held, nothing dispatched' \
  "$(canary_with_gh ccc333 9001 "$CANARY_REGRESSED" "$((CANARY_PUBLISHED + 3600))" >/dev/null ||
     { [ -s "$TMP/canary-dispatch.log" ] && echo dispatched || echo 'held, nothing dispatched'; })"

check 'a dry run judges the release and moves nothing' \
  'dry run: would move v1 to v1.15.0|nothing dispatched' \
  "$(out="$(canary_with_gh ccc333 9001 "$CANARY_CLEAN" "$((CANARY_PUBLISHED + 3600))" --dry-run)" &&
     printf '%s|%s' "$(tail -n1 <<<"$out")" \
       "$([ -s "$TMP/canary-dispatch.log" ] && echo dispatched || echo 'nothing dispatched')")"

# Property, not instance: every release fired `release: published` (release-please publishes
# with AUTOMATION_TOKEN), so a trigger left on update-major-tag.yml would move v1 the moment a
# release is cut and the canary would decide nothing.
check 'v1 moves only by dispatch, and only promote-canary.yml refers to that workflow' \
  'workflow_dispatch|promote-canary.yml' \
  "$(python3 - "$PLATFORM_ROOT/.github/workflows" <<'PY' 2>/dev/null
import pathlib, sys, yaml
root = pathlib.Path(sys.argv[1])
doc = yaml.safe_load((root / "update-major-tag.yml").read_text())
triggers = doc.get("on", doc.get(True))
callers = sorted(path.name for path in root.glob("*.yml")
                 if path.name != "update-major-tag.yml" and "update-major-tag.yml" in path.read_text())
print(",".join(sorted(triggers)) + "|" + ",".join(callers))
PY
)"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
