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
    printf '%s\n' "$out" | grep -m 1 '^FAIL' | sed 's/^FAIL  //'
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
     { find "$root" -name '*.agekey' | grep -q . && echo found || echo none; })"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
