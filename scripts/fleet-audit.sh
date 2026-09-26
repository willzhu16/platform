#!/usr/bin/env bash
# Report repos that should be athena-managed and are not.
#
#   bash scripts/fleet-audit.sh                       # queries GitHub via gh
#   bash scripts/fleet-audit.sh --owner <login>
#   bash scripts/fleet-audit.sh --inventory <file>    # offline, from a TSV inventory
#   bash scripts/fleet-audit.sh --fleet-file <file>
#
# athena-sync.yml is a reusable workflow that each managed repo calls FOR ITSELF. Nothing
# holds a list of the fleet, so a project built without the harness is never looked at by
# anything — launch-start was created 2026-07-04 and is unmanaged still.
#
# The naive version of this check is worthless. 26 of the owner's 27 repos are unmanaged and
# nearly all of them legitimately: coursework, dead prototypes, and the tooling repos
# themselves. Two narrowings turn the output into a decision list instead of noise.
#
#   - An epoch. A repo created before Artemis existed was never a candidate.
#   - An acknowledgement list. fleet/unmanaged.json records a deliberate opt-out, and why.
#
# What survives both — in scope, unmanaged, and nobody has written down why — is a decision
# waiting to be made. Either remedy is one step:
#
#   scripts/adopt-project.sh <repo-dir>   # take some or all of the harness
#   fleet/unmanaged.json                  # record why it stays outside
#
# It also reports a STALE acknowledgement: an entry for a repo since adopted, or for one that
# no longer exists. This file's value is that its silence means something, so an entry nobody
# prunes is a defect in it.
#
# NOT checked here: a repo holding .copier-answers.yml that has lost its .athena/config.json.
# That repo's own weekly sync job runs `doctor` and goes red by itself, so a rule for it would
# only restate what its own CI already says.
#
# Read-only. It writes nothing and adopts nothing. Needs bash and jq; the default mode also
# needs gh authenticated against the owner. --inventory needs no network, which is how the
# tests exercise the logic.
#
# THE TOKEN HAS TO SEE PRIVATE REPOS. 12 of the owner's 27 are private, including 4 of the 8
# in scope and `artemis`, which is acknowledged below. A repo-scoped GITHUB_TOKEN lists only
# public repos, so a run under one drops most of the real findings AND reports acknowledged
# private repos as absent — wrong in both directions at once, which is worse than not running.
# An interactive `gh auth login` is fine; in Actions it needs AUTOMATION_TOKEN.
#
# The inventory is one repo per line, tab-separated:
#
#   <name><TAB><created YYYY-MM-DD><TAB><yes|no|->
#
# The third field says whether .athena/config.json exists. "-" means "not looked at", which
# is what an out-of-scope repo gets, since the audit never asks GitHub about one.
#
# Sourcing this file defines the functions and runs nothing, so tests call them directly.

set -uo pipefail

# A reason copied from an example and left unfilled is worse than a missing one: it reads as
# a decision that was made. Same guard session-log.sh applies to its fields.
FLEET_PLACEHOLDER_RE='<[a-z][a-z -]*>'

# Kinds are padded to one width so a run reads as columns.
fleet_report_line() { # $1=kind $2=subject $3=detail
  printf '%-9s %s — %s\n' "$1" "$2" "$3"
}

# The whole audit as a pure function: acknowledgement file in $1, inventory on stdin, one
# line per problem on stdout, nothing at all when the fleet is consistent.
fleet_findings() { # $1=acknowledgement file
  local fleet_file="$1"
  local epoch ack_tsv
  epoch="$(jq -r '.epoch // empty' "$fleet_file" 2>/dev/null)"
  if [ -z "$epoch" ]; then
    fleet_report_line config "$fleet_file" \
      'unreadable, or no "epoch" field: cannot tell which repos are in scope'
    return 0
  fi
  case "$epoch" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *)
      fleet_report_line config "$fleet_file" "epoch \"$epoch\" is not a YYYY-MM-DD date"
      return 0
      ;;
  esac

  ack_tsv="$(jq -r '.acknowledged[]? | [(.repo // ""), (.reason // "")] | @tsv' "$fleet_file" 2>/dev/null)"
  local -a ack_repo=() ack_reason=()
  local repo reason
  while IFS=$'\t' read -r repo reason; do
    [ -n "$repo$reason" ] || continue
    ack_repo+=("$repo")
    ack_reason+=("$reason")
  done <<<"$ack_tsv"

  local index
  for index in "${!ack_repo[@]}"; do
    if [ -z "${ack_repo[$index]}" ]; then
      fleet_report_line config "$fleet_file" "acknowledged entry $((index + 1)) has no repo name"
    elif [ -z "${ack_reason[$index]}" ]; then
      fleet_report_line config "${ack_repo[$index]}" \
        'acknowledged with no reason; say why it stays outside the fleet'
    elif [[ "${ack_reason[$index]}" =~ $FLEET_PLACEHOLDER_RE ]]; then
      fleet_report_line config "${ack_repo[$index]}" \
        "reason is still a placeholder: ${ack_reason[$index]}"
    fi
  done

  local -a inventory_name=() inventory_created=() inventory_managed=()
  local name created managed
  while IFS=$'\t' read -r name created managed; do
    [ -n "$name" ] || continue
    inventory_name+=("$name")
    inventory_created+=("$created")
    inventory_managed+=("${managed:--}")
  done

  # An empty inventory must never read as a clean fleet. A failed gh call, a typo'd path, an
  # owner with no repos: each produces no lines, and silence would be reported as PASS — the
  # audit claiming it checked something it never saw.
  if [ "${#inventory_name[@]}" -eq 0 ]; then
    fleet_report_line config inventory 'no repos read — nothing was checked'
    return 0
  fi

  local acknowledged
  for index in "${!inventory_name[@]}"; do
    [[ "${inventory_created[$index]}" < "$epoch" ]] && continue
    [ "${inventory_managed[$index]}" = 'yes' ] && continue
    acknowledged=''
    for repo in "${ack_repo[@]:-}"; do
      [ "$repo" = "${inventory_name[$index]}" ] && { acknowledged=1; break; }
    done
    [ -n "$acknowledged" ] && continue
    fleet_report_line unmanaged "${inventory_name[$index]}" \
      "created ${inventory_created[$index]}, no .athena/config.json and no entry in fleet/unmanaged.json"
  done

  local found state probe
  for index in "${!ack_repo[@]}"; do
    repo="${ack_repo[$index]}"
    [ -n "$repo" ] || continue
    found=''
    state='-'
    for probe in "${!inventory_name[@]}"; do
      if [ "${inventory_name[$probe]}" = "$repo" ]; then
        found=1
        state="${inventory_managed[$probe]}"
        break
      fi
    done
    if [ -z "$found" ]; then
      # Deliberately not "deleted": a repo the token cannot see is absent from the listing in
      # exactly the same way, and 12 of the owner's 27 repos are private. Naming one cause
      # would make a token problem read as a fleet fact.
      fleet_report_line stale "$repo" \
        'acknowledged, but absent from the inventory: deleted, renamed, or invisible to this token'
    elif [ "$state" = 'yes' ]; then
      fleet_report_line stale "$repo" \
        'acknowledged as unmanaged, but it now has .athena/config.json; remove the entry'
    fi
  done
}

# Build the inventory from GitHub. Acknowledged names arrive on stdin, because an acknowledged
# repo has to be looked at even when the epoch would skip it — that is the only way a stale
# entry gets noticed. Everything else out of scope is reported as "-" and costs no API call:
# 8 requests on this fleet instead of 27.
fleet_inventory() { # $1=owner $2=epoch
  local owner="$1" epoch="$2"
  local -a acknowledged=()
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && acknowledged+=("$line")
  done

  local name created managed in_scope repo
  while IFS=$'\t' read -r name created; do
    [ -n "$name" ] || continue
    in_scope=''
    [[ "$created" < "$epoch" ]] || in_scope=1
    for repo in "${acknowledged[@]:-}"; do
      [ "$repo" = "$name" ] && { in_scope=1; break; }
    done
    managed='-'
    if [ -n "$in_scope" ]; then
      if gh api "repos/$owner/$name/contents/.athena/config.json" --jq .sha >/dev/null 2>&1; then
        managed='yes'
      else
        managed='no'
      fi
    fi
    printf '%s\t%s\t%s\n' "$name" "$created" "$managed"
  done < <(gh repo list "$owner" --limit 200 --json name,createdAt \
    --jq '.[] | [.name, .createdAt[:10]] | @tsv' | sort)
}

fleet_audit_main() {
  local owner='willzhu16' inventory='' fleet_file='' here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fleet_file="$(dirname "$here")/fleet/unmanaged.json"
  while [ $# -gt 0 ]; do
    case "$1" in
      --owner) owner="${2:-}"; shift 2 ;;
      --inventory) inventory="${2:-}"; shift 2 ;;
      --fleet-file) fleet_file="${2:-}"; shift 2 ;;
      -h|--help) sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; return 0 ;;
      *) printf 'unknown argument: %s\n' "$1" >&2; return 2 ;;
    esac
  done
  command -v jq >/dev/null 2>&1 || { echo 'fleet-audit needs jq' >&2; return 2; }

  local findings epoch
  if [ -n "$inventory" ]; then
    findings="$(fleet_findings "$fleet_file" <"$inventory")"
  else
    command -v gh >/dev/null 2>&1 \
      || { echo 'fleet-audit needs gh, or an --inventory file' >&2; return 2; }
    epoch="$(jq -r '.epoch // empty' "$fleet_file" 2>/dev/null)"
    if [ -z "$epoch" ]; then
      # No usable epoch means no way to decide scope, so skip the API calls entirely and let
      # fleet_findings report the broken file.
      findings="$(fleet_findings "$fleet_file" </dev/null)"
    else
      findings="$(jq -r '.acknowledged[]?.repo // empty' "$fleet_file" \
        | fleet_inventory "$owner" "$epoch" \
        | fleet_findings "$fleet_file")"
    fi
  fi

  if [ -z "$findings" ]; then
    echo 'PASS  every repo in scope is athena-managed or acknowledged'
    return 0
  fi
  printf '%s\n' "$findings"
  printf '\n%d finding(s). Adopt with scripts/adopt-project.sh, or record why in fleet/unmanaged.json\n' \
    "$(printf '%s\n' "$findings" | wc -l)"
  return 1
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  fleet_audit_main "$@"
fi
