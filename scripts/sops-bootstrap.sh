#!/usr/bin/env bash
# Put a real age recipient into a project's .sops.yaml, once, so sops can encrypt.
#
#   bash scripts/sops-bootstrap.sh <repo-dir>                        # new per-project key
#   bash scripts/sops-bootstrap.sh <repo-dir> --recipient age1...    # reuse a key you hold
#   bash scripts/sops-bootstrap.sh <repo-dir> --key-out <path>
#
# The cf-worker-app template ships .sops.yaml with a placeholder recipient, so every generated
# repo starts unable to encrypt anything, and the backlog item asking for a shared recipient
# could not be satisfied by committing one: a key in a public template is a key everybody has,
# and one private half would then decrypt every project in the fleet.
#
# So the choice stays with you, and --recipient is how you make it. Generate a key once, pass
# the same public half to every project, and you have the shared arrangement. Pass nothing and
# you get a fresh key for this project alone, which is the safer default because one leak then
# exposes one project.
#
# THE PRIVATE KEY IS NEVER PRINTED AND NEVER COMMITTED. When this script generates one it goes
# to a file outside the repo, mode 0600, and the path is reported. Move it into Bitwarden,
# which is where setup-machine.sh already expects the age key to live, then delete the file.
# Nothing here sends it anywhere. No agent should read it, and the t1 permission profile plus
# the sandbox profile both deny the paths it belongs in.
#
# It writes one line of one file (the `age:` line in .sops.yaml) and never commits, pushes or
# encrypts anything of yours. A bad run is undone with `git checkout -- .sops.yaml`.

set -euo pipefail

REPO_DIR=''
RECIPIENT=''
KEY_OUT=''

usage() {
  sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

fail() {
  printf 'sops-bootstrap: %s\n' "$1" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --recipient) RECIPIENT="${2:-}"; shift 2 ;;
    --key-out) KEY_OUT="${2:-}"; shift 2 ;;
    -h | --help) usage 0 ;;
    -*) fail "unknown option: $1" ;;
    *) REPO_DIR="$1"; shift ;;
  esac
done

[ -n "$REPO_DIR" ] || usage 2
[ -d "$REPO_DIR" ] || fail "no such directory: $REPO_DIR"
# --key-out only names where a GENERATED key lands, so pairing it with a recipient you already
# hold would report a path nothing was ever written to.
[ -n "$RECIPIENT" ] && [ -n "$KEY_OUT" ] \
  && fail '--recipient and --key-out are mutually exclusive: nothing is generated with a recipient'

SOPS_FILE="$REPO_DIR/.sops.yaml"
[ -f "$SOPS_FILE" ] || fail "no .sops.yaml in $REPO_DIR (is this a cf-worker-app project?)"

# A real age public key is "age1" plus 58 characters of bech32, which excludes b, i, o and 1.
# Validated before anything is written: a typo'd recipient produces files nobody can decrypt,
# and that is only discovered when someone needs them.
if [ -n "$RECIPIENT" ]; then
  case "$RECIPIENT" in
    age1[023456789acdefghjklmnpqrstuvwxyz]*)
      [ "${#RECIPIENT}" -eq 62 ] || fail "recipient is ${#RECIPIENT} characters, expected 62"
      ;;
    *) fail "recipient does not look like an age public key: $RECIPIENT" ;;
  esac
else
  command -v age-keygen >/dev/null 2>&1 \
    || fail 'age-keygen not found (setup-machine.sh installs age), or pass --recipient'
  if [ -z "$KEY_OUT" ]; then
    KEY_OUT="$HOME/.config/sops/age/$(basename "$(cd "$REPO_DIR" && pwd)").agekey"
  fi
  [ -e "$KEY_OUT" ] && fail "key file already exists, refusing to overwrite: $KEY_OUT"
  mkdir -p "$(dirname "$KEY_OUT")"
  # age-keygen writes the private key to the file and the public half to stderr. stderr is
  # dropped and the public half read back from the file's comment line, so no key material is
  # ever interpolated into a message this script prints.
  ( umask 077 && age-keygen -o "$KEY_OUT" 2>/dev/null )
  chmod 600 "$KEY_OUT"
  RECIPIENT="$(sed -n 's/^# public key: \(age1[0-9a-z]*\)$/\1/p' "$KEY_OUT" | head -1)"
  [ -n "$RECIPIENT" ] || fail "could not read the public key back from $KEY_OUT"
fi

# Rewrite only the age: line, so comments and creation_rules survive verbatim.
grep -q '^\( *\)age: age1' "$SOPS_FILE" \
  || fail "no 'age: age1...' line in $SOPS_FILE — configure it by hand"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
sed "s|^\( *\)age: age1.*|\1age: $RECIPIENT|" "$SOPS_FILE" >"$tmp"
cat "$tmp" >"$SOPS_FILE"

printf 'recipient written to %s\n' "$SOPS_FILE"
if [ -n "$KEY_OUT" ]; then
  printf '\nPrivate key: %s (mode 0600, NOT printed, NOT in the repo)\n' "$KEY_OUT"
  printf 'Move it into Bitwarden and delete the file. Losing it means losing every\n'
  printf 'secret encrypted to this recipient; leaking it means losing all of them.\n'
fi

# Prove the configuration works rather than asserting it. A recipient that parses but cannot
# encrypt is the failure this catches, and it costs one throwaway file.
if command -v sops >/dev/null 2>&1; then
  probe="$REPO_DIR/secrets/.sops-bootstrap-probe.env"
  mkdir -p "$REPO_DIR/secrets"
  printf 'PROBE=not-a-secret\n' >"$probe"
  if sops --config "$SOPS_FILE" -e "$probe" 2>/dev/null | grep -qF 'ENC[AES256_GCM'; then
    printf '\nverified: sops encrypts secrets/*.env to this recipient\n'
    rm -f "$probe"
  else
    rm -f "$probe"
    fail 'sops could not encrypt with the new recipient — .sops.yaml is written but unverified'
  fi
else
  printf '\nsops not installed, so encryption was NOT verified. Run scripts/sops-check.sh\n'
  printf 'before committing anything under secrets/.\n'
fi
