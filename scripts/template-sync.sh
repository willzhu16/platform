#!/usr/bin/env bash
# Update a generated repo's template files to a platform release with `copier update`.
#
#   bash scripts/template-sync.sh <ref> [repo-dir]
#
# Template fixes reach an existing repo only through `copier update`. Until now that was a
# monthly checklist item, and it did not happen: on 2026-10-29 canary-worker still recorded
# v1.7.0 (2026-09-11), seven releases behind. The reusable template-sync.yml runs this weekly
# in every generated repo and opens what it changes as one PR, the way athena-sync does for
# the instruction files.
#
# Prints one line saying what happened:
#
#   current <ref>                         the repo already records <ref>; nothing ran
#   updated <old> -> <ref>                files changed and none carries a conflict
#   conflicts <old> -> <ref>: <files>     copier could not merge these; the PR shows markers
#
# The repo must be a clean git checkout, untracked files included, or copier refuses to run.
# A lockfile is refreshed after the update when its manifest changed and the package manager
# is on PATH, because the templates ship no lockfile and a stale one fails `--frozen-lockfile`
# in CI before anything useful is checked.
#
# Sourcing this file defines the functions and runs nothing, so tests call them directly.

set -uo pipefail

# The template version a repo was last rendered or updated from.
template_sync_recorded() { # $1=repo dir
  awk '/^_commit:/ { sub(/^_commit:[[:space:]]*/, ""); gsub(/["'\'']/, ""); print; exit }' \
    "$1/.copier-answers.yml"
}

# Changed files carrying copier's inline conflict markers, plus any .rej it left, one per line.
template_sync_conflicts() { # $1=repo dir
  local file
  while IFS= read -r file; do
    [ -f "$1/$file" ] || continue
    case "$file" in
      *.rej) printf '%s\n' "$file"; continue ;;
    esac
    if grep -qE '^(<<<<<<< |>>>>>>> )' "$1/$file"; then
      printf '%s\n' "$file"
    fi
  done < <(git -C "$1" status --porcelain --untracked-files=all | cut -c4-)
}

# The one call to copier, kept apart so tests can stand it in.
template_sync_copier() { # $@=copier arguments, run inside the repo
  uvx --from copier copier "$@"
}

template_sync_refresh_lockfiles() { # $1=repo dir
  local changed
  changed="$(git -C "$1" status --porcelain | cut -c4-)"
  if grep -qx 'package.json' <<<"$changed" && [ -f "$1/pnpm-lock.yaml" ] \
    && command -v pnpm >/dev/null; then
    (cd "$1" && pnpm install --lockfile-only --ignore-scripts) >&2
  fi
  if grep -qx 'pyproject.toml' <<<"$changed" && [ -f "$1/uv.lock" ] \
    && command -v uv >/dev/null; then
    (cd "$1" && uv lock) >&2
  fi
}

template_sync_main() {
  local ref="${1:-}" root="${2:-.}"
  if [ -z "$ref" ]; then
    echo 'usage: template-sync.sh <ref> [repo-dir]' >&2
    return 2
  fi
  local recorded
  recorded="$(template_sync_recorded "$root")"
  if [ "$recorded" = "$ref" ]; then
    printf 'current %s\n' "$ref"
    return 0
  fi
  (cd "$root" && template_sync_copier update --defaults --vcs-ref "$ref" --conflict inline) >&2 \
    || return 1
  local conflicts
  conflicts="$(template_sync_conflicts "$root")"
  if [ -n "$conflicts" ]; then
    printf 'conflicts %s -> %s: %s\n' "$recorded" "$ref" "$(paste -sd ' ' <<<"$conflicts")"
    return 0
  fi
  template_sync_refresh_lockfiles "$root"
  printf 'updated %s -> %s\n' "$recorded" "$ref"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  template_sync_main "$@"
fi
