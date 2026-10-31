#!/usr/bin/env bash
# Move `v1` onto the release `canary` points at, once a real repo has run it.
#
#   PLATFORM_REPO=owner/platform CANARY_REPO=owner/canary-worker bash scripts/canary-promote.sh [--dry-run]
#
# A release used to move `v1` the moment it was cut, so every repo in the fleet ran it on its
# next CI run and nothing real had run it first: 1.13.1 broke `security / semgrep` everywhere
# that way. Releases now move `canary` instead. While canary and v1 differ, each run of
# canary-worker's hourly canary.yml runs each reusable workflow twice, once at @v1 (jobs named
# stable-*) and once at @canary (canary-*). This reads the newest completed run that started after the
# release and moves v1 only when no job passes on v1 and fails on canary.
#
# Comparing the two is the point. canary-worker sometimes fails a check for its own reasons
# (osv was red there for over a week in October), and a check that fails on both is not the
# release's doing. A job present on one side only does count, because job and check names are
# a frozen contract. A flaky failure clears itself: the next hourly run is judged afresh.
#
# Everything read is public, so the default GITHUB_TOKEN is enough; dispatching
# update-major-tag.yml is the one write. A release with no canary run after
# CANARY_MAX_WAIT_SECONDS fails the run, because that means canary.yml is broken or disabled
# and v1 would otherwise never move. Moving v1 by hand still works for an urgent fix:
#   gh workflow run update-major-tag.yml -f tag=vX.Y.Z
#
# Sourcing this file defines the functions and runs nothing, so tests call them directly.

set -uo pipefail

# A day, not the six hours this started at. GitHub fires an hourly schedule hours apart: the
# first nine runs of promote-canary.yml, in October 2026, came 3.5 to 6.8 hours apart. Six
# hours would have failed ordinary releases; a day still catches a disabled canary.yml.
CANARY_MAX_WAIT_SECONDS=86400
# A run counts only if it started this long after the release, so it cannot have resolved
# @canary in the seconds before the release workflow moved the tag.
CANARY_SETTLE_SECONDS=300

# One line per job that holds the release back, nothing when none does.
canary_regressions() { # $1=jobs JSON: [{"name": ..., "conclusion": ...}]
  jq -r '
    def ok: . == "success" or . == "skipped" or . == "neutral";
    (map({key: .name, value: (.conclusion // "")}) | from_entries) as $by
    | ([.[].name | select(startswith("canary-"))][] as $c
        | ("stable-" + ($c | ltrimstr("canary-"))) as $s
        | if ($by[$c] | ok) then empty
          elif ($by | has($s) | not) then "unpaired \($c): no \($s) ran to compare it with"
          elif $by[$s] == "success" then "regressed \($c): \($by[$c]) on canary, success on v1"
          else empty end),
      ([.[].name | select(startswith("stable-"))][] as $s
        | ("canary-" + ($s | ltrimstr("stable-"))) as $c
        | if ($by | has($c)) then empty
          else "missing \($c): \($s) ran on v1 and canary has no such job" end)
  ' "$1"
}

# A PASS line when the release may move v1; otherwise the reasons on stderr and exit 1.
canary_verdict() { # $1=jobs JSON
  local ran regressions both
  ran="$(jq '[.[] | select((.name | startswith("canary-")) and .conclusion != "skipped")] | length' "$1")"
  if [ "$ran" -eq 0 ]; then
    echo 'no canary job ran, so there is nothing to judge the release by' >&2
    return 1
  fi
  regressions="$(canary_regressions "$1")"
  if [ -n "$regressions" ]; then
    printf '%s\n' "$regressions" >&2
    return 1
  fi
  both="$(jq '
    def ok: . == "success" or . == "skipped" or . == "neutral";
    [.[] | select((.name | startswith("canary-")) and ((.conclusion // "") | ok | not))] | length
  ' "$1")"
  printf 'PASS  %s canary job(s) match v1 (%s fail on both and are not held against the release)\n' \
    "$ran" "$both"
}

canary_promote_main() {
  local dry_run=''
  if [ "${1:-}" = '--dry-run' ]; then dry_run=1; fi
  local repo="${PLATFORM_REPO:?set PLATFORM_REPO}" canary_repo="${CANARY_REPO:?set CANARY_REPO}"
  local canary v1
  canary="$(gh api "repos/$repo/git/ref/tags/canary" --jq .object.sha 2>/dev/null)"
  if [ -z "$canary" ]; then
    echo 'nothing to promote: there is no canary tag yet'
    return 0
  fi
  v1="$(gh api "repos/$repo/git/ref/tags/v1" --jq .object.sha)"
  if [ "$canary" = "$v1" ]; then
    echo 'nothing to promote: v1 is already at the canary release'
    return 0
  fi
  local tag
  tag="$(gh api "repos/$repo/git/matching-refs/tags/v" --jq '.[] | "\(.object.sha)\t\(.ref)"' |
    release_tag_at "$canary")"
  if [ -z "$tag" ]; then
    echo "canary points at $canary, and no vX.Y.Z release tag marks that commit" >&2
    return 1
  fi
  local published now since query run
  published="$(date -d "$(gh api "repos/$repo/releases/tags/$tag" --jq .published_at)" +%s)"
  now="${CANARY_NOW:-$(date +%s)}"
  since="$(date -u -d "@$((published + CANARY_SETTLE_SECONDS))" +%Y-%m-%dT%H:%M:%SZ)"
  query="status=completed&created=%3E%3D$since&per_page=1"
  # A failed read must not pass for "no run yet": that would wait quietly, then blame canary.yml.
  if ! run="$(gh api "repos/$canary_repo/actions/workflows/canary.yml/runs?$query" \
    --jq '.workflow_runs[0].id // empty')"; then
    echo "could not read canary runs from $canary_repo" >&2
    return 1
  fi
  if [ -z "$run" ]; then
    if [ $((now - published)) -gt "$CANARY_MAX_WAIT_SECONDS" ]; then
      printf '%s has waited over %s hours with no canary run; check canary.yml in %s\n' \
        "$tag" "$((CANARY_MAX_WAIT_SECONDS / 3600))" "$canary_repo" >&2
      return 1
    fi
    echo "waiting: no completed canary run of $tag yet"
    return 0
  fi
  local jobs verdict
  jobs="$(mktemp)"
  if ! gh api "repos/$canary_repo/actions/runs/$run/jobs?per_page=100" \
    --jq '[.jobs[] | {name, conclusion}]' >"$jobs"; then
    echo "could not read the jobs of canary run $run" >&2
    return 1
  fi
  if ! verdict="$(canary_verdict "$jobs")"; then
    echo "holding v1: canary run $run did not clear $tag" >&2
    return 1
  fi
  echo "$verdict"
  if [ -n "$dry_run" ]; then
    echo "dry run: would move v1 to $tag"
    return 0
  fi
  gh workflow run update-major-tag.yml --repo "$repo" --ref main -f "tag=$tag"
  echo "promoted: dispatched update-major-tag.yml to move v1 to $tag"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  # shellcheck source=scripts/lib.sh
  . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
  canary_promote_main "$@"
fi
