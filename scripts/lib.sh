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
