#!/usr/bin/env bash
# Adopt an EXISTING repo into Artemis, one piece at a time.
#
#   scripts/adopt-project.sh <repo-dir>                      # report only, writes nothing
#   scripts/adopt-project.sh <repo-dir> --with security
#   scripts/adopt-project.sh <repo-dir> --with security,ci,instructions --stack ts
#
# new-project.sh is the only adoption path Artemis had, and it builds a repo from a
# template — useless for a repo that already has history. This fills that gap, and it is
# deliberately a la carte: the launch-start review showed the realistic answer is usually
# "take the security scanning, leave the CI and the ruleset alone", not all or nothing.
#
# It writes files into <repo-dir> and stops there. It never commits, never pushes, never
# creates a repo and never applies a ruleset, so a bad run is undone with `git checkout`.
#
# Default is report-only. Run it with no --with first: the preflight is the point, and the
# blockers it prints are the reason a retrofit goes wrong.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

REPO_DIR=''
PIECES=''
OWNER='willzhu16'
STACK='ts'
TARGETS=''
TOOLS='claude'
FORCE=''

usage() {
  sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --with) PIECES="${2:-}"; shift 2 ;;
    --owner) OWNER="${2:-}"; shift 2 ;;
    --stack) STACK="${2:-}"; shift 2 ;;
    --targets) TARGETS="${2:-}"; shift 2 ;;
    --tools) TOOLS="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage 0 ;;
    -*) echo "unknown flag: $1" >&2; usage 1 ;;
    *)
      [ -z "$REPO_DIR" ] || { echo 'only one repo directory may be given' >&2; exit 1; }
      REPO_DIR="$1"; shift ;;
  esac
done

[ -n "$REPO_DIR" ] || usage 1
[ -d "$REPO_DIR" ] || { echo "not a directory: ${REPO_DIR}" >&2; exit 1; }
[ -d "${REPO_DIR}/.git" ] || { echo "not a git repo: ${REPO_DIR}" >&2; exit 1; }

blockers=0

say()   { printf '  %-8s %s\n' "$1" "$2"; }
ok()    { say 'ok' "$1"; }
note()  { say 'note' "$1"; }
# A warning is about what would happen LATER (applying the ruleset, pinning to @v1); it
# never stops a write. Only something this script is about to break itself is a blocker.
warn()  { say 'warn' "$1"; }
block() { say 'BLOCK' "$1"; blockers=$((blockers + 1)); }

echo "Preflight: ${REPO_DIR}"

# 1. Already adopted?
if [ -f "${REPO_DIR}/.athena/config.json" ]; then
  note '.athena/config.json exists — this repo is already athena-managed'
else
  note 'no .athena/config.json — agents here get no compiled rules and no permission profile'
fi

# 2. The ruleset-versus-bot conflict. This is the one that actually breaks a live repo.
pushers=''
if [ -d "${REPO_DIR}/.github/workflows" ]; then
  for wf in "${REPO_DIR}"/.github/workflows/*.y*ml; do
    [ -e "$wf" ] || continue
    if workflow_pushes_directly < "$wf"; then
      pushers="${pushers}${pushers:+, }$(basename "$wf")"
    fi
  done
fi
if [ -n "$pushers" ]; then
  # Deliberately a warning, not a blocker. This script never applies the ruleset, so the
  # conflict is with a step you may never take — refusing to write security.yml over it
  # would withhold the one piece that is always safe.
  warn "pushes to a branch directly: ${pushers}"
  say '' 'the Artemis main ruleset requires pull requests, so applying it would reject'
  say '' 'that job. Move it to a PR first, or simply never adopt the ruleset here.'
else
  ok 'no workflow pushes directly to a branch'
fi

# 3. Script contract, required by the ci piece only.
if [ -f "${REPO_DIR}/package.json" ]; then
  if has_script_contract < "${REPO_DIR}/package.json"; then
    ok 'package.json exposes lint, typecheck and test'
  else
    note 'package.json lacks one of lint/typecheck/test — the ci piece needs all three'
  fi
else
  note 'no package.json — the ci piece is for Node projects; see ci-python.yml otherwise'
fi

# 4. Workflows we would overwrite. Only a blocker when that piece was actually requested:
# an existing ci.yml is none of our business unless --with ci is asked for.
for piece in security ci codeql; do
  if [ -f "${REPO_DIR}/.github/workflows/${piece}.yml" ]; then
    if printf '%s' ",${PIECES}," | grep -q ",${piece}," && [ -z "$FORCE" ]; then
      block "${piece}.yml already exists and --with ${piece} would overwrite it"
      say '' 'pass --force to replace it, after checking what the existing one does.'
    else
      note "${piece}.yml already exists (not requested, leaving it alone)"
    fi
  fi
done

# 5. Blast radius, worth stating out loud.
note 'adopting ci or codeql pins this repo to the moving @v1 tag: a bad platform release'
say '' 'reaches it on the next run, with no staged rollout. security is the safest piece.'

echo
if [ -z "$PIECES" ]; then
  echo 'Report only. Re-run with --with security[,ci,codeql,instructions] to write files.'
  exit 0
fi

if [ "$blockers" -gt 0 ]; then
  echo "Refusing to write: ${blockers} blocker(s) above. Resolve them, or pick fewer pieces." >&2
  exit 1
fi

echo "Writing into ${REPO_DIR}:"
mkdir -p "${REPO_DIR}/.github/workflows"

IFS=','
for piece in $PIECES; do
  case "$piece" in
    security|ci|codeql)
      render_caller_workflow "$piece" "$OWNER" > "${REPO_DIR}/.github/workflows/${piece}.yml"
      echo "  .github/workflows/${piece}.yml"
      ;;
    instructions)
      mkdir -p "${REPO_DIR}/.athena"
      build_athena_config "$STACK" "$TARGETS" "$TOOLS" > "${REPO_DIR}/.athena/config.json"
      echo '  .athena/config.json'
      ;;
    '') ;;
    *) echo "unknown piece: ${piece}" >&2; exit 1 ;;
  esac
done
unset IFS

cat <<'NEXT'

Next, by hand:
  - review the diff, then commit on a branch and open a PR
  - for 'instructions': run `pnpm compile <repo-dir>` from the athena repo, which writes
    CLAUDE.md and .claude/ — then commit those too
  - the branch ruleset is NOT applied by this script. Apply it only once nothing pushes
    to the default branch directly.
NEXT
