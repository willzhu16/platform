#!/usr/bin/env bash
# Shared helpers for the bootstrap scripts. These live in one sourceable file so they can
# be tested directly (scripts/tests.sh): new-project.sh creates real GitHub repos and
# setup-machine.sh mutates the machine, so neither can be executed as a test — but the
# pure string-building logic inside them can.
#
# Contains no top-level side effects: sourcing this file only defines functions.

# Emit the copier answers as YAML on stdout, from the globals new-project.sh has already
# validated. DESCRIPTION and BINDINGS are free text (unlike NAME/TEMPLATE/VISIBILITY), so
# they go through jq rather than bare interpolation: a description containing ": " is not a
# valid YAML plain scalar, and a newline would inject a second answer key. jq emits a JSON
# string/array, which is valid YAML.
build_answers_file() {
  echo "template: ${TEMPLATE}"
  echo "project_name: ${NAME}"
  echo "description: $(jq -n --arg d "$DESCRIPTION" '$d')"
  echo "visibility: ${VISIBILITY}"
  if [ "$TEMPLATE" = 'cf-worker-app' ]; then
    echo "needs_scheduled_jobs: ${SCHEDULED}"
    echo "public_forms: ${PUBLIC_FORMS}"
    echo "bindings: $(jq -cn --arg b "$BINDINGS" '$b | split(",") | map(select(length > 0))')"
  fi
}

# Print the newest plain vX.Y.Z tag from a newline-separated list on stdin, or nothing.
# A generated project must record a CONCRETE release as its template ref: the moving major
# tags (`v1`) are force-moved onto every release, so a project whose `_commit` is `v1`
# later has copier compare the template against itself and report "Keeping template
# version 1" while applying nothing. Component-prefixed tags are ignored too.
# Never returns non-zero: grep exits 1 on no match, and under `set -euo pipefail` that
# would abort the caller instead of letting it fall back to an unpinned generate.
newest_release_tag() {
  { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -1
}

# Print $1's dotted version, or nothing if it has none. Never returns non-zero: under
# `set -euo pipefail` a bare assignment whose pipeline fails aborts the caller, and grep
# exits 1 when a tool prints no dotted version to stdout (gitleaks, age). The self-check
# table must never kill the run it exists to diagnose.
tool_version() {
  "$1" --version 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1 || true
}

# --- adopting an existing repo (adopt-project.sh) -----------------------------------
# new-project.sh only ever builds a repo from a template. Everything below exists so a
# repo that already has history can take Artemis a piece at a time instead of all at once.

# Emit the thin caller workflow for one reusable platform pipeline on stdout, with the
# owner left as __OWNER__ for render_caller_workflow to substitute. $1 = security|ci|codeql.
# The job id is the frozen check-name contract (D-18): literal here, never parameterised.
caller_workflow() {
  local kind="$1"
  case "$kind" in
    security)
      cat <<'YAML'
name: security

on:
  pull_request:
  push:
    branches: [main]

# One live run per branch: a superseded push cancels the previous run's jobs.
concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.run_id }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  security: # job id MUST be `security` — check-name contract
    uses: __OWNER__/platform/.github/workflows/security.yml@v1
YAML
      ;;
    ci)
      cat <<'YAML'
name: ci

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  ci: # job id MUST be `ci` — check-name contract
    uses: __OWNER__/platform/.github/workflows/ci.yml@v1
YAML
      ;;
    codeql)
      cat <<'YAML'
name: codeql

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read
  security-events: write

jobs:
  codeql: # job id MUST be `codeql` — check-name contract
    uses: __OWNER__/platform/.github/workflows/codeql.yml@v1
YAML
      ;;
    *)
      echo "caller_workflow: unknown pipeline '${kind}'" >&2
      return 1
      ;;
  esac
}

# Render a caller workflow with the owner substituted in.
render_caller_workflow() {
  caller_workflow "$1" | sed "s|__OWNER__|${2:-willzhu16}|"
}

# True when a workflow body pushes straight to a branch. The Artemis main ruleset requires
# pull requests and linear history, so adopting it would start rejecting such a job — the
# single most common way retrofitting an existing repo breaks it.
workflow_pushes_directly() {
  grep -qE '(^|[^[:alnum:]_-])git[[:space:]]+push([[:space:]]|$)'
}

# True when a package.json on stdin exposes the frozen lint/typecheck/test contract that
# the reusable ci.yml calls. A repo without all three cannot take the ci piece unchanged.
has_script_contract() {
  jq -e '.scripts | has("lint") and has("typecheck") and has("test")' >/dev/null 2>&1
}

# Emit a minimal .athena/config.json on stdout. Targets may be empty: a repo that is not a
# Worker or a VS Code extension should take no target layer rather than a wrong one.
build_athena_config() { # $1=stack $2=comma targets (may be empty) $3=comma tools
  jq -n \
    --arg stack "$1" \
    --arg targets "$2" \
    --arg tools "$3" \
    '{
       athenaVersion: "v1",
       stack: $stack,
       targets: ($targets | split(",") | map(select(length > 0))),
       tools: ($tools | split(",") | map(select(length > 0)))
     }'
}
