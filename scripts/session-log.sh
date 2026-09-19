#!/usr/bin/env bash
# Validate the session-log block at the bottom of an agent PR description.
#
#   bash scripts/session-log.sh < pr-body.md
#   gh pr view 42 --json body --jq .body | bash scripts/session-log.sh
#
# Why this exists: the session log is the only record of HOW a change was made, and the
# monthly harvest (handbook/cadences.md) is supposed to turn recurring mistakes into lint
# rules. Free prose cannot be counted, so the harvest has always been someone reading PRs
# by hand. These fields are the enumerated subset a program can tally — planning, gates,
# retries, abstention — chosen to match the process-discipline pillars the 2026 RigorBench
# work measures. The prose fields stay, because the dead ends are still the valuable part.
#
# Deliberately dependency-free: bash only, no jq, no python. It has to run anywhere a PR
# is reviewed, including a machine that never installed the project toolchain.
#
# Sourcing this file defines `validate_session_log` and runs nothing, so tests can call the
# function directly. Executing it reads stdin and exits non-zero on the first bad block.

set -uo pipefail

# Field name -> regex the value must match. An empty pattern means "any non-empty value".
# Kept as parallel arrays rather than an associative array so the order of reported
# problems is stable, which makes the test assertions readable.
SESSION_LOG_FIELDS=(
  'Tool/model'
  'Packet'
  'Plan'
  'Gates'
  'Retries'
  'Abstained'
  'Tried'
  'Dead ends'
  'Decisions and why'
)

SESSION_LOG_PATTERNS=(
  ''
  '^(#[0-9]+|none)$'
  '^(before-first-edit|mid-task|none)$'
  ''
  '^[0-9]+'
  '^(no|yes[[:space:]]*[—-].+)$'
  ''
  ''
  ''
)

# Print the value of "<field>:" from the block, or nothing when the line is absent. Only the
# first occurrence counts: a log that states Plan twice is reported as malformed rather than
# silently resolved to whichever line happened to come last.
#
# Trimming is parameter expansion rather than sed because one field name contains a slash
# ("Tool/model"), which sed reads as its own substitution delimiter.
session_log_field() { # $1=field $2=block
  local line
  line="$(printf '%s\n' "$2" | grep -m 1 -E "^[[:space:]]*$1:")"
  line="${line#*:}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  printf '%s' "$line"
}

session_log_field_count() { # $1=field $2=block
  printf '%s\n' "$2" | grep -c -E "^[[:space:]]*$1:" || true
}

# Validate a session-log block. Prints one problem per line; returns 1 if any were found.
validate_session_log() { # $1=text containing the block
  local text="$1" problems=0 index field pattern value count

  if ! printf '%s\n' "$text" | grep -q -E '^[[:space:]]*## Session log[[:space:]]*$'; then
    echo 'no "## Session log" heading — every agent PR body ends with one'
    return 1
  fi

  # Everything from the heading down. A PR body may carry prose above it; the block is the
  # last thing, so anything before the heading is not the log and must not be searched.
  local block
  block="$(printf '%s\n' "$text" | sed -n '/^[[:space:]]*## Session log[[:space:]]*$/,$p')"

  for index in "${!SESSION_LOG_FIELDS[@]}"; do
    field="${SESSION_LOG_FIELDS[$index]}"
    pattern="${SESSION_LOG_PATTERNS[$index]}"
    count="$(session_log_field_count "$field" "$block")"

    if [ "$count" -eq 0 ]; then
      printf 'missing field: %s\n' "$field"
      problems=$((problems + 1))
      continue
    fi
    if [ "$count" -gt 1 ]; then
      printf 'field stated %s times: %s\n' "$count" "$field"
      problems=$((problems + 1))
      continue
    fi

    value="$(session_log_field "$field" "$block")"
    if [ -z "$value" ]; then
      printf 'empty field: %s\n' "$field"
      problems=$((problems + 1))
      continue
    fi
    # A placeholder left unfilled reads as a completed field to every reader but a person.
    if printf '%s' "$value" | grep -q -E '^<.*>$|^…$|^\.\.\.$'; then
      printf 'placeholder left unfilled: %s\n' "$field"
      problems=$((problems + 1))
      continue
    fi
    if [ -n "$pattern" ] && ! printf '%s' "$value" | grep -q -E "$pattern"; then
      printf 'field %s does not match %s: %s\n' "$field" "$pattern" "$value"
      problems=$((problems + 1))
    fi
  done

  [ "$problems" -eq 0 ]
}

# Only when executed, never when sourced.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  body="$(cat)"
  if validate_session_log "$body"; then
    echo 'session log OK'
  else
    echo 'session log invalid — see handbook/templates/session-log.md' >&2
    exit 1
  fi
fi
