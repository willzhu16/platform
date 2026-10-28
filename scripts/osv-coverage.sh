#!/usr/bin/env bash
# Fail when osv-scanner read far fewer packages from a lockfile than the lockfile holds.
#
#   bash scripts/osv-coverage.sh <osv-json> [repo-dir] [scan-root]
#
# <osv-json> is osv-scanner's `--format=json --all-packages` output for the same checkout.
# [scan-root] is the directory osv-scanner ran in as it saw it, which prefixes every path in
# that output; inside the osv-scanner action that is /github/workspace, the default.
#
# A scanner that cannot read a lockfile finds no advisories in it, and that looks exactly like a
# clean lockfile. On 2026-10-26 the pnpm 12 Renovate PRs passed `security / osv` that way:
# osv-scanner 2.3.8 read only the first of the two YAML documents pnpm 12 writes, 15 packages
# of athena's 309, and nothing failed.
#
# This counts each committed lockfile itself and compares. It reports a lockfile osv-scanner
# did not list at all, and one where it read under OSV_COVERAGE_MIN_PERCENT of the packages.
# Two formats are counted, the two the fleet uses; others are not judged:
#
#   - pnpm-lock.yaml: distinct name@version keys under `snapshots:`, peer-dependency suffix
#     removed, across every YAML document in the file
#   - uv.lock: [[package]] blocks, the project's own entry included
#
# On 2026-10-27 osv-scanner 2.7.0 reported exactly these counts for athena, canary-worker,
# both selftest fixtures and the pnpm 12 lockfiles of all three repos. The threshold leaves
# room for the two to drift apart a little without letting a 5% read through.
#
# Read-only, no network; needs bash, git, awk and jq. Lockfiles come from `git ls-files`
# because osv-scanner skips git-ignored paths, so an untracked lockfile is not one it missed.
#
# Sourcing this file defines the functions and runs nothing, so tests call them directly.

set -uo pipefail

OSV_COVERAGE_MIN_PERCENT=90

# Committed lockfiles in the counted formats, one repo-relative path per line.
osv_lockfiles() { # $1=repo dir
  git -C "$1" ls-files -- ':(glob)**/pnpm-lock.yaml' ':(glob)**/uv.lock'
}

# How many distinct packages a lockfile pins, counted the way osv-scanner counts them.
osv_lockfile_count() { # $1=lockfile path
  case "${1##*/}" in
    uv.lock)
      grep -c '^\[\[package\]\]' "$1"
      ;;
    pnpm-lock.yaml)
      awk '
        /^---[[:space:]]*$/ { section = ""; next }
        /^[A-Za-z][A-Za-z0-9_]*:/ { section = $0; sub(/:.*/, "", section); next }
        section == "snapshots" && /^  [^ ]/ {
          key = substr($0, 3)
          sub(/:[[:space:]]*([{][}])?[[:space:]]*$/, "", key)
          gsub(/^['\''"]|['\''"]$/, "", key)
          sub(/[(].*/, "", key)
          seen[key] = 1
        }
        END { n = 0; for (k in seen) n++; print n }
      ' "$1"
      ;;
  esac
}

# How many packages osv-scanner listed for one lockfile, or nothing if it did not list it.
osv_scanned_count() { # $1=osv json, $2=lockfile path exactly as osv-scanner reported it
  jq -r --arg path "$2" \
    '[.results[]? | select(.source.path == $path) | .packages | length] | first // empty' "$1"
}

# One line per lockfile osv-scanner did not fully read, nothing at all when it read them all.
osv_coverage_findings() { # $1=osv json, $2=repo dir, $3=scan root as osv-scanner saw it
  local json="$1" root="$2" scan_root="$3"
  local rel expected scanned
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    expected="$(osv_lockfile_count "$root/$rel")"
    scanned="$(osv_scanned_count "$json" "$scan_root/$rel")"
    if [ "$expected" -eq 0 ]; then
      # An empty lockfile has nothing to miss. A non-empty one this cannot count is a format
      # change, and the first thing to learn is whether osv-scanner reads it either.
      if [ "${scanned:-0}" -gt 0 ]; then
        printf 'uncounted %s: osv-scanner read %s packages and this check counted none\n' \
          "$rel" "$scanned"
      fi
    elif [ -z "$scanned" ]; then
      printf 'unscanned %s: osv-scanner did not list it, so none of its %s packages were checked\n' \
        "$rel" "$expected"
    elif [ $((scanned * 100)) -lt $((expected * OSV_COVERAGE_MIN_PERCENT)) ]; then
      printf 'partial %s: osv-scanner read %s of %s packages; the rest were never checked\n' \
        "$rel" "$scanned" "$expected"
    fi
  done < <(osv_lockfiles "$root")
}

osv_coverage_main() {
  local json="${1:-}" root="${2:-.}" scan_root="${3:-/github/workspace}"
  if [ -z "$json" ]; then
    echo 'usage: osv-coverage.sh <osv-json> [repo-dir] [scan-root]' >&2
    return 2
  fi
  if ! jq -e '.results | type == "array"' "$json" >/dev/null 2>&1; then
    printf 'no package list at %s: the JSON scan did not finish, so coverage is unknown\n' \
      "$json" >&2
    return 1
  fi
  local findings
  findings="$(osv_coverage_findings "$json" "$root" "$scan_root")"
  if [ -n "$findings" ]; then
    printf '%s\n' "$findings" >&2
    return 1
  fi
  local rel files=0 expected=0 scanned=0
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    files=$((files + 1))
    expected=$((expected + $(osv_lockfile_count "$root/$rel")))
    scanned=$((scanned + $(osv_scanned_count "$json" "$scan_root/$rel" | grep . || echo 0)))
  done < <(osv_lockfiles "$root")
  if [ "$files" -eq 0 ]; then
    echo 'PASS  no pnpm-lock.yaml or uv.lock is committed, so there is nothing to compare'
  else
    printf 'PASS  osv-scanner read %s of %s packages across %s lockfile(s)\n' \
      "$scanned" "$expected" "$files"
  fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  osv_coverage_main "$@"
fi
