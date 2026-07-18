#!/usr/bin/env bash
# Regression tests for scripts/lib.sh plus one workflow invariant.
#
#   bash scripts/tests.sh
#
# Needs bash, jq and python3 with PyYAML — nothing else. new-project.sh and
# setup-machine.sh are never executed here (they create real GitHub repos and mutate the
# machine), which is exactly why their pure logic lives in lib.sh. Gated by selftest.yml.
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

echo '== workflow invariants'

# Property, not instance: athena-sync.yml shipped without a permissions block, so assert
# the rule for EVERY reusable workflow — including the next one someone adds.
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

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
